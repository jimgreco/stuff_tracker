import Foundation
import SwiftData
import Combine

@MainActor
final class LocalDataManager: ObservableObject {
    static let shared = LocalDataManager()

    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?
    private var legacyContainer: ModelContainer?
    private var memoryStores: [String: ModelContainer] = [:]
    private let accountDefaults: UserDefaults
    private let inMemory: Bool
    private let storageRoot: URL
    private let legacyURL: URL?
    private var startupError: Error?
    private(set) var boundAccountID: String?
    @Published private(set) var storeGeneration = UUID()
    static let accountOwnerKey = "local_inventory_owner_user_id_v1"

    // One atomic catalog publishes both the verified store and legacy ownership.
    // Unpublished attempt directories are never reused or removed automatically.
    private struct Catalog: Codable {
        var version = 1
        var accounts: [String: String] = [:]
        var legacyClaimedBy: String?
    }
    private var catalog = Catalog()
    enum MigrationCheckpoint { case archived, imported, published }
    var migrationCheckpoint: ((MigrationCheckpoint) throws -> Void)?
    enum AccountAccess: Equatable { case allowed, claimRequired }

    init(inMemory: Bool = false, accountDefaults: UserDefaults = .standard,
         storageRoot: URL? = nil, legacyURL: URL? = nil) {
        self.accountDefaults = accountDefaults
        self.inMemory = inMemory
        self.storageRoot = storageRoot ?? (inMemory
            ? FileManager.default.temporaryDirectory.appendingPathComponent("cubby-test-\(UUID().uuidString)")
            : URL.applicationSupportDirectory.appendingPathComponent("CubbyAccounts", isDirectory: true))
        self.legacyURL = legacyURL
        do {
            if !inMemory, FileManager.default.fileExists(atPath: catalogURL.path) {
                catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: catalogURL))
                guard catalog.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
            }
            // Existing installations stay locked until their server identity is verified.
            if inMemory || (!accountDefaults.bool(forKey: AuthStore.completedAuthenticationDefaultsKey)
                            && accountDefaults.string(forKey: Self.accountOwnerKey) == nil
                            && catalog.accounts.isEmpty) {
                let legacy = try openLegacy()
                modelContainer = legacy
                modelContext = ModelContext(legacy)
                modelContext?.autosaveEnabled = false
            }
        } catch { startupError = error }
    }

    private var catalogURL: URL { storageRoot.appendingPathComponent("catalog.json") }
    private var archiveURL: URL { storageRoot.appendingPathComponent("legacy-recovery.json") }
    private var schema: Schema { Schema([LocalHome.self, LocalLocation.self, LocalItem.self, SyncOperation.self]) }

    private func makeContainer(url: URL?) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else if let url {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            // Keep the shipped default.store path exactly; never repurpose it.
            configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func openLegacy() throws -> ModelContainer {
        if let legacyContainer { return legacyContainer }
        let container = try makeContainer(url: legacyURL)
        legacyContainer = container
        return container
    }

    func deactivateAccount() {
        // Saves at every editing boundary already occurred. Disable autosave so a
        // detached view/model cannot later persist into a different account.
        modelContext?.autosaveEnabled = false
        modelContext = nil
        modelContainer = nil
        boundAccountID = nil
        storeGeneration = UUID()
    }

    private func legacyArchive() throws -> InventoryArchive {
        if let startupError { throw startupError }
        if let modelContext, boundAccountID == nil { try modelContext.save() }
        let archive = try InventoryArchive(context: ModelContext(openLegacy()))
        if !inMemory, FileManager.default.fileExists(atPath: archiveURL.path) {
            let saved = try JSONDecoder().decode(InventoryArchive.self, from: Data(contentsOf: archiveURL))
            // A changed source requires review, never silently overwrite its backup.
            guard saved == archive else { throw CocoaError(.fileReadCorruptFile) }
        }
        return archive
    }

    func hasLegacyRecovery(for userID: String) throws -> Bool {
        guard catalog.legacyClaimedBy == nil else { return false }
        if let owner = accountDefaults.string(forKey: Self.accountOwnerKey), owner != userID { return false }
        return try !legacyArchive().isEmpty
    }

    func recoveryData(for userID: String) throws -> Data {
        guard try hasLegacyRecovery(for: userID) else { throw CocoaError(.fileReadNoPermission) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(legacyArchive())
    }

    // Bind only after /auth/me or provider sign-in has verified this stable user ID.
    // Shared-home owner IDs and email addresses are never evidence of ownership.
    func bindAccount(userID: String, claimLegacy: Bool = false, skipLegacy: Bool = false) throws -> AccountAccess {
        if let startupError { throw startupError }
        guard !userID.isEmpty else { throw CocoaError(.fileReadNoPermission) }
        if let modelContext { try modelContext.save() }
        deactivateAccount()
        let pendingLegacy = try hasLegacyRecovery(for: userID)
        let provenOwner = accountDefaults.string(forKey: Self.accountOwnerKey) == userID
        let shouldImport = pendingLegacy && !skipLegacy && (provenOwner || claimLegacy)
        if pendingLegacy && !skipLegacy && !shouldImport && catalog.accounts[userID] == nil { return .claimRequired }

        let container: ModelContainer
        if let slot = catalog.accounts[userID], !shouldImport {
            container = try openAccount(slot: slot)
        } else {
            var archive: InventoryArchive?
            if shouldImport {
                let source = try legacyArchive()
                if !inMemory {
                    try FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)
                    if !FileManager.default.fileExists(atPath: archiveURL.path) {
                        try JSONEncoder().encode(source).write(to: archiveURL, options: [.atomic, .completeFileProtection])
                    }
                }
                try migrationCheckpoint?(.archived)
                archive = source
                if let existing = catalog.accounts[userID] {
                    archive = try source.merging(with: InventoryArchive(context: ModelContext(openAccount(slot: existing))))
                }
            }
            let slot = UUID().uuidString
            let directory = storageRoot.appendingPathComponent(slot, isDirectory: true)
            if !inMemory { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            container = try makeContainer(url: directory.appendingPathComponent("inventory.store"))
            let context = ModelContext(container)
            context.autosaveEnabled = false
            if let archive { try archive.restore(into: context) }
            else { try context.save() }
            try migrationCheckpoint?(.imported)
            var next = catalog
            next.accounts[userID] = slot
            if shouldImport { next.legacyClaimedBy = userID }
            if !inMemory { try JSONEncoder().encode(next).write(to: catalogURL, options: [.atomic, .completeFileProtection]) }
            memoryStores[slot] = inMemory ? container : nil
            catalog = next
            try migrationCheckpoint?(.published)
        }
        modelContainer = container
        modelContext = ModelContext(container)
        modelContext?.autosaveEnabled = false
        boundAccountID = userID
        storeGeneration = UUID()
        return .allowed
    }

    private func openAccount(slot: String) throws -> ModelContainer {
        guard UUID(uuidString: slot) != nil else { throw CocoaError(.fileReadCorruptFile) }
        if let container = memoryStores[slot] { return container }
        let url = storageRoot.appendingPathComponent(slot).appendingPathComponent("inventory.store")
        guard !inMemory, FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile) // Never replace a missing/corrupt account with an empty store.
        }
        return try makeContainer(url: url)
    }

    func currentInventoryData() throws -> Data {
        guard boundAccountID != nil, let modelContext else { throw CocoaError(.fileReadNoPermission) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(InventoryArchive(context: modelContext))
    }

    var context: ModelContext? { modelContext }

    // MARK: - Homes
    
    func fetchHomes() -> [LocalHome] {
        guard let context = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<LocalHome>(
            predicate: #Predicate { !$0.isDeleted },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        )
        
        return (try? context.fetch(descriptor)) ?? []
    }
    
    func fetchHome(id: String) -> LocalHome? {
        guard let context = modelContext else { return nil }
        
        let descriptor = FetchDescriptor<LocalHome>(
            predicate: #Predicate { $0.id == id && !$0.isDeleted }
        )
        
        return try? context.fetch(descriptor).first
    }
    
    func createHome(name: String) -> LocalHome {
        guard let context = modelContext else {
            return LocalHome(name: name)
        }
        
        let home = LocalHome(name: name, needsSync: true)
        home.id = home.id.lowercased()
        home.clientCreateID = home.id
        context.insert(home)
        save()
        return home
    }
    
    func updateHome(_ home: LocalHome) {
        home.updatedAt = Date()
        home.needsSync = true
        save()
    }
    
    func deleteHome(_ home: LocalHome) {
        home.isDeleted = true
        home.updatedAt = Date()
        home.needsSync = true
        save()
    }
    
    // MARK: - Locations

    func fetchLocation(id: String) -> LocalLocation? {
        guard let context = modelContext else { return nil }
        let descriptor = FetchDescriptor<LocalLocation>(
            predicate: #Predicate { $0.id == id && !$0.isDeleted }
        )
        return try? context.fetch(descriptor).first
    }

    func createLocation(homeId: String, name: String, parentId: String?, type: String) -> LocalLocation? {
        guard let context = modelContext,
              let home = fetchHome(id: homeId) else { return nil }
        
        let location = LocalLocation(
            homeId: homeId,
            parentId: parentId,
            name: name,
            type: type,
            needsSync: true
        )
        
        location.id = location.id.lowercased()
        location.clientCreateID = location.id
        context.insert(location)
        location.home = home
        save()
        return location
    }
    
    func updateLocation(_ location: LocalLocation) {
        location.updatedAt = Date()
        location.needsSync = true
        save()
    }
    
    func deleteLocation(_ location: LocalLocation) {
        location.isDeleted = true
        location.updatedAt = Date()
        location.needsSync = true
        save()
    }
    
    // MARK: - Items

    func fetchItem(id: String) -> LocalItem? {
        guard let context = modelContext else { return nil }
        let descriptor = FetchDescriptor<LocalItem>(
            predicate: #Predicate { $0.id == id && !$0.isDeleted }
        )
        return try? context.fetch(descriptor).first
    }

    func fetchDeletedItem(id: String) -> LocalItem? {
        guard let context = modelContext else { return nil }
        let descriptor = FetchDescriptor<LocalItem>(
            predicate: #Predicate { $0.id == id && $0.isDeleted }
        )
        return try? context.fetch(descriptor).first
    }

    func createItem(homeId: String, name: String, locationId: String?) -> LocalItem? {
        guard let context = modelContext,
              let home = fetchHome(id: homeId) else { return nil }
        
        let item = LocalItem(
            homeId: homeId,
            locationId: locationId,
            name: name,
            needsSync: true
        )
        
        item.id = item.id.lowercased()
        item.clientCreateID = item.id
        context.insert(item)
        item.home = home
        save()
        return item
    }
    
    func updateItem(_ item: LocalItem) {
        item.updatedAt = Date()
        item.needsSync = true
        save()
    }
    
    func deleteItem(_ item: LocalItem) {
        item.isDeleted = true
        item.updatedAt = Date()
        item.needsSync = true
        save()
    }

    func restoreItem(_ item: LocalItem) {
        item.isDeleted = false
        item.updatedAt = Date()
        item.needsSync = true
        save()
    }
    
    // MARK: - Fetch pending changes for sync

    func fetchPendingLocations() -> [LocalLocation] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<LocalLocation>(
            predicate: #Predicate { $0.needsSync && !$0.isDeleted }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchPendingItems() -> [LocalItem] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<LocalItem>(
            predicate: #Predicate { $0.needsSync && !$0.isDeleted }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchLocations(homeId: String) -> [LocalLocation] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<LocalLocation>(
            predicate: #Predicate { $0.homeId == homeId && !$0.isDeleted }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchItems(homeId: String) -> [LocalItem] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<LocalItem>(
            predicate: #Predicate { $0.homeId == homeId && !$0.isDeleted }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchItems(locationId: String) -> [LocalItem] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<LocalItem>(
            predicate: #Predicate { $0.locationId == locationId && !$0.isDeleted }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchDeletedHomes() -> [LocalHome] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<LocalHome>(
            predicate: #Predicate { $0.isDeleted }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchDeletedLocations() -> [LocalLocation] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<LocalLocation>(
            predicate: #Predicate { $0.isDeleted }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchDeletedItems() -> [LocalItem] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<LocalItem>(
            predicate: #Predicate { $0.isDeleted }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Orphan cleanup
    // Soft-deletes locations whose parent is missing or soft-deleted,
    // and unsets locationId for items pointing to missing/deleted locations.
    // Repeats until no more orphans are found (children of orphans become orphans).
    func cleanupOrphans() {
        guard let context = modelContext else { return }

        while true {
            let descriptor = FetchDescriptor<LocalLocation>(
                predicate: #Predicate { !$0.isDeleted }
            )
            guard let activeLocs = try? context.fetch(descriptor) else { return }
            let validIds = Set(activeLocs.map { $0.id })

            var foundOrphan = false
            for loc in activeLocs {
                if let parentId = loc.parentId, !validIds.contains(parentId) {
                    loc.isDeleted = true
                    loc.updatedAt = Date()
                    loc.needsSync = true
                    foundOrphan = true
                }
            }
            if !foundOrphan { break }
            save()
        }

        // Fix items whose locationId points to a missing/deleted location
        let locDesc = FetchDescriptor<LocalLocation>(
            predicate: #Predicate { !$0.isDeleted }
        )
        guard let activeLocs = try? context.fetch(locDesc) else { return }
        let validLocIds = Set(activeLocs.map { $0.id })

        let itemDesc = FetchDescriptor<LocalItem>(
            predicate: #Predicate { !$0.isDeleted }
        )
        guard let activeItems = try? context.fetch(itemDesc) else { return }

        var didUpdateItem = false
        for item in activeItems {
            if let locId = item.locationId, !validLocIds.contains(locId) {
                item.locationId = nil
                item.updatedAt = Date()
                item.needsSync = true
                didUpdateItem = true
            }
        }
        if didUpdateItem { save() }
    }

    // MARK: - Hard delete (after server confirms)

    func hardDelete(home: LocalHome) {
        modelContext?.delete(home)
        save()
    }

    func hardDelete(location: LocalLocation) {
        modelContext?.delete(location)
        save()
    }

    func hardDelete(item: LocalItem) {
        modelContext?.delete(item)
        save()
    }

    // MARK: - Remap IDs (local → server)

    func remapHomeId(from oldId: String, to newId: String) {
        guard let home = fetchHome(id: oldId) ?? fetchDeletedHome(id: oldId) else { return }
        home.id = newId
        // Update all child locations and items
        for loc in home.locations {
            loc.homeId = newId
        }
        for item in home.items {
            item.homeId = newId
        }
        save()
    }

    func remapLocationId(from oldId: String, to newId: String) {
        guard let loc = fetchLocation(id: oldId) else { return }
        let oldLocId = loc.id
        loc.id = newId
        // Update children that reference this as parent
        if let context = modelContext {
            let descriptor = FetchDescriptor<LocalLocation>(
                predicate: #Predicate { $0.parentId == oldLocId }
            )
            if let children = try? context.fetch(descriptor) {
                for child in children {
                    child.parentId = newId
                }
            }
            // Update items in this location
            let itemDescriptor = FetchDescriptor<LocalItem>(
                predicate: #Predicate { $0.locationId == oldLocId }
            )
            if let items = try? context.fetch(itemDescriptor) {
                for item in items {
                    item.locationId = newId
                }
            }
        }
        save()
    }

    func remapItemId(from oldId: String, to newId: String) {
        guard let item = fetchItem(id: oldId) else { return }
        item.id = newId
        save()
    }

    private func fetchDeletedHome(id: String) -> LocalHome? {
        guard let context = modelContext else { return nil }
        let descriptor = FetchDescriptor<LocalHome>(
            predicate: #Predicate { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }

    // MARK: - Search
    
    func searchItems(homeId: String, query: String) -> [LocalItem] {
        guard let context = modelContext else { return [] }
        
        let lowercaseQuery = query.lowercased()
        let descriptor = FetchDescriptor<LocalItem>(
            predicate: #Predicate { item in
                item.homeId == homeId &&
                !item.isDeleted &&
                (
                    item.name.localizedStandardContains(lowercaseQuery) ||
                    (item.notes ?? "").localizedStandardContains(lowercaseQuery) ||
                    (item.serialNumber ?? "").localizedStandardContains(lowercaseQuery) ||
                    (item.modelNumber ?? "").localizedStandardContains(lowercaseQuery)
                )
            }
        )
        
        return (try? context.fetch(descriptor)) ?? []
    }
    
    // MARK: - Sync from Server
    
    @discardableResult
    func mergeFromServer(homes: [Home]) -> ServerMergeResult {
        var result = ServerMergeResult()
        for home in homes {
            if let existingHome = fetchHome(id: home.id) {
                guard ServerMergePolicy.shouldApplyServerRecord(
                    needsSync: existingHome.needsSync,
                    isDeleted: existingHome.isDeleted
                ) else {
                    result.deferred += 1
                    continue
                }
                existingHome.update(from: home)
                result.applied += 1
            } else {
                // Don't re-insert if it was locally deleted
                if fetchDeletedHome(id: home.id) != nil {
                    result.deferred += 1
                    continue
                }
                let localHome = LocalHome(
                    id: home.id,
                    name: home.name,
                    ownerId: home.ownerId,
                    role: home.role,
                    icon: home.icon,
                    isFlagged: home.isFlagged,
                    needsSync: false
                )
                modelContext?.insert(localHome)
                result.applied += 1
            }
        }
        save()
        return result
    }
    
    @discardableResult
    func mergeHomeDetail(homeDetail: HomeDetail) -> ServerMergeResult {
        var result = ServerMergeResult()
        guard let home = fetchHome(id: homeDetail.id) else { return result }

        // Update home
        if ServerMergePolicy.shouldApplyServerRecord(needsSync: home.needsSync, isDeleted: home.isDeleted) {
            home.name = homeDetail.name
            home.ownerId = homeDetail.ownerId
            home.role = homeDetail.role
            home.icon = homeDetail.icon
            home.isFlagged = homeDetail.isFlagged
            home.needsSync = false
            result.applied += 1
        } else {
            result.deferred += 1
        }

        // Merge locations
        for location in homeDetail.locations {
            if let existing = home.locations.first(where: { $0.id == location.id }) {
                // Don't update locally-deleted locations
                guard ServerMergePolicy.shouldApplyServerRecord(
                    needsSync: existing.needsSync,
                    isDeleted: existing.isDeleted
                ) else {
                    result.deferred += 1
                    continue
                }
                existing.update(from: location)
                result.applied += 1
            } else {
                // Don't re-insert if locally deleted
                if home.locations.contains(where: { $0.id == location.id && $0.isDeleted }) {
                    result.deferred += 1
                    continue
                }
                let localLocation = LocalLocation(
                    id: location.id,
                    homeId: location.homeId,
                    parentId: location.parentId,
                    name: location.name,
                    type: location.type.rawValue,
                    sortOrder: location.sortOrder,
                    icon: location.icon,
                    isFlagged: location.isFlagged,
                    needsSync: false
                )
                modelContext?.insert(localLocation)
                localLocation.home = home
                result.applied += 1
            }
        }

        // Merge items
        for item in homeDetail.items {
            if let existing = home.items.first(where: { $0.id == item.id }) {
                // Don't update locally-deleted items
                guard ServerMergePolicy.shouldApplyServerRecord(
                    needsSync: existing.needsSync,
                    isDeleted: existing.isDeleted
                ) else {
                    result.deferred += 1
                    continue
                }
                existing.update(from: item)
                result.applied += 1
            } else {
                // Don't re-insert if locally deleted
                if home.items.contains(where: { $0.id == item.id && $0.isDeleted }) {
                    result.deferred += 1
                    continue
                }
                let localItem = LocalItem(
                    id: item.id,
                    homeId: item.homeId,
                    locationId: item.locationId,
                    name: item.name,
                    icon: item.icon,
                    notes: item.notes,
                    quantity: item.quantity,
                    properties: item.properties,
                    photoUrls: item.photoUrls,
                    documents: item.documents,
                    purchaseDate: item.purchaseDate,
                    serialNumber: item.serialNumber,
                    modelNumber: item.modelNumber,
                    warrantyExpiresDate: item.warrantyExpiresDate,
                    estimatedValueCents: item.estimatedValueCents,
                    isFlagged: item.isFlagged,
                    createdBy: item.createdBy,
                    needsSync: false
                )
                modelContext?.insert(localItem)
                localItem.home = home
                result.applied += 1
            }
        }

        save()
        return result
    }
    
    // MARK: - Helpers
    
    func save() {
        guard let context = modelContext else { return }
        
        do {
            try context.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }
    
    func clearAllData() {
        guard let context = modelContext else { return }

        // Delete all homes (cascade will handle locations and items)
        let allHomes = (try? context.fetch(FetchDescriptor<LocalHome>())) ?? []
        allHomes.forEach { context.delete($0) }

        // Delete all sync operations
        let syncOps = (try? context.fetch(FetchDescriptor<SyncOperation>())) ?? []
        syncOps.forEach { context.delete($0) }

        save()
    }
}
