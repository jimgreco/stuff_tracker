import Testing
import Foundation
@testable import StuffTracker

@Suite("Local Data Manager Tests")
@MainActor
struct LocalDataManagerTests {
    
    var manager: LocalDataManager
    
    init() async {
        manager = LocalDataManager.shared
        // Clean slate for each test
        manager.clearAllData()
    }
    
    @Test("Create and fetch home")
    func createAndFetchHome() async throws {
        let home = manager.createHome(name: "Test Home")
        
        #expect(home.name == "Test Home")
        #expect(home.needsSync == true)
        
        let fetched = manager.fetchHome(id: home.id)
        #expect(fetched != nil)
        #expect(fetched?.name == "Test Home")
    }
    
    @Test("Fetch all homes")
    func fetchAllHomes() async throws {
        _ = manager.createHome(name: "Home 1")
        _ = manager.createHome(name: "Home 2")
        _ = manager.createHome(name: "Home 3")
        
        let homes = manager.fetchHomes()
        #expect(homes.count == 3)
    }
    
    @Test("Update home marks needsSync")
    func updateHomeMarksNeedsSync() async throws {
        let home = manager.createHome(name: "Original")
        home.needsSync = false
        
        home.name = "Updated"
        manager.updateHome(home)
        
        #expect(home.needsSync == true)
    }
    
    @Test("Delete home soft deletes")
    func deleteHomeSoftDeletes() async throws {
        let home = manager.createHome(name: "To Delete")
        let homeId = home.id
        
        manager.deleteHome(home)
        
        #expect(home.isDeleted == true)
        
        // Should not appear in normal fetches
        let homes = manager.fetchHomes()
        #expect(homes.contains(where: { $0.id == homeId }) == false)
    }
    
    @Test("Create location in home")
    func createLocationInHome() async throws {
        let home = manager.createHome(name: "Test Home")
        let location = try #require(manager.createLocation(
            homeId: home.id,
            name: "Living Room",
            parentId: nil,
            type: "room"
        ))
        
        #expect(location.name == "Living Room")
        #expect(location.type == "room")
        #expect(location.homeId == home.id)
        #expect(location.needsSync == true)
        
        // Verify relationship
        #expect(home.locations.contains(where: { $0.id == location.id }))
    }
    
    @Test("Create nested container")
    func createNestedContainer() async throws {
        let home = manager.createHome(name: "Test Home")
        let room = try #require(manager.createLocation(
            homeId: home.id,
            name: "Bedroom",
            parentId: nil,
            type: "room"
        ))
        
        let container = try #require(manager.createLocation(
            homeId: home.id,
            name: "Closet",
            parentId: room.id,
            type: "container"
        ))
        
        #expect(container.parentId == room.id)
        #expect(container.type == "container")
    }
    
    @Test("Create item in location")
    func createItemInLocation() async throws {
        let home = manager.createHome(name: "Test Home")
        let location = try #require(manager.createLocation(
            homeId: home.id,
            name: "Kitchen",
            parentId: nil,
            type: "room"
        ))
        
        let item = try #require(manager.createItem(
            homeId: home.id,
            name: "Coffee Maker",
            locationId: location.id
        ))
        
        #expect(item.name == "Coffee Maker")
        #expect(item.locationId == location.id)
        #expect(item.homeId == home.id)
        #expect(item.needsSync == true)
        
        // Verify relationship
        #expect(home.items.contains(where: { $0.id == item.id }))
    }
    
    @Test("Search items by name")
    func searchItemsByName() async throws {
        let home = manager.createHome(name: "Test Home")
        
        _ = manager.createItem(homeId: home.id, name: "Coffee Maker", locationId: nil)
        _ = manager.createItem(homeId: home.id, name: "Tea Kettle", locationId: nil)
        _ = manager.createItem(homeId: home.id, name: "Coffee Grinder", locationId: nil)
        
        let results = manager.searchItems(homeId: home.id, query: "coffee")
        
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.name.lowercased().contains("coffee") })
    }
    
    @Test("Merge home from server")
    func mergeHomeFromServer() async throws {
        let serverHome = Home(
            id: "server-123",
            name: "Server Home",
            ownerId: "user-456",
            role: "owner"
        )
        
        manager.mergeFromServer(homes: [serverHome])
        
        let fetched = manager.fetchHome(id: "server-123")
        #expect(fetched != nil)
        #expect(fetched?.name == "Server Home")
        #expect(fetched?.needsSync == false)
    }
    
    @Test("Merge updates existing home")
    func mergeUpdatesExistingHome() async throws {
        // Create local home first
        let localHome = manager.createHome(name: "Local Name")
        localHome.needsSync = true
        
        // Server returns updated version
        let serverHome = Home(
            id: localHome.id,
            name: "Updated Server Name",
            ownerId: "user-123",
            role: "admin"
        )
        
        manager.mergeFromServer(homes: [serverHome])
        
        let fetched = manager.fetchHome(id: localHome.id)
        #expect(fetched?.name == "Updated Server Name")
        #expect(fetched?.role == "admin")
        #expect(fetched?.needsSync == false)
    }
    
    @Test("Convert local home to API model")
    func convertLocalHomeToAPIModel() async throws {
        let localHome = manager.createHome(name: "Test Home")
        let apiHome = localHome.toHome()
        
        #expect(apiHome.id == localHome.id)
        #expect(apiHome.name == localHome.name)
    }
    
    @Test("Convert to HomeDetail includes locations and items")
    func convertToHomeDetailIncludesRelations() async throws {
        let home = manager.createHome(name: "Test Home")
        let location = try #require(manager.createLocation(
            homeId: home.id,
            name: "Room",
            parentId: nil,
            type: "room"
        ))
        let item = try #require(manager.createItem(
            homeId: home.id,
            name: "Item",
            locationId: location.id
        ))
        
        let homeDetail = home.toHomeDetail()
        
        #expect(homeDetail.locations.count == 1)
        #expect(homeDetail.items.count == 1)
        #expect(homeDetail.locations.first?.id == location.id)
        #expect(homeDetail.items.first?.id == item.id)
    }
}
