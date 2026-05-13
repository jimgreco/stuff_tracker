import Foundation

struct PendingSyncLocation: Equatable {
    let id: String
    let parentId: String?
    let name: String
    let needsSync: Bool
    let isDeleted: Bool
}

enum SyncUploadPlanningError: LocalizedError, Equatable {
    case missingParent(locationName: String)
    case cyclicLocation(locationName: String)

    var errorDescription: String? {
        switch self {
        case .missingParent(let locationName):
            return "Location '\(locationName)' references a parent that no longer exists."
        case .cyclicLocation(let locationName):
            return "Location '\(locationName)' has a circular parent relationship."
        }
    }
}

enum SyncUploadPlanner {
    static func orderedPendingLocationIds(_ locations: [PendingSyncLocation]) throws -> [String] {
        let activeLocations = locations.filter { !$0.isDeleted }
        let locationsById = Dictionary(uniqueKeysWithValues: activeLocations.map { ($0.id, $0) })
        let pendingIds = Set(activeLocations.filter(\.needsSync).map(\.id))

        var orderedIds: [String] = []
        var visiting = Set<String>()
        var visited = Set<String>()

        func visit(_ locationId: String) throws {
            if visited.contains(locationId) { return }
            guard let location = locationsById[locationId] else { return }

            if visiting.contains(locationId) {
                throw SyncUploadPlanningError.cyclicLocation(locationName: location.name)
            }

            visiting.insert(locationId)

            if let parentId = location.parentId {
                guard let parent = locationsById[parentId] else {
                    throw SyncUploadPlanningError.missingParent(locationName: location.name)
                }
                try visit(parent.id)
            }

            visiting.remove(locationId)
            visited.insert(locationId)

            if pendingIds.contains(locationId) {
                orderedIds.append(locationId)
            }
        }

        for location in activeLocations where location.needsSync {
            try visit(location.id)
        }

        return orderedIds
    }
}

enum ServerMergePolicy {
    static func shouldApplyServerRecord(needsSync: Bool, isDeleted: Bool) -> Bool {
        !needsSync && !isDeleted
    }
}
