import SwiftUI
import Combine

private enum LocalSyncScope {
    @TaskLocal static var storeGeneration: UUID?
}

private enum SyncUploadError: LocalizedError {
    case missingParent(locationName: String)
    case missingItemLocation(itemName: String)
    case cyclicLocation(locationName: String)
    case unresolvedLegacy(name: String)
    case itemUploadFailed(itemName: String, message: String, context: String)

    var errorDescription: String? {
        switch self {
        case .unresolvedLegacy(let name):
            return "Older record '\(name)' has an unknown server outcome. It stays saved for review; export the account inventory from Account before resolving it."
        case .missingParent(let locationName):
            return "Location '\(locationName)' references a parent that no longer exists."
        case .missingItemLocation(let itemName):
            return "Item '\(itemName)' references a location that no longer exists."
        case .cyclicLocation(let locationName):
            return "Location '\(locationName)' has a circular parent relationship."
        case .itemUploadFailed(let itemName, let message, let context):
            return "Failed to sync item '\(itemName)': \(message) \(context)"
        }
    }
}

@MainActor
final class SyncManager: ObservableObject {
    static let shared = SyncManager()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published var pendingSyncCount: Int = 0
    @Published var deferredServerChangeCount: Int = 0

    private let api: APIClient
    private let local: LocalDataManager
    private var activeRun: UUID?
    private var accountObserver: AnyCancellable?

    init(api: APIClient = .shared, local: LocalDataManager? = nil) {
        self.api = api
        self.local = local ?? .shared
        updatePendingSyncCount()
        accountObserver = self.local.$storeGeneration.sink { [weak self] _ in
            self?.activeRun = nil
            self?.isSyncing = false
            self?.syncError = nil
            self?.lastSyncDate = nil
            self?.pendingSyncCount = 0
            self?.deferredServerChangeCount = 0
        }
    }

    private func requireSyncSession() throws {
        try api.requireCurrentSession()
        if let expected = LocalSyncScope.storeGeneration, expected != local.storeGeneration { throw CancellationError() }
        guard api.hasToken, let userID = api.localAccountID, userID == local.boundAccountID else {
            throw CancellationError()
        }
    }

    private func runSync(_ operation: () async throws -> Void) async {
        guard activeRun == nil, (try? requireSyncSession()) != nil else { return }
        let run = UUID()
        activeRun = run
        isSyncing = true
        syncError = nil
        defer {
            if activeRun == run {
                isSyncing = false
                activeRun = nil
                updatePendingSyncCount()
            }
        }
        await LocalSyncScope.$storeGeneration.withValue(local.storeGeneration) {
            await api.withSessionScope {
                do {
                    try await operation()
                    try requireSyncSession()
                    if syncError == nil { lastSyncDate = Date() }
                } catch is CancellationError {
                    // The original account keeps pending work; the new one may sync now.
                } catch {
                    if (try? requireSyncSession()) != nil { syncError = "Sync failed: \(error.localizedDescription)" }
                }
            }
        }
    }

    // Check connectivity/authorization before a sign-in-triggered upload. Failure
    // is never interpreted as an empty account or permission to recreate homes.
    func performFullSync() async {
        await runSync {
            _ = try await api.listHomes()
            try requireSyncSession()
            try await pushPendingChanges()
            try requireSyncSession()
            try await pullFromServer()
        }
    }

    func syncPendingChanges() async {
        await runSync { try await pushPendingChanges() }
    }

    // MARK: - Pull server data into local

    private func pullFromServer() async throws {
        try requireSyncSession()
        var mergeResult = ServerMergeResult()
        let serverHomes = try await api.listHomes()
        try requireSyncSession()
        mergeResult.add(local.mergeFromServer(homes: serverHomes))
        for home in serverHomes {
            do {
                let detail = try await api.getHome(home.id)
                try requireSyncSession()
                mergeResult.add(local.mergeHomeDetail(homeDetail: detail))
            } catch {
                try requireSyncSession()
                syncError = "Some home details could not be refreshed. Saved changes are preserved."
            }
        }
        deferredServerChangeCount = mergeResult.deferred
    }

    // MARK: - Push local changes to server

    private func pushPendingChanges() async throws {
        try requireSyncSession()
        // Push homes that need sync
        let pendingHomes = local.fetchHomes().filter { $0.needsSync }
        for home in pendingHomes {
            try requireSyncSession()
            await pushHome(home)
        }

        // Push locations after their parents have server IDs
        let pendingLocationHomeIds = Set(local.fetchPendingLocations().map(\.homeId))
        for homeId in pendingLocationHomeIds {
            do {
                try await pushPendingLocations(homeId: homeId)
            } catch {
                try requireSyncSession()
                syncError = "Failed to sync locations: \(error.localizedDescription)"
            }
        }

        // Push items that need sync
        let pendingItems = local.fetchPendingItems()
        for item in pendingItems {
            try requireSyncSession()
            await pushItem(item)
        }

        // Push deleted entities
        await pushDeleted()
    }

    private func pushHome(_ home: LocalHome) async {
        do {
            if home.isTombstone {
                try await api.deleteHome(home.id, clientID: home.clientCreateID, mutationMetadata: mutationMetadata("home-delete", id: home.id, at: home.updatedAt))
                try requireSyncSession()
                local.hardDelete(home: home)
            } else {
                // Try to create or update
                do {
                    let _ = try await api.getHome(home.id)
                    try requireSyncSession()
                    // Exists on server, update
                    let _: Home = try await api.updateHome(home.id, name: home.name, icon: home.icon, isFlagged: home.isFlagged, mutationMetadata: mutationMetadata("home-update", id: home.id, at: home.updatedAt))
                    try requireSyncSession()
                } catch APIError.httpError(let code, _) where code == 404 || (code == 403 && home.clientCreateID != nil) {
                    guard home.clientCreateID != nil else { throw SyncUploadError.unresolvedLegacy(name: home.name) }
                    // Only an explicitly recorded durable create may use POST.
                    let created = try await api.createHome(name: home.name, icon: home.icon, isFlagged: home.isFlagged, clientID: home.clientCreateID, mutationMetadata: mutationMetadata("home-create", id: home.id, at: home.updatedAt))
                    try requireSyncSession()
                    // Remap the local ID to server ID if different
                    if created.id != home.id {
                        local.remapHomeId(from: home.id, to: created.id)
                    }
                }
                home.needsSync = false
                local.save()
            }
        } catch {
            guard (try? requireSyncSession()) != nil else { return }
            syncError = "Failed to sync home '\(home.name)': \(error.localizedDescription)"
        }
    }

    private func pushLocation(_ loc: LocalLocation) async {
        guard !loc.isTombstone else { return }
        do {
            try await upsertLocation(loc)
            try requireSyncSession()
        } catch {
            guard (try? requireSyncSession()) != nil else { return }
            syncError = "Failed to sync location '\(loc.name)': \(error.localizedDescription)"
        }
    }

    private func pushItem(_ item: LocalItem) async {
        guard !item.isTombstone else { return }
        do {
            try await upsertItem(item)
            try requireSyncSession()
        } catch {
            guard (try? requireSyncSession()) != nil else { return }
            syncError = "Failed to sync item '\(item.name)': \(error.localizedDescription) \(itemSyncContext(item))"
        }
    }

    private func deleteConfirmed(_ request: () async throws -> Void) async throws {
        try requireSyncSession()
        try await request()
        try requireSyncSession()
    }

    private func pushDeleted() async {
        for home in local.fetchDeletedHomes() {
            do {
                if home.clientCreateID == nil {
                    do { _ = try await api.getHome(home.id) }
                    catch { try requireSyncSession(); throw SyncUploadError.unresolvedLegacy(name: home.name) }
                    try requireSyncSession()
                }
                try await deleteConfirmed {
                    try await api.deleteHome(home.id, clientID: home.clientCreateID, mutationMetadata: mutationMetadata("home-delete", id: home.id, at: home.updatedAt))
                }
                try requireSyncSession()
                local.hardDelete(home: home)
            } catch { if (try? requireSyncSession()) != nil { syncError = "A deletion stays saved: \(error.localizedDescription)" } }
        }
        for loc in local.fetchDeletedLocations() {
            do {
                if loc.clientCreateID == nil {
                    let detail = try await api.getHome(loc.homeId)
                    try requireSyncSession()
                    guard detail.locations.contains(where: { $0.id.lowercased() == loc.id.lowercased() }) else {
                        throw SyncUploadError.unresolvedLegacy(name: loc.name)
                    }
                }
                try await deleteConfirmed {
                    try await api.deleteLocation(homeId: loc.homeId, locationId: loc.id, clientID: loc.clientCreateID, mutationMetadata: mutationMetadata("location-delete", id: loc.id, at: loc.updatedAt))
                }
                try requireSyncSession()
                local.hardDelete(location: loc)
            } catch { if (try? requireSyncSession()) != nil { syncError = "A deletion stays saved: \(error.localizedDescription)" } }
        }
        for item in local.fetchDeletedItems() {
            do {
                if item.clientCreateID == nil {
                    let detail = try await api.getHome(item.homeId)
                    try requireSyncSession()
                    guard detail.items.contains(where: { $0.id.lowercased() == item.id.lowercased() }) else {
                        throw SyncUploadError.unresolvedLegacy(name: item.name)
                    }
                }
                try await deleteConfirmed {
                    try await api.deleteItem(homeId: item.homeId, itemId: item.id, clientID: item.clientCreateID, mutationMetadata: mutationMetadata("item-delete", id: item.id, at: item.updatedAt))
                }
                try requireSyncSession()
                local.hardDelete(item: item)
            } catch { if (try? requireSyncSession()) != nil { syncError = "A deletion stays saved: \(error.localizedDescription)" } }
        }
    }

    private func uploadBoundInventory() async throws {
        try requireSyncSession()
        _ = try await api.listHomes()
        try requireSyncSession()
        for home in local.fetchHomes() {
            let uploadedHome = try await ensureHomeUploaded(home)
            try requireSyncSession()
            try await pushPendingLocations(homeId: uploadedHome.id)
            try await pushPendingItems(homeId: uploadedHome.id)
        }
    }

    func uploadLocalToServer() async {
        await runSync { try await uploadBoundInventory() }
    }

    func replaceLocalWithServer() async {
        await runSync {
            // Fetch a complete replacement before touching the retained store.
            let homes = try await api.listHomes()
            var details: [HomeDetail] = []
            for home in homes {
                details.append(try await api.getHome(home.id))
            }
            try requireSyncSession()
            local.clearAllData()
            _ = local.mergeFromServer(homes: homes)
            for detail in details { _ = local.mergeHomeDetail(homeDetail: detail) }
        }
    }

    func mergeLocalAndServer() async {
        await runSync {
            try await uploadBoundInventory()
            try requireSyncSession()
            try await pullFromServer()
        }
    }

    // MARK: - Helpers

    private func ensureHomeUploaded(_ home: LocalHome) async throws -> Home {
        try requireSyncSession()
        do {
            let detail = try await api.getHome(home.id)
            try requireSyncSession()
            if home.needsSync {
                let updated: Home = try await api.updateHome(home.id, name: home.name, icon: home.icon, isFlagged: home.isFlagged, mutationMetadata: mutationMetadata("home-update", id: home.id, at: home.updatedAt))
                try requireSyncSession()
                home.needsSync = false
                local.save()
                return updated
            }
            return Home(
                id: detail.id,
                name: detail.name,
                ownerId: detail.ownerId,
                role: detail.role,
                icon: detail.icon,
                isFlagged: detail.isFlagged
            )
        } catch APIError.httpError(let code, _) where code == 404 || (code == 403 && home.clientCreateID != nil) {
            guard home.clientCreateID != nil else { throw SyncUploadError.unresolvedLegacy(name: home.name) }
            let created = try await api.createHome(name: home.name, icon: home.icon, isFlagged: home.isFlagged, clientID: home.clientCreateID, mutationMetadata: mutationMetadata("home-create", id: home.id, at: home.updatedAt))
            try requireSyncSession()
            let oldId = home.id
            if created.id != oldId {
                local.remapHomeId(from: oldId, to: created.id)
            }
            home.ownerId = created.ownerId
            home.role = created.role
            home.needsSync = false
            local.save()
            return created
        }
    }

    private func pushPendingLocations(homeId: String) async throws {
        try requireSyncSession()
        let locations = local.fetchLocations(homeId: homeId)
        let orderedLocationIds = try SyncUploadPlanner.orderedPendingLocationIds(
            locations.map {
                PendingSyncLocation(
                    id: $0.id,
                    parentId: $0.parentId,
                    name: $0.name,
                    needsSync: $0.needsSync,
                    isDeleted: $0.isTombstone
                )
            }
        )

        for locationId in orderedLocationIds {
            guard let location = local.fetchLocation(id: locationId), !location.isTombstone else {
                continue
            }
            try await upsertLocation(location)
            try requireSyncSession()
        }
    }

    private func upsertLocation(_ loc: LocalLocation) async throws {
        try requireSyncSession()
        if let parentId = loc.parentId {
            guard let parent = local.fetchLocation(id: parentId), !parent.isTombstone else {
                throw SyncUploadError.missingParent(locationName: loc.name)
            }
            try await ensureLocationUploaded(parent, visiting: [loc.id])
            try requireSyncSession()
        }

        do {
            let updated = try await api.updateLocation(
                homeId: loc.homeId,
                locationId: loc.id,
                newHomeId: loc.homeId,
                name: loc.name,
                parentId: loc.parentId,
                sortOrder: loc.sortOrder,
                icon: loc.icon,
                isFlagged: loc.isFlagged,
                mutationMetadata: mutationMetadata("location-update", id: loc.id, at: loc.updatedAt)
            )
            try requireSyncSession()
            loc.update(from: updated)
            local.save()
        } catch APIError.httpError(let code, _) where code == 404 {
            guard loc.clientCreateID != nil else { throw SyncUploadError.unresolvedLegacy(name: loc.name) }
            let oldId = loc.id
            let created = try await api.createLocation(
                homeId: loc.homeId,
                name: loc.name,
                parentId: loc.parentId,
                type: loc.type,
                sortOrder: loc.sortOrder,
                icon: loc.icon,
                isFlagged: loc.isFlagged,
                clientID: loc.clientCreateID,
                mutationMetadata: mutationMetadata("location-create", id: loc.id, at: loc.updatedAt)
            )
            try requireSyncSession()
            if created.id != oldId {
                local.remapLocationId(from: oldId, to: created.id)
            }
            let uploaded = local.fetchLocation(id: created.id) ?? loc
            uploaded.update(from: created)
            local.save()
        }
    }

    private func ensureLocationUploaded(_ loc: LocalLocation, visiting: Set<String> = []) async throws {
        try requireSyncSession()
        if visiting.contains(loc.id) {
            throw SyncUploadError.cyclicLocation(locationName: loc.name)
        }

        var nextVisiting = visiting
        nextVisiting.insert(loc.id)

        if let parentId = loc.parentId {
            guard let parent = local.fetchLocation(id: parentId), !parent.isTombstone else {
                throw SyncUploadError.missingParent(locationName: loc.name)
            }
            try await ensureLocationUploaded(parent, visiting: nextVisiting)
            try requireSyncSession()
        }

        try await upsertLocation(loc)
        try requireSyncSession()
    }

    private func pushPendingItems(homeId: String) async throws {
        try requireSyncSession()
        let items = local.fetchItems(homeId: homeId).filter { $0.needsSync && !$0.isTombstone }

        for item in items {
            do {
                try await upsertItem(item)
                try requireSyncSession()
            } catch {
                throw SyncUploadError.itemUploadFailed(
                    itemName: item.name,
                    message: error.localizedDescription,
                    context: itemSyncContext(item)
                )
            }
        }
    }

    private func upsertItem(_ item: LocalItem) async throws {
        try requireSyncSession()
        try await ensureItemHomeUploaded(item)
        try requireSyncSession()
        try await ensureItemLocationUploaded(item)
        try requireSyncSession()
        let latest = refreshedItem(item)

        do {
            try await saveItemToServer(latest)
            try requireSyncSession()
        } catch APIError.httpError(400, let message) where message == "Location not found" {
            try await ensureItemLocationUploaded(latest)
            try requireSyncSession()
            let repaired = refreshedItem(latest)
            do {
                try await saveItemToServer(repaired)
                try requireSyncSession()
            } catch APIError.httpError(400, let retryMessage) where retryMessage == "Location not found" {
                repaired.locationId = nil
                repaired.needsSync = true
                local.save()
                try await saveItemToServer(repaired)
                try requireSyncSession()
            }
        }
    }

    private func saveItemToServer(_ item: LocalItem) async throws {
        try requireSyncSession()
        do {
            let updated = try await api.updateItem(homeId: item.homeId, itemId: item.id, body: itemBody(item), mutationMetadata: mutationMetadata("item-update", id: item.id, at: item.updatedAt))
            try requireSyncSession()
            item.update(from: updated)
            local.save()
        } catch APIError.httpError(404, _) {
            guard item.clientCreateID != nil else { throw SyncUploadError.unresolvedLegacy(name: item.name) }
            let oldId = item.id
            let created = try await api.createItem(homeId: item.homeId, body: itemBody(item), clientID: item.clientCreateID, mutationMetadata: mutationMetadata("item-create", id: item.id, at: item.updatedAt))
            try requireSyncSession()
            if created.id != oldId {
                local.remapItemId(from: oldId, to: created.id)
            }
            let uploaded = local.fetchItem(id: created.id) ?? item
            uploaded.update(from: created)
            local.save()
        }
    }

    private func ensureItemHomeUploaded(_ item: LocalItem) async throws {
        try requireSyncSession()
        guard let home = local.fetchHome(id: item.homeId) else { return }
        let uploadedHome = try await ensureHomeUploaded(home)
        try requireSyncSession()
        if item.homeId != uploadedHome.id {
            item.homeId = uploadedHome.id
            local.save()
        }
    }

    private func mutationMetadata(_ operation: String, id: String, at date: Date) -> APIClient.MutationMetadata {
        APIClient.MutationMetadata(
            id: "ios:\(operation):\(id):\(date.timeIntervalSince1970)",
            occurredAt: date
        )
    }

    private func ensureItemLocationUploaded(_ item: LocalItem) async throws {
        try requireSyncSession()
        let currentItem = refreshedItem(item)
        guard let locationId = currentItem.locationId else { return }
        guard let location = local.fetchLocation(id: locationId), !location.isTombstone else {
            throw SyncUploadError.missingItemLocation(itemName: currentItem.name)
        }

        try alignLocationChain(location, toHomeId: currentItem.homeId)
        try await ensureLocationUploaded(location)
        try requireSyncSession()

        let repairedItem = refreshedItem(currentItem)
        guard let syncedLocationId = repairedItem.locationId else { return }
        if try await serverHasLocation(homeId: repairedItem.homeId, locationId: syncedLocationId) {
            return
        }

        if let repairedLocation = local.fetchLocation(id: syncedLocationId), !repairedLocation.isTombstone {
            repairedLocation.needsSync = true
            try await ensureLocationUploaded(repairedLocation)
            try requireSyncSession()
        }

        let finalItem = refreshedItem(repairedItem)
        if !(try await serverHasLocation(homeId: finalItem.homeId, locationId: finalItem.locationId ?? syncedLocationId)) {
            finalItem.locationId = nil
            finalItem.needsSync = true
            local.save()
        }
    }

    private func itemBody(_ item: LocalItem) -> APIClient.ItemBody {
        APIClient.ItemBody(
            name: item.name,
            homeId: item.homeId,
            locationId: item.locationId,
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
            sortOrder: item.sortOrder
        )
    }

    private func alignLocationChain(
        _ location: LocalLocation,
        toHomeId homeId: String,
        visiting: Set<String> = []
    ) throws {
        if visiting.contains(location.id) {
            throw SyncUploadError.cyclicLocation(locationName: location.name)
        }

        var nextVisiting = visiting
        nextVisiting.insert(location.id)

        if let parentId = location.parentId {
            guard let parent = local.fetchLocation(id: parentId), !parent.isTombstone else {
                throw SyncUploadError.missingParent(locationName: location.name)
            }
            try alignLocationChain(parent, toHomeId: homeId, visiting: nextVisiting)
        }

        if location.homeId != homeId {
            location.homeId = homeId
            location.home = local.fetchHome(id: homeId)
            location.needsSync = true
            local.save()
        }
    }

    private func serverHasLocation(homeId: String, locationId: String) async throws -> Bool {
        try requireSyncSession()
        let detail = try await api.getHome(homeId)
        try requireSyncSession()
        return detail.locations.contains { $0.id == locationId }
    }

    private func refreshedItem(_ item: LocalItem) -> LocalItem {
        local.fetchItem(id: item.id) ?? item
    }

    private func itemSyncContext(_ item: LocalItem) -> String {
        let latest = refreshedItem(item)
        let locHome = latest.locationId.flatMap { local.fetchLocation(id: $0)?.homeId } ?? "none"
        return "[homeId=\(latest.homeId), locationId=\(latest.locationId ?? "nil"), locationHomeId=\(locHome)]"
    }

    func updatePendingSyncCount() {
        let homes = local.fetchHomes().filter { $0.needsSync }
        let locs = local.fetchPendingLocations()
        let items = local.fetchPendingItems()
        let deleted = local.fetchDeletedHomes().count + local.fetchDeletedLocations().count + local.fetchDeletedItems().count
        pendingSyncCount = homes.count + locs.count + items.count + deleted
    }
}
