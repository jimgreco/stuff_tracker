import Foundation
import SwiftData

@MainActor
final class LocalDataManager {
    static let shared = LocalDataManager()
    
    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?
    
    private init() {
        setupContainer()
    }
    
    private func setupContainer() {
        let schema = Schema([
            LocalHome.self,
            LocalLocation.self,
            LocalItem.self,
            SyncOperation.self
        ])
        
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            modelContext = ModelContext(modelContainer!)
        } catch {
            print("Failed to create ModelContainer: \(error)")
        }
    }
    
    var context: ModelContext? {
        modelContext
    }
    
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
                item.name.localizedStandardContains(lowercaseQuery)
            }
        )
        
        return (try? context.fetch(descriptor)) ?? []
    }
    
    // MARK: - Sync from Server
    
    func mergeFromServer(homes: [Home]) {
        for home in homes {
            if let existingHome = fetchHome(id: home.id) {
                existingHome.update(from: home)
            } else {
                // Don't re-insert if it was locally deleted
                if fetchDeletedHome(id: home.id) != nil { continue }
                let localHome = LocalHome(
                    id: home.id,
                    name: home.name,
                    ownerId: home.ownerId,
                    role: home.role,
                    needsSync: false
                )
                modelContext?.insert(localHome)
            }
        }
        save()
    }
    
    func mergeHomeDetail(homeDetail: HomeDetail) {
        guard let home = fetchHome(id: homeDetail.id) else { return }

        // Update home
        home.name = homeDetail.name
        home.ownerId = homeDetail.ownerId
        home.role = homeDetail.role
        home.needsSync = false

        // Merge locations
        for location in homeDetail.locations {
            if let existing = home.locations.first(where: { $0.id == location.id }) {
                // Don't update locally-deleted locations
                if existing.isDeleted { continue }
                existing.update(from: location)
            } else {
                // Don't re-insert if locally deleted
                if home.locations.contains(where: { $0.id == location.id && $0.isDeleted }) { continue }
                let localLocation = LocalLocation(
                    id: location.id,
                    homeId: location.homeId,
                    parentId: location.parentId,
                    name: location.name,
                    type: location.type.rawValue,
                    sortOrder: location.sortOrder,
                    needsSync: false
                )
                modelContext?.insert(localLocation)
                localLocation.home = home
            }
        }

        // Merge items
        for item in homeDetail.items {
            if let existing = home.items.first(where: { $0.id == item.id }) {
                // Don't update locally-deleted items
                if existing.isDeleted { continue }
                existing.update(from: item)
            } else {
                // Don't re-insert if locally deleted
                if home.items.contains(where: { $0.id == item.id && $0.isDeleted }) { continue }
                let localItem = LocalItem(
                    id: item.id,
                    homeId: item.homeId,
                    locationId: item.locationId,
                    name: item.name,
                    notes: item.notes,
                    quantity: item.quantity,
                    tags: item.tags,
                    photoUrl: item.photoUrl,
                    purchaseDate: item.purchaseDate,
                    createdBy: item.createdBy,
                    needsSync: false
                )
                modelContext?.insert(localItem)
                localItem.home = home
            }
        }

        save()
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
