import Testing
import Foundation
@testable import StuffTracker

@Suite("Home Store Integration Tests")
@MainActor
struct HomeStoreIntegrationTests {
    
    var homeStore: HomeStore
    var localData: LocalDataManager
    
    init() async {
        localData = LocalDataManager.shared
        localData.clearAllData()
        homeStore = HomeStore()
    }
    
    @Test("Load homes shows local data immediately")
    func loadHomesShowsLocalDataImmediately() async {
        // Setup: Create local homes
        _ = localData.createHome(name: "Home 1")
        _ = localData.createHome(name: "Home 2")
        
        // Action: Load homes
        await homeStore.loadHomes()
        
        // Assert: Should see local homes
        #expect(homeStore.homes.count == 2)
        #expect(homeStore.homes.contains(where: { $0.name == "Home 1" }))
    }
    
    @Test("Create home works offline")
    func createHomeWorksOffline() async {
        // Action: Create home while offline (no API client configured)
        await homeStore.createHome(name: "Offline Home")
        
        // Assert: Home created locally
        #expect(homeStore.homes.count == 1)
        #expect(homeStore.homes.first?.name == "Offline Home")
        #expect(homeStore.selectedHome?.name == "Offline Home")
        
        // Verify in local storage
        let localHomes = localData.fetchHomes()
        #expect(localHomes.count == 1)
        #expect(localHomes.first?.needsSync == true)
    }
    
    @Test("Create location works offline")
    func createLocationWorksOffline() async {
        // Setup: Create a home first
        await homeStore.createHome(name: "Test Home")
        
        // Action: Create location
        await homeStore.createLocation(name: "Living Room", parentId: nil, type: "room")
        
        // Assert: Location created
        #expect(homeStore.selectedHome?.locations.count == 1)
        #expect(homeStore.selectedHome?.locations.first?.name == "Living Room")
    }
    
    @Test("Create item works offline")
    func createItemWorksOffline() async {
        // Setup: Create home and location
        await homeStore.createHome(name: "Test Home")
        await homeStore.createLocation(name: "Kitchen", parentId: nil, type: "room")
        
        let locationId = homeStore.selectedHome?.locations.first?.id
        
        // Action: Create item
        await homeStore.createItem(name: "Coffee Maker", locationId: locationId)
        
        // Assert: Item created
        #expect(homeStore.selectedHome?.items.count == 1)
        #expect(homeStore.selectedHome?.items.first?.name == "Coffee Maker")
    }
    
    @Test("Update item works offline")
    func updateItemWorksOffline() async {
        // Setup: Create item
        await homeStore.createHome(name: "Test Home")
        await homeStore.createItem(name: "Original Name", locationId: nil)
        
        let itemId = try #require(homeStore.selectedHome?.items.first?.id)
        
        // Action: Update item
        let body = APIClient.ItemBody(
            name: "Updated Name",
            locationId: nil,
            notes: "New notes",
            quantity: 2,
            tags: ["tag1"],
            photoUrl: nil,
            purchaseDate: nil
        )
        await homeStore.updateItem(itemId, body: body)
        
        // Assert: Item updated locally
        let updatedItem = homeStore.selectedHome?.items.first
        #expect(updatedItem?.name == "Updated Name")
        #expect(updatedItem?.notes == "New notes")
        #expect(updatedItem?.quantity == 2)
    }
    
    @Test("Delete home works offline")
    func deleteHomeWorksOffline() async {
        // Setup: Create homes
        await homeStore.createHome(name: "Home 1")
        let homeId = homeStore.homes.first?.id ?? ""
        await homeStore.createHome(name: "Home 2")
        
        #expect(homeStore.homes.count == 2)
        
        // Action: Delete first home
        await homeStore.deleteHome(homeId)
        
        // Assert: Home removed from list
        #expect(homeStore.homes.count == 1)
        #expect(homeStore.homes.first?.name == "Home 2")
        
        // Verify soft delete in local storage
        let localHome = localData.fetchHome(id: homeId)
        #expect(localHome == nil) // Should not appear in normal fetch
    }
    
    @Test("Search items works offline")
    func searchItemsWorksOffline() async {
        // Setup: Create items
        await homeStore.createHome(name: "Test Home")
        await homeStore.createItem(name: "Coffee Maker", locationId: nil)
        await homeStore.createItem(name: "Tea Kettle", locationId: nil)
        await homeStore.createItem(name: "Coffee Grinder", locationId: nil)
        
        // Action: Search for "coffee"
        let results = await homeStore.searchItems(query: "coffee")
        
        // Assert: Found matching items
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.name.lowercased().contains("coffee") })
    }
    
    @Test("Move item between locations")
    func moveItemBetweenLocations() async {
        // Setup: Create home with two locations and one item
        await homeStore.createHome(name: "Test Home")
        await homeStore.createLocation(name: "Kitchen", parentId: nil, type: "room")
        await homeStore.createLocation(name: "Bedroom", parentId: nil, type: "room")
        
        let kitchenId = homeStore.selectedHome?.locations.first(where: { $0.name == "Kitchen" })?.id
        let bedroomId = homeStore.selectedHome?.locations.first(where: { $0.name == "Bedroom" })?.id
        
        await homeStore.createItem(name: "Keys", locationId: kitchenId)
        let itemId = try #require(homeStore.selectedHome?.items.first?.id)
        
        // Action: Move item to bedroom
        await homeStore.moveItem(itemId, toLocation: bedroomId)
        
        // Assert: Item location updated
        let movedItem = homeStore.selectedHome?.items.first(where: { $0.id == itemId })
        #expect(movedItem?.locationId == bedroomId)
    }
    
    @Test("Rename location")
    func renameLocation() async {
        // Setup: Create location
        await homeStore.createHome(name: "Test Home")
        await homeStore.createLocation(name: "Living Room", parentId: nil, type: "room")
        
        let locationId = try #require(homeStore.selectedHome?.locations.first?.id)
        
        // Action: Rename
        await homeStore.renameLocation(locationId, name: "Family Room")
        
        // Assert: Location renamed
        let renamedLocation = homeStore.selectedHome?.locations.first(where: { $0.id == locationId })
        #expect(renamedLocation?.name == "Family Room")
    }
    
    @Test("Delete location removes items from location")
    func deleteLocationRemovesItemsFromLocation() async {
        // Setup: Create location with item
        await homeStore.createHome(name: "Test Home")
        await homeStore.createLocation(name: "Garage", parentId: nil, type: "room")
        
        let locationId = try #require(homeStore.selectedHome?.locations.first?.id)
        await homeStore.createItem(name: "Car", locationId: locationId)
        
        #expect(homeStore.selectedHome?.items.first?.locationId == locationId)
        
        // Action: Delete location
        await homeStore.deleteLocation(locationId)
        
        // Assert: Location removed and item's locationId cleared
        #expect(homeStore.selectedHome?.locations.isEmpty == true)
        #expect(homeStore.selectedHome?.items.first?.locationId == nil)
    }
    
    @Test("Create nested containers")
    func createNestedContainers() async {
        // Setup: Create home and room
        await homeStore.createHome(name: "Test Home")
        await homeStore.createLocation(name: "Bedroom", parentId: nil, type: "room")
        
        let roomId = try #require(homeStore.selectedHome?.locations.first?.id)
        
        // Action: Create container in room
        await homeStore.createLocation(name: "Closet", parentId: roomId, type: "container")
        
        // Assert: Container created with correct parent
        let container = homeStore.selectedHome?.locations.first(where: { $0.name == "Closet" })
        #expect(container?.parentId == roomId)
        #expect(container?.type == .container)
    }
    
    @Test("Select different home")
    func selectDifferentHome() async {
        // Setup: Create multiple homes
        await homeStore.createHome(name: "Home 1")
        let home1Id = homeStore.homes.first?.id ?? ""
        
        await homeStore.createHome(name: "Home 2")
        let home2Id = homeStore.homes.last?.id ?? ""
        
        #expect(homeStore.selectedHome?.name == "Home 2")
        
        // Action: Select first home
        await homeStore.selectHome(home1Id)
        
        // Assert: Selection changed
        #expect(homeStore.selectedHome?.id == home1Id)
        #expect(homeStore.selectedHome?.name == "Home 1")
    }
}
