import SwiftUI

@MainActor
final class HomeStore: ObservableObject {
    @Published var homes: [Home] = []
    @Published var homeDetails: [HomeDetail] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = APIClient.shared
    private let local = LocalDataManager.shared

    var isAuthenticated: Bool { api.hasToken }

    private func detailIndex(for homeId: String) -> Int? {
        homeDetails.firstIndex(where: { $0.id == homeId })
    }

    // MARK: - Load (always local-first)

    func loadHomes() async {
        isLoading = true
        defer { isLoading = false }

        // Clean up any orphaned locations/items from previous bugs
        local.cleanupOrphans()

        // Always load from local first
        reloadFromLocal()

        // If authenticated, sync from server in background
        if isAuthenticated {
            await syncFromServer()
        }
    }

    func reloadFromLocal() {
        let localHomes = local.fetchHomes()
        homes = localHomes.map { $0.toHome() }
        homeDetails = localHomes.map { $0.toHomeDetail() }
    }

    private func syncFromServer() async {
        do {
            // Push deletes first so server doesn't send back deleted items
            await SyncManager.shared.syncPendingChanges()

            let serverHomes = try await api.listHomes()
            var mergeResult = local.mergeFromServer(homes: serverHomes)

            for home in serverHomes {
                do {
                    let detail = try await api.getHome(home.id)
                    mergeResult.add(local.mergeHomeDetail(homeDetail: detail))
                } catch {
                    // Individual home detail fetch failed, skip
                }
            }

            SyncManager.shared.deferredServerChangeCount = mergeResult.deferred

            // Reload UI from local (now updated with server data)
            reloadFromLocal()
        } catch {
            // Server unavailable, that's fine — we have local data
        }
    }

    // MARK: - Homes

    func createHome(name: String) {
        let maxSort = local.fetchHomes().map(\.sortOrder).max() ?? -1
        let localHome = local.createHome(name: name)
        localHome.sortOrder = maxSort + 1
        local.save()
        homes.append(localHome.toHome())
        homeDetails.append(localHome.toHomeDetail())
        enqueueSyncIfNeeded()
    }

    func renameHome(_ id: String, name: String) {
        if let idx = homes.firstIndex(where: { $0.id == id }) {
            homes[idx].name = name
        }
        if let idx = detailIndex(for: id) {
            homeDetails[idx].name = name
        }
        if let localHome = local.fetchHome(id: id) {
            localHome.name = name
            local.updateHome(localHome)
        }
        enqueueSyncIfNeeded()
    }

    func updateHomeIcon(_ id: String, icon: String) {
        let customIcon = icon.isEmpty ? nil : icon
        if let idx = homes.firstIndex(where: { $0.id == id }) {
            homes[idx].icon = customIcon
        }
        if let idx = detailIndex(for: id) {
            homeDetails[idx].icon = customIcon
        }
        if let localHome = local.fetchHome(id: id) {
            localHome.icon = customIcon
            local.updateHome(localHome)
        }
        enqueueSyncIfNeeded()
    }

    func setHomeFlagged(_ id: String, isFlagged: Bool) {
        if let idx = homes.firstIndex(where: { $0.id == id }) {
            homes[idx].isFlagged = isFlagged
        }
        if let idx = detailIndex(for: id) {
            homeDetails[idx].isFlagged = isFlagged
        }
        if let localHome = local.fetchHome(id: id) {
            localHome.isFlagged = isFlagged
            local.updateHome(localHome)
        }
        enqueueSyncIfNeeded()
    }

    func reorderHome(_ homeId: String, toIndex destination: Int) {
        var ordered = homeDetails.sorted { a, b in
            let aSort = local.fetchHome(id: a.id)?.sortOrder ?? 0
            let bSort = local.fetchHome(id: b.id)?.sortOrder ?? 0
            return aSort < bSort
        }
        guard let fromIndex = ordered.firstIndex(where: { $0.id == homeId }) else { return }
        let moved = ordered.remove(at: fromIndex)
        let clampedIndex = min(max(destination, 0), ordered.count)
        ordered.insert(moved, at: clampedIndex)

        for (i, home) in ordered.enumerated() {
            if let localHome = local.fetchHome(id: home.id) {
                localHome.sortOrder = i
                local.save()
            }
        }
        homeDetails = ordered
    }

    func deleteHome(_ id: String) {
        if let localHome = local.fetchHome(id: id) {
            local.deleteHome(localHome)
        }
        homes.removeAll { $0.id == id }
        homeDetails.removeAll { $0.id == id }
        enqueueSyncIfNeeded()
    }

    // MARK: - Locations

    func createLocation(homeId: String, name: String, parentId: String?, type: String) {
        if let localLoc = local.createLocation(homeId: homeId, name: name, parentId: parentId, type: type) {
            if let idx = detailIndex(for: homeId) {
                homeDetails[idx].locations.append(localLoc.toLocation())
            }
        }
        enqueueSyncIfNeeded()
    }

    func renameLocation(homeId: String, locationId: String, name: String) {
        if let hIdx = detailIndex(for: homeId),
           let lIdx = homeDetails[hIdx].locations.firstIndex(where: { $0.id == locationId }) {
            homeDetails[hIdx].locations[lIdx].name = name
        }
        if let localLoc = local.fetchLocation(id: locationId) {
            localLoc.name = name
            local.updateLocation(localLoc)
        }
        enqueueSyncIfNeeded()
    }

    func updateLocationIcon(homeId: String, locationId: String, icon: String) {
        let customIcon = icon.isEmpty ? nil : icon
        if let hIdx = detailIndex(for: homeId),
           let lIdx = homeDetails[hIdx].locations.firstIndex(where: { $0.id == locationId }) {
            homeDetails[hIdx].locations[lIdx].icon = customIcon
        }
        if let localLoc = local.fetchLocation(id: locationId) {
            localLoc.icon = customIcon
            local.updateLocation(localLoc)
        }
        enqueueSyncIfNeeded()
    }

    func setLocationFlagged(homeId: String, locationId: String, isFlagged: Bool) {
        if let hIdx = detailIndex(for: homeId),
           let lIdx = homeDetails[hIdx].locations.firstIndex(where: { $0.id == locationId }) {
            homeDetails[hIdx].locations[lIdx].isFlagged = isFlagged
        }
        if let localLoc = local.fetchLocation(id: locationId) {
            localLoc.isFlagged = isFlagged
            local.updateLocation(localLoc)
        }
        enqueueSyncIfNeeded()
    }

    func moveLocation(homeId: String, locationId: String, toParent newParentId: String?) {
        if let hIdx = detailIndex(for: homeId),
           let lIdx = homeDetails[hIdx].locations.firstIndex(where: { $0.id == locationId }) {
            homeDetails[hIdx].locations[lIdx].parentId = newParentId
        }
        if let localLoc = local.fetchLocation(id: locationId) {
            localLoc.parentId = newParentId
            local.updateLocation(localLoc)
        }
        enqueueSyncIfNeeded()
    }

    func reorderLocation(homeId: String, locationId: String, toIndex destination: Int) {
        guard let hIdx = detailIndex(for: homeId) else { return }

        // Find the location being moved
        guard let loc = homeDetails[hIdx].locations.first(where: { $0.id == locationId }) else { return }

        // Get siblings (same parentId), sorted by current sortOrder
        var siblings = homeDetails[hIdx].locations
            .filter { $0.parentId == loc.parentId && $0.id != locationId }
            .sorted { $0.sortOrder < $1.sortOrder }

        // Insert at destination
        let clampedIndex = min(max(destination, 0), siblings.count)
        siblings.insert(loc, at: clampedIndex)

        // Reassign sortOrder for all siblings
        for (i, sibling) in siblings.enumerated() {
            if let lIdx = homeDetails[hIdx].locations.firstIndex(where: { $0.id == sibling.id }) {
                homeDetails[hIdx].locations[lIdx].sortOrder = i
            }
            if let localLoc = local.fetchLocation(id: sibling.id) {
                localLoc.sortOrder = i
                local.updateLocation(localLoc)
            }
        }
        enqueueSyncIfNeeded()
    }

    func moveLocationToParent(homeId: String, locationId: String, newParentId: String?, atIndex index: Int) {
        guard let hIdx = detailIndex(for: homeId),
              let lIdx = homeDetails[hIdx].locations.firstIndex(where: { $0.id == locationId }) else { return }

        // Update parent
        homeDetails[hIdx].locations[lIdx].parentId = newParentId
        if let localLoc = local.fetchLocation(id: locationId) {
            localLoc.parentId = newParentId
            local.updateLocation(localLoc)
        }

        // Reorder within new parent's children
        reorderLocation(homeId: homeId, locationId: locationId, toIndex: index)
    }

    func moveLocationAcrossHomes(fromHomeId: String, locationId: String, toHomeId: String, newParentId: String?, atIndex index: Int) {
        // Get the source location info
        guard let srcIdx = detailIndex(for: fromHomeId),
              let loc = homeDetails[srcIdx].locations.first(where: { $0.id == locationId }) else { return }

        // Delete from source home
        deleteLocation(homeId: fromHomeId, locationId: locationId)

        // Create in destination home
        if let localLoc = local.createLocation(homeId: toHomeId, name: loc.name, parentId: newParentId, type: loc.type.rawValue) {
            localLoc.sortOrder = index
            localLoc.icon = loc.icon
            localLoc.isFlagged = loc.isFlagged
            local.updateLocation(localLoc)
            if let dstIdx = detailIndex(for: toHomeId) {
                homeDetails[dstIdx].locations.append(localLoc.toLocation())
                // Reorder to correct position
                reorderLocation(homeId: toHomeId, locationId: localLoc.id, toIndex: index)
            }
        }
        enqueueSyncIfNeeded()
    }

    func deleteLocation(homeId: String, locationId: String) {
        // Collect all descendant location IDs (children, grandchildren, etc.)
        var allIds = [locationId]
        if let idx = detailIndex(for: homeId) {
            var queue = [locationId]
            while !queue.isEmpty {
                let parentId = queue.removeFirst()
                let childIds = homeDetails[idx].locations
                    .filter { $0.parentId == parentId }
                    .map { $0.id }
                allIds.append(contentsOf: childIds)
                queue.append(contentsOf: childIds)
            }
        }

        let deletedSet = Set(allIds)

        // Soft-delete all locations in the subtree
        for id in allIds {
            if let localLoc = local.fetchLocation(id: id) {
                local.deleteLocation(localLoc)
            }
        }

        // Clear locationId on items in any deleted location (matches server ON DELETE SET NULL)
        for id in allIds {
            for localItem in local.fetchItems(locationId: id) {
                localItem.locationId = nil
                local.updateItem(localItem)
            }
        }

        // Update in-memory model
        if let idx = detailIndex(for: homeId) {
            homeDetails[idx].locations.removeAll { deletedSet.contains($0.id) }
            homeDetails[idx].items = homeDetails[idx].items.map { item in
                var i = item
                if let locId = i.locationId, deletedSet.contains(locId) {
                    i.locationId = nil
                }
                return i
            }
        }
        enqueueSyncIfNeeded()
    }

    // MARK: - Items

    func createItem(homeId: String, name: String, locationId: String?) {
        if let localItem = local.createItem(homeId: homeId, name: name, locationId: locationId) {
            if let idx = detailIndex(for: homeId) {
                homeDetails[idx].items.append(localItem.toItem())
            }
        }
        enqueueSyncIfNeeded()
    }

    func updateItem(homeId: String, itemId: String, body: APIClient.ItemBody) {
        // Update local
        if let localItem = local.fetchItem(id: itemId) {
            localItem.name = body.name
            localItem.locationId = body.locationId
            localItem.icon = body.icon
            localItem.notes = body.notes
            localItem.quantity = body.quantity ?? localItem.quantity
            localItem.properties = body.properties ?? localItem.properties
            localItem.photoUrls = body.photoUrls ?? localItem.photoUrls
            localItem.documents = body.documents ?? localItem.documents
            localItem.purchaseDate = body.purchaseDate
            localItem.serialNumber = body.serialNumber
            localItem.modelNumber = body.modelNumber
            localItem.warrantyExpiresDate = body.warrantyExpiresDate
            localItem.estimatedValueCents = body.estimatedValueCents
            localItem.isFlagged = body.isFlagged ?? localItem.isFlagged
            localItem.sortOrder = body.sortOrder ?? localItem.sortOrder
            local.updateItem(localItem)

            // Update in-memory
            if let hIdx = detailIndex(for: homeId),
               let iIdx = homeDetails[hIdx].items.firstIndex(where: { $0.id == itemId }) {
                homeDetails[hIdx].items[iIdx] = localItem.toItem()
            }
        }
        enqueueSyncIfNeeded()
    }

    func moveItem(homeId: String, itemId: String, toLocation locationId: String?) {
        moveItems(homeId: homeId, itemIds: [itemId], toLocation: locationId)
    }

    func moveItems(homeId: String, itemIds: [String], toLocation locationId: String?, atIndex destination: Int? = nil) {
        guard let hIdx = detailIndex(for: homeId) else { return }

        var seen = Set<String>()
        let uniqueIds = itemIds.filter { seen.insert($0).inserted }
        guard !uniqueIds.isEmpty else { return }

        let movingSet = Set(uniqueIds)
        let movingItems = uniqueIds.compactMap { itemId in
            homeDetails[hIdx].items.first(where: { $0.id == itemId })
        }
        guard !movingItems.isEmpty else { return }

        var siblings = homeDetails[hIdx].items
            .filter { $0.locationId == locationId && !movingSet.contains($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }

        let insertionIndex = destination.map { min(max($0, 0), siblings.count) } ?? siblings.count
        siblings.insert(contentsOf: movingItems, at: insertionIndex)

        for (sortOrder, item) in siblings.enumerated() {
            if let iIdx = homeDetails[hIdx].items.firstIndex(where: { $0.id == item.id }) {
                homeDetails[hIdx].items[iIdx].locationId = locationId
                homeDetails[hIdx].items[iIdx].sortOrder = sortOrder
            }
            if let localItem = local.fetchItem(id: item.id) {
                localItem.locationId = locationId
                localItem.sortOrder = sortOrder
                local.updateItem(localItem)
            }
        }

        enqueueSyncIfNeeded()
    }

    func deleteItems(homeId: String, itemIds: [String]) {
        var seen = Set<String>()
        let uniqueIds = itemIds.filter { seen.insert($0).inserted }
        guard !uniqueIds.isEmpty else { return }

        for itemId in uniqueIds {
            if let localItem = local.fetchItem(id: itemId) {
                local.deleteItem(localItem)
            }
        }
        if let idx = detailIndex(for: homeId) {
            let deletedSet = Set(uniqueIds)
            homeDetails[idx].items.removeAll { deletedSet.contains($0.id) }
        }
        enqueueSyncIfNeeded()
    }

    func setItemsFlagged(homeId: String, itemIds: [String], isFlagged: Bool) {
        guard let hIdx = detailIndex(for: homeId) else { return }

        var seen = Set<String>()
        let uniqueIds = itemIds.filter { seen.insert($0).inserted }
        guard !uniqueIds.isEmpty else { return }

        for itemId in uniqueIds {
            if let iIdx = homeDetails[hIdx].items.firstIndex(where: { $0.id == itemId }) {
                homeDetails[hIdx].items[iIdx].isFlagged = isFlagged
            }
            if let localItem = local.fetchItem(id: itemId) {
                localItem.isFlagged = isFlagged
                local.updateItem(localItem)
            }
        }
        enqueueSyncIfNeeded()
    }

    func reorderItem(homeId: String, itemId: String, toIndex destination: Int) {
        guard let hIdx = detailIndex(for: homeId),
              let item = homeDetails[hIdx].items.first(where: { $0.id == itemId }) else { return }

        var siblings = homeDetails[hIdx].items
            .filter { $0.locationId == item.locationId && $0.id != itemId }
            .sorted { $0.sortOrder < $1.sortOrder }

        let clampedIndex = min(max(destination, 0), siblings.count)
        siblings.insert(item, at: clampedIndex)

        for (i, sibling) in siblings.enumerated() {
            if let iIdx = homeDetails[hIdx].items.firstIndex(where: { $0.id == sibling.id }) {
                homeDetails[hIdx].items[iIdx].sortOrder = i
            }
            if let localItem = local.fetchItem(id: sibling.id) {
                localItem.sortOrder = i
                local.updateItem(localItem)
            }
        }
        enqueueSyncIfNeeded()
    }

    func sortItemsByName(homeId: String, locationId: String?) {
        guard let hIdx = detailIndex(for: homeId) else { return }

        let sorted = homeDetails[hIdx].items
            .filter { $0.locationId == locationId }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        for (i, item) in sorted.enumerated() {
            if let iIdx = homeDetails[hIdx].items.firstIndex(where: { $0.id == item.id }) {
                homeDetails[hIdx].items[iIdx].sortOrder = i
            }
            if let localItem = local.fetchItem(id: item.id) {
                localItem.sortOrder = i
                local.updateItem(localItem)
            }
        }
        enqueueSyncIfNeeded()
    }

    func sortChildLocationsByName(homeId: String, parentId: String?, type: Location.LocationType? = nil) {
        guard let hIdx = detailIndex(for: homeId) else { return }

        let siblings = homeDetails[hIdx].locations
            .filter { $0.parentId == parentId }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.sortOrder < $1.sortOrder
            }
        let targetSiblings = siblings
            .filter { location in type.map { location.type == $0 } ?? true }
        let targetIds = Set(targetSiblings.map(\.id))
        let sortedTargets = targetSiblings
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        var targetIndex = 0
        let reordered = siblings.map { location in
            guard targetIds.contains(location.id) else { return location }
            defer { targetIndex += 1 }
            return sortedTargets[targetIndex]
        }

        for (i, loc) in reordered.enumerated() {
            if let lIdx = homeDetails[hIdx].locations.firstIndex(where: { $0.id == loc.id }) {
                homeDetails[hIdx].locations[lIdx].sortOrder = i
            }
            if let localLoc = local.fetchLocation(id: loc.id) {
                localLoc.sortOrder = i
                local.updateLocation(localLoc)
            }
        }
        enqueueSyncIfNeeded()
    }

    func deleteItem(homeId: String, itemId: String) {
        deleteItems(homeId: homeId, itemIds: [itemId])
    }

    // MARK: - Trash bin

    var deletedItems: [(item: Item, homeName: String)] {
        let localDeleted = local.fetchDeletedItems()
        return localDeleted.map { localItem in
            let homeName = local.fetchHome(id: localItem.homeId)?.name
                ?? homeDetails.first(where: { $0.id == localItem.homeId })?.name
                ?? "Unknown"
            return (localItem.toItem(), homeName)
        }
    }

    func restoreItem(itemId: String) {
        guard let localItem = local.fetchDeletedItem(id: itemId) else { return }
        local.restoreItem(localItem)
        // Re-add to in-memory homeDetails
        let item = localItem.toItem()
        if let idx = detailIndex(for: item.homeId) {
            homeDetails[idx].items.append(item)
        }
        enqueueSyncIfNeeded()
    }

    func searchItems(query: String) -> [Item] {
        var results: [Item] = []
        for home in homeDetails {
            results += local.searchItems(homeId: home.id, query: query).map { $0.toItem() }
        }
        return results
    }

    // MARK: - Background sync trigger

    private func enqueueSyncIfNeeded() {
        guard isAuthenticated else { return }
        Task {
            await SyncManager.shared.syncPendingChanges()
            // Refresh in-memory model after sync to pick up any ID remaps
            reloadFromLocal()
        }
    }
}
