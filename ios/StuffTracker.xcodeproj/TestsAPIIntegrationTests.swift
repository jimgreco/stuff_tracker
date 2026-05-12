import Testing
import Foundation
@testable import StuffTracker

// MARK: - API Integration Tests
// These tests require a running backend server
// Set INTEGRATION_TESTS environment variable to run them

@Suite("API Integration Tests", .disabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != "1"))
@MainActor
struct APIIntegrationTests {
    
    var api: APIClient
    
    init() {
        api = APIClient.shared
        // Clear any existing token
        api.setToken(nil)
    }
    
    // MARK: - Homes
    
    @Test("Create home via API")
    func createHomeViaAPI() async throws {
        // Requires authentication
        guard api.hasToken else {
            throw TestError.noAuthentication
        }
        
        let home = try await api.createHome(name: "Integration Test Home")
        
        #expect(home.name == "Integration Test Home")
        #expect(!home.id.isEmpty)
        
        // Cleanup
        try await api.deleteHome(home.id)
    }
    
    @Test("List homes from API")
    func listHomesFromAPI() async throws {
        guard api.hasToken else {
            throw TestError.noAuthentication
        }
        
        // Create a test home
        let created = try await api.createHome(name: "Test List Home")
        
        // List all homes
        let homes = try await api.listHomes()
        
        #expect(homes.contains(where: { $0.id == created.id }))
        
        // Cleanup
        try await api.deleteHome(created.id)
    }
    
    @Test("Get home details from API")
    func getHomeDetailsFromAPI() async throws {
        guard api.hasToken else {
            throw TestError.noAuthentication
        }
        
        // Create test home
        let created = try await api.createHome(name: "Test Details Home")
        
        // Get details
        let details: HomeDetail = try await api.getHome(created.id)
        
        #expect(details.id == created.id)
        #expect(details.name == "Test Details Home")
        #expect(details.locations.isEmpty)
        #expect(details.items.isEmpty)
        
        // Cleanup
        try await api.deleteHome(created.id)
    }
    
    @Test("Update home via API")
    func updateHomeViaAPI() async throws {
        guard api.hasToken else {
            throw TestError.noAuthentication
        }
        
        // Create test home
        let created = try await api.createHome(name: "Original Name")
        
        // Update
        let updated = try await api.updateHome(created.id, name: "Updated Name")
        
        #expect(updated.name == "Updated Name")
        #expect(updated.id == created.id)
        
        // Cleanup
        try await api.deleteHome(created.id)
    }
    
    @Test("Delete home via API")
    func deleteHomeViaAPI() async throws {
        guard api.hasToken else {
            throw TestError.noAuthentication
        }
        
        // Create test home
        let created = try await api.createHome(name: "To Delete")
        
        // Delete
        try await api.deleteHome(created.id)
        
        // Verify deleted
        do {
            let _: HomeDetail = try await api.getHome(created.id)
            Issue.record("Home should have been deleted")
        } catch {
            // Expected to fail
        }
    }
    
    // MARK: - Locations
    
    @Test("Create location via API")
    func createLocationViaAPI() async throws {
        guard api.hasToken else {
            throw TestError.noAuthentication
        }
        
        let home = try await api.createHome(name: "Test Home")
        
        let location = try await api.createLocation(
            homeId: home.id,
            name: "Living Room",
            parentId: nil,
            type: "room"
        )
        
        #expect(location.name == "Living Room")
        #expect(location.type == .room)
        
        // Cleanup
        try await api.deleteHome(home.id)
    }
    
    @Test("Create nested location via API")
    func createNestedLocationViaAPI() async throws {
        guard api.hasToken else {
            throw TestError.noAuthentication
        }
        
        let home = try await api.createHome(name: "Test Home")
        let room = try await api.createLocation(
            homeId: home.id,
            name: "Bedroom",
            parentId: nil,
            type: "room"
        )
        
        let container = try await api.createLocation(
            homeId: home.id,
            name: "Closet",
            parentId: room.id,
            type: "container"
        )
        
        #expect(container.parentId == room.id)
        
        // Cleanup
        try await api.deleteHome(home.id)
    }
    
    // MARK: - Items
    
    @Test("Create item via API")
    func createItemViaAPI() async throws {
        guard api.hasToken else {
            throw TestError.noAuthentication
        }
        
        let home = try await api.createHome(name: "Test Home")
        
        let body = APIClient.ItemBody(
            name: "Coffee Maker",
            locationId: nil,
            notes: "Black & Decker",
            quantity: 1,
            tags: ["appliance"],
            photoUrl: nil,
            purchaseDate: "2024-01-01"
        )
        
        let item = try await api.createItem(homeId: home.id, body: body)
        
        #expect(item.name == "Coffee Maker")
        #expect(item.notes == "Black & Decker")
        #expect(item.quantity == 1)
        #expect(item.tags == ["appliance"])
        
        // Cleanup
        try await api.deleteHome(home.id)
    }
    
    @Test("Update item via API")
    func updateItemViaAPI() async throws {
        guard api.hasToken else {
            throw TestError.noAuthentication
        }
        
        let home = try await api.createHome(name: "Test Home")
        
        let createBody = APIClient.ItemBody(
            name: "Original",
            locationId: nil,
            notes: nil,
            quantity: 1,
            tags: [],
            photoUrl: nil,
            purchaseDate: nil
        )
        let created = try await api.createItem(homeId: home.id, body: createBody)
        
        let updateBody = APIClient.ItemBody(
            name: "Updated",
            locationId: nil,
            notes: "New notes",
            quantity: 2,
            tags: ["tag1"],
            photoUrl: nil,
            purchaseDate: nil
        )
        let updated = try await api.updateItem(homeId: home.id, itemId: created.id, body: updateBody)
        
        #expect(updated.name == "Updated")
        #expect(updated.notes == "New notes")
        #expect(updated.quantity == 2)
        
        // Cleanup
        try await api.deleteHome(home.id)
    }
    
    @Test("Search items via API")
    func searchItemsViaAPI() async throws {
        guard api.hasToken else {
            throw TestError.noAuthentication
        }
        
        let home = try await api.createHome(name: "Test Home")
        
        // Create test items
        _ = try await api.createItem(homeId: home.id, body: APIClient.ItemBody(
            name: "Coffee Maker",
            locationId: nil,
            notes: nil,
            quantity: 1,
            tags: [],
            photoUrl: nil,
            purchaseDate: nil
        ))
        
        _ = try await api.createItem(homeId: home.id, body: APIClient.ItemBody(
            name: "Coffee Grinder",
            locationId: nil,
            notes: nil,
            quantity: 1,
            tags: [],
            photoUrl: nil,
            purchaseDate: nil
        ))
        
        _ = try await api.createItem(homeId: home.id, body: APIClient.ItemBody(
            name: "Tea Kettle",
            locationId: nil,
            notes: nil,
            quantity: 1,
            tags: [],
            photoUrl: nil,
            purchaseDate: nil
        ))
        
        // Search
        let results = try await api.searchItems(homeId: home.id, query: "coffee")
        
        #expect(results.count >= 2)
        #expect(results.allSatisfy { $0.name.lowercased().contains("coffee") })
        
        // Cleanup
        try await api.deleteHome(home.id)
    }
    
    // MARK: - Full Sync Flow
    
    @Test("Complete sync workflow")
    func completeSyncWorkflow() async throws {
        guard api.hasToken else {
            throw TestError.noAuthentication
        }
        
        let localData = LocalDataManager.shared
        let syncManager = SyncManager.shared
        
        localData.clearAllData()
        
        // 1. Create local data
        let localHome = localData.createHome(name: "Sync Test Home")
        let localLocation = try #require(localData.createLocation(
            homeId: localHome.id,
            name: "Test Room",
            parentId: nil,
            type: "room"
        ))
        let localItem = try #require(localData.createItem(
            homeId: localHome.id,
            name: "Test Item",
            locationId: localLocation.id
        ))
        
        #expect(localHome.needsSync == true)
        #expect(localLocation.needsSync == true)
        #expect(localItem.needsSync == true)
        
        // 2. Push to server
        try await syncManager.pushToServer()
        
        #expect(localHome.needsSync == false)
        #expect(localLocation.needsSync == false)
        #expect(localItem.needsSync == false)
        
        // 3. Clear local and pull from server
        let serverId = localHome.ownerId // Should now have server ID
        localData.clearAllData()
        
        try await syncManager.pullFromServer()
        
        let homes = localData.fetchHomes()
        #expect(homes.count >= 1)
        
        // 4. Cleanup
        if let serverHome = homes.first(where: { $0.ownerId == serverId }) {
            try await api.deleteHome(serverHome.id)
        }
    }
}

// MARK: - Error Cases

@Suite("API Error Handling", .disabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != "1"))
@MainActor
struct APIErrorHandlingTests {
    
    @Test("Handle 404 not found")
    func handle404NotFound() async throws {
        let api = APIClient.shared
        
        do {
            let _: HomeDetail = try await api.getHome("non-existent-id")
            Issue.record("Should have thrown 404 error")
        } catch APIError.httpError(let code, _) {
            #expect(code == 404)
        }
    }
    
    @Test("Handle unauthorized")
    func handleUnauthorized() async throws {
        let api = APIClient.shared
        
        // Clear token
        api.setToken(nil)
        
        do {
            _ = try await api.listHomes()
            Issue.record("Should have thrown 401 error")
        } catch APIError.httpError(let code, _) {
            #expect(code == 401)
        }
    }
    
    @Test("Handle network timeout")
    func handleNetworkTimeout() async throws {
        // This would require actual network manipulation
        // or a mock server that delays responses
    }
}

// MARK: - Test Utilities

enum TestError: Error {
    case noAuthentication
}
