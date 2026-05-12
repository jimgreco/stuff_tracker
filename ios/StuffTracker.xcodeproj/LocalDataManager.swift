import Foundation
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
            sortBy: [SortDescriptor(\.name)]
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
    
    // MARK: - Sync Operations
    
    func addSyncOperation(entityType: String, entityId: String, operation: String, payload: Data? = nil) {
        guard let context = modelContext else { return }
        
        let syncOp = SyncOperation(
            entityType: entityType,
            entityId: entityId,
            operation: operation,
            payload: payload
        )
        
        context.insert(syncOp)
        save()
    }
    
    func fetchPendingSyncOperations() -> [SyncOperation] {
        guard let context = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<SyncOperation>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        
        return (try? context.fetch(descriptor)) ?? []
    }
    
    func removeSyncOperation(_ operation: SyncOperation) {
        guard let context = modelContext else { return }
        context.delete(operation)
        save()
    }
    
    func incrementSyncFailure(_ operation: SyncOperation, error: String) {
        operation.failureCount += 1
        operation.lastError = error
        save()
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
                existing.update(from: location)
            } else {
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
                existing.update(from: item)
            } else {
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
    
    private func save() {
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
        let homes = fetchHomes()
        homes.forEach { context.delete($0) }
        
        // Delete all sync operations
        let syncOps = fetchPendingSyncOperations()
        syncOps.forEach { context.delete($0) }
        
        save()
    }
}
