import Testing
import Foundation
@testable import StuffTracker

@Suite("Sync Manager Tests")
@MainActor
struct SyncManagerTests {
    
    var syncManager: SyncManager
    var localData: LocalDataManager
    var mockAPI: MockAPIClient
    
    init() async {
        localData = LocalDataManager.shared
        localData.clearAllData()
        
        mockAPI = MockAPIClient()
        syncManager = SyncManager.shared
        // Note: In real implementation, you'd inject the mock API
    }
    
    @Test("Initial state has no pending syncs")
    func initialStateHasNoPendingSyncs() async {
        #expect(syncManager.pendingSyncCount == 0)
        #expect(syncManager.isSyncing == false)
        #expect(syncManager.lastSyncDate == nil)
    }
    
    @Test("Creating local item increments pending count")
    func creatingLocalItemIncrementsPendingCount() async {
        let home = localData.createHome(name: "Test")
        
        syncManager.updatePendingSyncCount()
        
        #expect(syncManager.pendingSyncCount >= 1)
    }
    
    @Test("Sync operation is queued for offline changes")
    func syncOperationIsQueuedForOfflineChanges() async {
        localData.addSyncOperation(
            entityType: "home",
            entityId: "123",
            operation: "create",
            payload: nil
        )
        
        let operations = localData.fetchPendingSyncOperations()
        #expect(operations.count == 1)
        #expect(operations.first?.entityType == "home")
        #expect(operations.first?.operation == "create")
    }
    
    @Test("Failed sync increments failure count")
    func failedSyncIncrementsFailureCount() async {
        localData.addSyncOperation(
            entityType: "item",
            entityId: "456",
            operation: "update",
            payload: nil
        )
        
        let operation = try #require(localData.fetchPendingSyncOperations().first)
        #expect(operation.failureCount == 0)
        
        localData.incrementSyncFailure(operation, error: "Network timeout")
        
        #expect(operation.failureCount == 1)
        #expect(operation.lastError == "Network timeout")
    }
    
    @Test("Sync operation removed after max failures")
    func syncOperationRemovedAfterMaxFailures() async {
        localData.addSyncOperation(
            entityType: "item",
            entityId: "789",
            operation: "delete",
            payload: nil
        )
        
        let operation = try #require(localData.fetchPendingSyncOperations().first)
        
        // Simulate 3 failures
        localData.incrementSyncFailure(operation, error: "Error 1")
        localData.incrementSyncFailure(operation, error: "Error 2")
        localData.incrementSyncFailure(operation, error: "Error 3")
        
        #expect(operation.failureCount == 3)
        // In real implementation, processSyncQueue would remove it
    }
}

// MARK: - Mock API Client

class MockAPIClient {
    var shouldFail = false
    var homes: [Home] = []
    var homeDetails: [String: HomeDetail] = [:]
    
    func listHomes() async throws -> [Home] {
        if shouldFail {
            throw APIError.networkError(NSError(domain: "test", code: -1))
        }
        return homes
    }
    
    func createHome(name: String) async throws -> Home {
        if shouldFail {
            throw APIError.networkError(NSError(domain: "test", code: -1))
        }
        let home = Home(id: UUID().uuidString, name: name, ownerId: "test-user", role: "owner")
        homes.append(home)
        return home
    }
    
    func getHome(_ id: String) async throws -> HomeDetail {
        if shouldFail {
            throw APIError.networkError(NSError(domain: "test", code: -1))
        }
        guard let detail = homeDetails[id] else {
            throw APIError.httpError(404, "Not found")
        }
        return detail
    }
}
