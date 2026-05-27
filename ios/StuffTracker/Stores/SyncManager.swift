import SwiftUI

private enum SyncUploadError: LocalizedError {
    case missingParent(locationName: String)
    case missingItemLocation(itemName: String)
    case cyclicLocation(locationName: String)
    case itemUploadFailed(itemName: String, message: String, context: String)

    var errorDescription: String? {
        switch self {
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

    private let api = APIClient.shared
    private let local = LocalDataManager.shared
    private var isSyncInFlight = false

    private init() {
        updatePendingSyncCount()
    }

    // MARK: - Full sync (push local → server, then pull server → local)

    func performFullSync() async {
        guard api.hasToken, !isSyncInFlight else { return }
        isSyncInFlight = true
        isSyncing = true
        syncError = nil

        // Push pending local changes before pulling so server data cannot clobber unsynced local edits.
        await pushPendingChanges()

        // Pull server data after local changes have either synced or remained marked pending.
        await pullFromServer()

        lastSyncDate = Date()
        isSyncing = false
        isSyncInFlight = false
        updatePendingSyncCount()
    }

    // MARK: - Push only (called after each local mutation)

    func syncPendingChanges() async {
        guard api.hasToken, !isSyncInFlight else { return }
        isSyncInFlight = true
        isSyncing = true

        await pushPendingChanges()

        isSyncing = false
        isSyncInFlight = false
        updatePendingSyncCount()
    }

    // MARK: - Pull server data into local

    private func pullFromServer() async {
        do {
            var mergeResult = ServerMergeResult()
            let serverHomes = try await api.listHomes()
            mergeResult.add(local.mergeFromServer(homes: serverHomes))

            for home in serverHomes {
                do {
                    let detail = try await api.getHome(home.id)
                    mergeResult.add(local.mergeHomeDetail(homeDetail: detail))
                } catch {
                    // Skip individual failures
                }
            }
            deferredServerChangeCount = mergeResult.deferred
        } catch {
            syncError = "Pull failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Push local changes to server

    private func pushPendingChanges() async {
        // Push homes that need sync
        let pendingHomes = local.fetchHomes().filter { $0.needsSync }
        for home in pendingHomes {
            await pushHome(home)
        }

        // Push locations after their parents have server IDs
        let pendingLocationHomeIds = Set(local.fetchPendingLocations().map(\.homeId))
        for homeId in pendingLocationHomeIds {
            do {
                try await pushPendingLocations(homeId: homeId)
            } catch {
                syncError = "Failed to sync locations: \(error.localizedDescription)"
            }
        }

        // Push items that need sync
        let pendingItems = local.fetchPendingItems()
        for item in pendingItems {
            await pushItem(item)
        }

        // Push deleted entities
        await pushDeleted()
    }

    private func pushHome(_ home: LocalHome) async {
        do {
            if home.isDeleted {
                try await api.deleteHome(home.id)
                local.hardDelete(home: home)
            } else {
                // Try to create or update
                do {
                    let _ = try await api.getHome(home.id)
                    // Exists on server, update
                    let _: Home = try await api.updateHome(home.id, name: home.name, icon: home.icon)
                } catch {
                    // Doesn't exist, create
                    let created = try await api.createHome(name: home.name, icon: home.icon)
                    // Remap the local ID to server ID if different
                    if created.id != home.id {
                        local.remapHomeId(from: home.id, to: created.id)
                    }
                }
                home.needsSync = false
                local.save()
            }
        } catch {
            syncError = "Failed to sync home '\(home.name)': \(error.localizedDescription)"
        }
    }

    private func pushLocation(_ loc: LocalLocation) async {
        guard !loc.isDeleted else { return }
        do {
            try await upsertLocation(loc)
        } catch {
            syncError = "Failed to sync location '\(loc.name)': \(error.localizedDescription)"
        }
    }

    private func pushItem(_ item: LocalItem) async {
        guard !item.isDeleted else { return }
        do {
            try await upsertItem(item)
        } catch {
            syncError = "Failed to sync item '\(item.name)': \(error.localizedDescription) \(itemSyncContext(item))"
        }
    }

    private func pushDeleted() async {
        // Delete homes
        for home in local.fetchDeletedHomes() {
            do {
                try await api.deleteHome(home.id)
            } catch {
                // Might already be deleted on server
            }
            local.hardDelete(home: home)
        }

        // Delete locations
        for loc in local.fetchDeletedLocations() {
            do {
                try await api.deleteLocation(homeId: loc.homeId, locationId: loc.id)
            } catch {}
            local.hardDelete(location: loc)
        }

        // Delete items
        for item in local.fetchDeletedItems() {
            do {
                try await api.deleteItem(homeId: item.homeId, itemId: item.id)
            } catch {}
            local.hardDelete(item: item)
        }
    }

    // MARK: - First sign-in: upload all local data to server

    func uploadLocalToServer() async {
        isSyncing = true
        syncError = nil

        let homes = local.fetchHomes()
        for home in homes {
            do {
                let uploadedHome = try await ensureHomeUploaded(home)
                try await pushPendingLocations(homeId: uploadedHome.id)
                try await pushPendingItems(homeId: uploadedHome.id)
            } catch {
                syncError = "Upload failed: \(error.localizedDescription)"
            }
        }

        local.save()
        lastSyncDate = Date()
        isSyncing = false
        updatePendingSyncCount()
    }

    // MARK: - First sign-in: replace local with server data

    func replaceLocalWithServer() async {
        isSyncing = true
        syncError = nil

        local.clearAllData()

        await pullFromServer()

        lastSyncDate = Date()
        isSyncing = false
        updatePendingSyncCount()
    }

    // MARK: - First sign-in: merge local + server

    func mergeLocalAndServer() async {
        isSyncing = true
        syncError = nil

        // First upload local data
        await uploadLocalToServer()

        // Then pull server data (which now includes our uploads + anything else)
        await pullFromServer()

        lastSyncDate = Date()
        isSyncing = false
        updatePendingSyncCount()
    }

    // MARK: - Helpers

    private func ensureHomeUploaded(_ home: LocalHome) async throws -> Home {
        do {
            let detail = try await api.getHome(home.id)
            if home.needsSync {
                let updated: Home = try await api.updateHome(home.id, name: home.name, icon: home.icon)
                home.needsSync = false
                local.save()
                return updated
            }
            return Home(
                id: detail.id,
                name: detail.name,
                ownerId: detail.ownerId,
                role: detail.role,
                icon: detail.icon
            )
        } catch APIError.httpError(let code, _) where code == 403 || code == 404 {
            let created = try await api.createHome(name: home.name, icon: home.icon)
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
        let locations = local.fetchLocations(homeId: homeId)
        let orderedLocationIds = try SyncUploadPlanner.orderedPendingLocationIds(
            locations.map {
                PendingSyncLocation(
                    id: $0.id,
                    parentId: $0.parentId,
                    name: $0.name,
                    needsSync: $0.needsSync,
                    isDeleted: $0.isDeleted
                )
            }
        )

        for locationId in orderedLocationIds {
            guard let location = local.fetchLocation(id: locationId), !location.isDeleted else {
                continue
            }
            try await upsertLocation(location)
        }
    }

    private func upsertLocation(_ loc: LocalLocation) async throws {
        if let parentId = loc.parentId {
            guard let parent = local.fetchLocation(id: parentId), !parent.isDeleted else {
                throw SyncUploadError.missingParent(locationName: loc.name)
            }
            try await ensureLocationUploaded(parent, visiting: [loc.id])
        }

        do {
            let updated = try await api.updateLocation(
                homeId: loc.homeId,
                locationId: loc.id,
                name: loc.name,
                parentId: loc.parentId,
                sortOrder: loc.sortOrder,
                icon: loc.icon
            )
            loc.update(from: updated)
            local.save()
        } catch APIError.httpError(let code, _) where code == 403 || code == 404 {
            let oldId = loc.id
            let created = try await api.createLocation(
                homeId: loc.homeId,
                name: loc.name,
                parentId: loc.parentId,
                type: loc.type,
                sortOrder: loc.sortOrder,
                icon: loc.icon
            )
            if created.id != oldId {
                local.remapLocationId(from: oldId, to: created.id)
            }
            let uploaded = local.fetchLocation(id: created.id) ?? loc
            uploaded.update(from: created)
            local.save()
        }
    }

    private func ensureLocationUploaded(_ loc: LocalLocation, visiting: Set<String> = []) async throws {
        if visiting.contains(loc.id) {
            throw SyncUploadError.cyclicLocation(locationName: loc.name)
        }

        var nextVisiting = visiting
        nextVisiting.insert(loc.id)

        if let parentId = loc.parentId {
            guard let parent = local.fetchLocation(id: parentId), !parent.isDeleted else {
                throw SyncUploadError.missingParent(locationName: loc.name)
            }
            try await ensureLocationUploaded(parent, visiting: nextVisiting)
        }

        try await upsertLocation(loc)
    }

    private func pushPendingItems(homeId: String) async throws {
        let items = local.fetchItems(homeId: homeId).filter { $0.needsSync && !$0.isDeleted }

        for item in items {
            do {
                try await upsertItem(item)
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
        try await ensureItemHomeUploaded(item)
        try await ensureItemLocationUploaded(item)
        let latest = refreshedItem(item)

        do {
            try await saveItemToServer(latest)
        } catch APIError.httpError(400, let message) where message == "Location not found" {
            try await ensureItemLocationUploaded(latest)
            let repaired = refreshedItem(latest)
            do {
                try await saveItemToServer(repaired)
            } catch APIError.httpError(400, let retryMessage) where retryMessage == "Location not found" {
                repaired.locationId = nil
                repaired.needsSync = true
                local.save()
                try await saveItemToServer(repaired)
            }
        }
    }

    private func saveItemToServer(_ item: LocalItem) async throws {
        do {
            let updated = try await api.updateItem(homeId: item.homeId, itemId: item.id, body: itemBody(item))
            item.update(from: updated)
            local.save()
        } catch APIError.httpError(404, _) {
            let oldId = item.id
            let created = try await api.createItem(homeId: item.homeId, body: itemBody(item))
            if created.id != oldId {
                local.remapItemId(from: oldId, to: created.id)
            }
            let uploaded = local.fetchItem(id: created.id) ?? item
            uploaded.update(from: created)
            local.save()
        }
    }

    private func ensureItemHomeUploaded(_ item: LocalItem) async throws {
        guard let home = local.fetchHome(id: item.homeId) else { return }
        let uploadedHome = try await ensureHomeUploaded(home)
        if item.homeId != uploadedHome.id {
            item.homeId = uploadedHome.id
            local.save()
        }
    }

    private func ensureItemLocationUploaded(_ item: LocalItem) async throws {
        let currentItem = refreshedItem(item)
        guard let locationId = currentItem.locationId else { return }
        guard let location = local.fetchLocation(id: locationId), !location.isDeleted else {
            throw SyncUploadError.missingItemLocation(itemName: currentItem.name)
        }

        try alignLocationChain(location, toHomeId: currentItem.homeId)
        try await ensureLocationUploaded(location)

        let repairedItem = refreshedItem(currentItem)
        guard let syncedLocationId = repairedItem.locationId else { return }
        if try await serverHasLocation(homeId: repairedItem.homeId, locationId: syncedLocationId) {
            return
        }

        if let repairedLocation = local.fetchLocation(id: syncedLocationId), !repairedLocation.isDeleted {
            repairedLocation.needsSync = true
            try await ensureLocationUploaded(repairedLocation)
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
            isFlagged: item.isFlagged
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
            guard let parent = local.fetchLocation(id: parentId), !parent.isDeleted else {
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
        let detail = try await api.getHome(homeId)
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
