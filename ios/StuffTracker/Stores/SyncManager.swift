import SwiftUI

@MainActor
final class SyncManager: ObservableObject {
    static let shared = SyncManager()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published var pendingSyncCount: Int = 0

    private let api = APIClient.shared
    private let local = LocalDataManager.shared
    private var isSyncInFlight = false

    private init() {
        updatePendingSyncCount()
    }

    // MARK: - Full sync (pull server → local, then push local → server)

    func performFullSync() async {
        guard api.hasToken, !isSyncInFlight else { return }
        isSyncInFlight = true
        isSyncing = true
        syncError = nil

        // 1. Pull from server
        await pullFromServer()

        // 2. Push pending local changes
        await pushPendingChanges()

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
            let serverHomes = try await api.listHomes()
            local.mergeFromServer(homes: serverHomes)

            for home in serverHomes {
                do {
                    let detail = try await api.getHome(home.id)
                    local.mergeHomeDetail(homeDetail: detail)
                } catch {
                    // Skip individual failures
                }
            }
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

        // Push locations that need sync
        let pendingLocations = local.fetchPendingLocations()
        for loc in pendingLocations {
            await pushLocation(loc)
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
                    let _: Home = try await api.updateHome(home.id, name: home.name)
                } catch {
                    // Doesn't exist, create
                    let created = try await api.createHome(name: home.name)
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
            // Try update first
            do {
                let _: Location = try await api.updateLocation(
                    homeId: loc.homeId,
                    locationId: loc.id,
                    name: loc.name,
                    parentId: loc.parentId,
                    sortOrder: loc.sortOrder
                )
            } catch APIError.httpError(404, _) {
                // Doesn't exist, create
                let created = try await api.createLocation(
                    homeId: loc.homeId,
                    name: loc.name,
                    parentId: loc.parentId,
                    type: loc.type,
                    sortOrder: loc.sortOrder
                )
                if created.id != loc.id {
                    local.remapLocationId(from: loc.id, to: created.id)
                }
            }
            loc.needsSync = false
            local.save()
        } catch {
            syncError = "Failed to sync location '\(loc.name)': \(error.localizedDescription)"
        }
    }

    private func pushItem(_ item: LocalItem) async {
        guard !item.isDeleted else { return }
        let body = APIClient.ItemBody(
            name: item.name,
            locationId: item.locationId,
            icon: item.icon,
            notes: item.notes,
            quantity: item.quantity,
            tags: item.tags,
            photoUrl: item.photoUrl,
            purchaseDate: item.purchaseDate
        )
        do {
            do {
                let _: Item = try await api.updateItem(homeId: item.homeId, itemId: item.id, body: body)
            } catch APIError.httpError(404, _) {
                let created = try await api.createItem(homeId: item.homeId, body: body)
                if created.id != item.id {
                    local.remapItemId(from: item.id, to: created.id)
                }
            }
            item.needsSync = false
            local.save()
        } catch {
            syncError = "Failed to sync item '\(item.name)': \(error.localizedDescription)"
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
                let created = try await api.createHome(name: home.name)
                let oldId = home.id

                if created.id != oldId {
                    local.remapHomeId(from: oldId, to: created.id)
                }

                // Push locations
                let locs = local.fetchLocations(homeId: created.id)
                for loc in locs {
                    let createdLoc = try await api.createLocation(
                        homeId: created.id,
                        name: loc.name,
                        parentId: loc.parentId,
                        type: loc.type,
                        sortOrder: loc.sortOrder
                    )
                    if createdLoc.id != loc.id {
                        local.remapLocationId(from: loc.id, to: createdLoc.id)
                    }
                    loc.needsSync = false
                }

                // Push items
                let items = local.fetchItems(homeId: created.id)
                for item in items {
                    let body = APIClient.ItemBody(
                        name: item.name,
                        locationId: item.locationId,
                        icon: item.icon,
                        notes: item.notes,
                        quantity: item.quantity,
                        tags: item.tags,
                        photoUrl: item.photoUrl,
                        purchaseDate: item.purchaseDate
                    )
                    let createdItem = try await api.createItem(homeId: created.id, body: body)
                    if createdItem.id != item.id {
                        local.remapItemId(from: item.id, to: createdItem.id)
                    }
                    item.needsSync = false
                }

                home.needsSync = false
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

    func updatePendingSyncCount() {
        let homes = local.fetchHomes().filter { $0.needsSync }
        let locs = local.fetchPendingLocations()
        let items = local.fetchPendingItems()
        let deleted = local.fetchDeletedHomes().count + local.fetchDeletedLocations().count + local.fetchDeletedItems().count
        pendingSyncCount = homes.count + locs.count + items.count + deleted
    }
}
