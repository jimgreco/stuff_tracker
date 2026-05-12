import Foundation
import Foundation
import SwiftUI

@MainActor
final class SyncManager: ObservableObject {
    static let shared = SyncManager()
    
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published var pendingSyncCount: Int = 0
    
    private let localData = LocalDataManager.shared
    private let api = APIClient.shared
    
    private init() {
        updatePendingSyncCount()
    }
    
    // MARK: - Sync Status
    
    func updatePendingSyncCount() {
        let operations = localData.fetchPendingSyncOperations()
        pendingSyncCount = operations.count
        
        // Also count items that need sync
        let homes = localData.fetchHomes()
        let needsSyncCount = homes.reduce(0) { count, home in
            let homeCount = home.needsSync ? 1 : 0
            let locationCount = home.locations.filter { $0.needsSync }.count
            let itemCount = home.items.filter { $0.needsSync }.count
            return count + homeCount + locationCount + itemCount
        }
        
        pendingSyncCount += needsSyncCount
    }
    
    // MARK: - Pull from Server
    
    func pullFromServer() async throws {
        guard api.hasToken else { return }
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            // Fetch all homes from server
            let homes: [Home] = try await api.listHomes()
            
            // Merge into local database
            localData.mergeFromServer(homes: homes)
            
            // Fetch details for each home
            for home in homes {
                let homeDetail: HomeDetail = try await api.getHome(home.id)
                localData.mergeHomeDetail(homeDetail: homeDetail)
            }
            
            lastSyncDate = Date()
            syncError = nil
            updatePendingSyncCount()
        } catch {
            syncError = "Failed to pull data: \(error.localizedDescription)"
            throw error
        }
    }
    
    // MARK: - Push to Server
    
    func pushToServer() async throws {
        guard api.hasToken else { return }
        
        isSyncing = true
        defer { 
            isSyncing = false
            updatePendingSyncCount()
        }
        
        var hasErrors = false
        
        // Push homes
        let homes = localData.fetchHomes().filter { $0.needsSync }
        for home in homes {
            do {
                if home.isDeleted {
                    try await api.deleteHome(home.id)
                } else if home.ownerId == nil {
                    // Create new home on server
                    let created = try await api.createHome(name: home.name)
                    home.update(from: created)
                } else {
                    // Update existing home
                    let updated = try await api.updateHome(id: home.id, name: home.name)
                    home.update(from: updated)
                }
                home.needsSync = false
            } catch {
                hasErrors = true
                print("Failed to sync home \(home.id): \(error)")
            }
        }
        
        // Push locations
        let allHomes = localData.fetchHomes()
        for home in allHomes {
            let locations = home.locations.filter { $0.needsSync }
            for location in locations {
                do {
                    if location.isDeleted {
                        try await api.deleteLocation(homeId: home.id, locationId: location.id)
                    } else {
                        let created = try await api.createLocation(
                            homeId: home.id,
                            name: location.name,
                            parentId: location.parentId,
                            type: location.type
                        )
                        location.update(from: created)
                    }
                    location.needsSync = false
                } catch {
                    hasErrors = true
                    print("Failed to sync location \(location.id): \(error)")
                }
            }
        }
        
        // Push items
        for home in allHomes {
            let items = home.items.filter { $0.needsSync }
            for item in items {
                do {
                    if item.isDeleted {
                        try await api.deleteItem(homeId: home.id, itemId: item.id)
                    } else {
                        let body = APIClient.ItemBody(
                            name: item.name,
                            locationId: item.locationId,
                            notes: item.notes,
                            quantity: item.quantity,
                            tags: item.tags,
                            photoUrl: item.photoUrl,
                            purchaseDate: item.purchaseDate
                        )
                        
                        if item.createdBy == nil {
                            // Create new item
                            let created = try await api.createItem(homeId: home.id, body: body)
                            item.update(from: created)
                        } else {
                            // Update existing
                            let updated = try await api.updateItem(homeId: home.id, itemId: item.id, body: body)
                            item.update(from: updated)
                        }
                    }
                    item.needsSync = false
                } catch {
                    hasErrors = true
                    print("Failed to sync item \(item.id): \(error)")
                }
            }
        }
        
        if !hasErrors {
            lastSyncDate = Date()
            syncError = nil
        } else {
            syncError = "Some items failed to sync"
        }
    }
    
    // MARK: - Full Sync
    
    func performFullSync() async {
        guard api.hasToken else { return }
        
        do {
            // First push local changes
            try await pushToServer()
            
            // Then pull latest from server
            try await pullFromServer()
            
        } catch {
            syncError = "Sync failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Process Sync Queue
    
    func processSyncQueue() async {
        guard api.hasToken else { return }
        
        let operations = localData.fetchPendingSyncOperations()
        
        for operation in operations {
            do {
                try await processSyncOperation(operation)
                localData.removeSyncOperation(operation)
            } catch {
                localData.incrementSyncFailure(operation, error: error.localizedDescription)
                
                // Remove after too many failures
                if operation.failureCount >= 3 {
                    localData.removeSyncOperation(operation)
                }
            }
        }
        
        updatePendingSyncCount()
    }
    
    private func processSyncOperation(_ operation: SyncOperation) async throws {
        switch (operation.entityType, operation.operation) {
        case ("home", "create"):
            if let payload = operation.payload,
               let dict = try? JSONDecoder().decode([String: String].self, from: payload),
               let name = dict["name"] {
                _ = try await api.createHome(name: name)
            }
            
        case ("home", "delete"):
            try await api.deleteHome(operation.entityId)
            
        case ("location", "create"):
            if let payload = operation.payload,
               let dict = try? JSONDecoder().decode([String: String].self, from: payload) {
                _ = try await api.createLocation(
                    homeId: dict["homeId"] ?? "",
                    name: dict["name"] ?? "",
                    parentId: dict["parentId"],
                    type: dict["type"] ?? "room"
                )
            }
            
        case ("location", "delete"):
            if let payload = operation.payload,
               let dict = try? JSONDecoder().decode([String: String].self, from: payload),
               let homeId = dict["homeId"] {
                try await api.deleteLocation(homeId: homeId, locationId: operation.entityId)
            }
            
        case ("item", "create"), ("item", "update"):
            if let payload = operation.payload,
               let dict = try? JSONDecoder().decode([String: AnyCodable].self, from: payload),
               let homeId = dict["homeId"]?.value as? String {
                
                let body = APIClient.ItemBody(
                    name: dict["name"]?.value as? String ?? "",
                    locationId: dict["locationId"]?.value as? String,
                    notes: dict["notes"]?.value as? String,
                    quantity: dict["quantity"]?.value as? Int ?? 1,
                    tags: dict["tags"]?.value as? [String] ?? [],
                    photoUrl: dict["photoUrl"]?.value as? String,
                    purchaseDate: dict["purchaseDate"]?.value as? String
                )
                
                if operation.operation == "create" {
                    _ = try await api.createItem(homeId: homeId, body: body)
                } else {
                    _ = try await api.updateItem(homeId: homeId, itemId: operation.entityId, body: body)
                }
            }
            
        case ("item", "delete"):
            if let payload = operation.payload,
               let dict = try? JSONDecoder().decode([String: String].self, from: payload),
               let homeId = dict["homeId"] {
                try await api.deleteItem(homeId: homeId, itemId: operation.entityId)
            }
            
        default:
            break
        }
    }
}

// MARK: - Helper for any codable value

struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let array = try? container.decode([String].self) {
            value = array
        } else {
            value = ""
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let array = value as? [String] {
            try container.encode(array)
        }
    }
}
