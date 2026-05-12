import Testing
import Foundation
@testable import StuffTracker

@Suite("Model Conversion Tests")
struct ModelConversionTests {
    
    @Test("LocalHome converts to Home")
    func localHomeConvertsToHome() {
        let localHome = LocalHome(
            id: "123",
            name: "Test Home",
            ownerId: "user-456",
            role: "owner"
        )
        
        let home = localHome.toHome()
        
        #expect(home.id == "123")
        #expect(home.name == "Test Home")
        #expect(home.ownerId == "user-456")
        #expect(home.role == "owner")
    }
    
    @Test("LocalHome converts to HomeDetail with relations")
    @MainActor
    func localHomeConvertsToHomeDetailWithRelations() async {
        let localData = LocalDataManager.shared
        localData.clearAllData()
        
        let home = localData.createHome(name: "Test Home")
        _ = localData.createLocation(homeId: home.id, name: "Room", parentId: nil, type: "room")
        _ = localData.createItem(homeId: home.id, name: "Item", locationId: nil)
        
        let homeDetail = home.toHomeDetail()
        
        #expect(homeDetail.id == home.id)
        #expect(homeDetail.name == "Test Home")
        #expect(homeDetail.locations.count == 1)
        #expect(homeDetail.items.count == 1)
    }
    
    @Test("LocalLocation converts to Location")
    func localLocationConvertsToLocation() {
        let localLocation = LocalLocation(
            id: "loc-123",
            homeId: "home-456",
            parentId: "parent-789",
            name: "Living Room",
            type: "room",
            sortOrder: 5
        )
        
        let location = localLocation.toLocation()
        
        #expect(location.id == "loc-123")
        #expect(location.homeId == "home-456")
        #expect(location.parentId == "parent-789")
        #expect(location.name == "Living Room")
        #expect(location.type == .room)
        #expect(location.sortOrder == 5)
    }
    
    @Test("LocalItem converts to Item")
    func localItemConvertsToItem() {
        let localItem = LocalItem(
            id: "item-123",
            homeId: "home-456",
            locationId: "loc-789",
            name: "Coffee Maker",
            notes: "Black Decker",
            quantity: 1,
            tags: ["appliance", "kitchen"],
            photoUrl: "https://example.com/photo.jpg",
            purchaseDate: "2024-01-01",
            createdBy: "user-999"
        )
        
        let item = localItem.toItem()
        
        #expect(item.id == "item-123")
        #expect(item.homeId == "home-456")
        #expect(item.locationId == "loc-789")
        #expect(item.name == "Coffee Maker")
        #expect(item.notes == "Black Decker")
        #expect(item.quantity == 1)
        #expect(item.tags == ["appliance", "kitchen"])
        #expect(item.photoUrl == "https://example.com/photo.jpg")
        #expect(item.purchaseDate == "2024-01-01")
        #expect(item.createdBy == "user-999")
    }
    
    @Test("Home updates LocalHome")
    func homeUpdatesLocalHome() {
        let localHome = LocalHome(
            id: "123",
            name: "Original",
            ownerId: "old-owner",
            role: "viewer"
        )
        localHome.needsSync = true
        
        let serverHome = Home(
            id: "123",
            name: "Updated",
            ownerId: "new-owner",
            role: "admin"
        )
        
        localHome.update(from: serverHome)
        
        #expect(localHome.name == "Updated")
        #expect(localHome.ownerId == "new-owner")
        #expect(localHome.role == "admin")
        #expect(localHome.needsSync == false)
    }
    
    @Test("Location updates LocalLocation")
    func locationUpdatesLocalLocation() {
        let localLocation = LocalLocation(
            id: "123",
            homeId: "home-456",
            name: "Original",
            type: "room"
        )
        localLocation.needsSync = true
        
        let serverLocation = Location(
            id: "123",
            homeId: "home-456",
            parentId: "parent-789",
            name: "Updated",
            type: .container,
            sortOrder: 10
        )
        
        localLocation.update(from: serverLocation)
        
        #expect(localLocation.name == "Updated")
        #expect(localLocation.parentId == "parent-789")
        #expect(localLocation.type == "container")
        #expect(localLocation.sortOrder == 10)
        #expect(localLocation.needsSync == false)
    }
    
    @Test("Item updates LocalItem")
    func itemUpdatesLocalItem() {
        let localItem = LocalItem(
            id: "123",
            homeId: "home-456",
            name: "Original"
        )
        localItem.needsSync = true
        
        let serverItem = Item(
            id: "123",
            homeId: "home-456",
            locationId: "loc-789",
            name: "Updated",
            notes: "New notes",
            quantity: 5,
            tags: ["tag1", "tag2"],
            photoUrl: "https://example.com/new.jpg",
            purchaseDate: "2024-02-01",
            createdBy: "user-999"
        )
        
        localItem.update(from: serverItem)
        
        #expect(localItem.name == "Updated")
        #expect(localItem.locationId == "loc-789")
        #expect(localItem.notes == "New notes")
        #expect(localItem.quantity == 5)
        #expect(localItem.tags == ["tag1", "tag2"])
        #expect(localItem.photoUrl == "https://example.com/new.jpg")
        #expect(localItem.purchaseDate == "2024-02-01")
        #expect(localItem.needsSync == false)
    }
    
    @Test("Deleted items filtered from HomeDetail")
    @MainActor
    func deletedItemsFilteredFromHomeDetail() async {
        let localData = LocalDataManager.shared
        localData.clearAllData()
        
        let home = localData.createHome(name: "Test Home")
        let item1 = try #require(localData.createItem(homeId: home.id, name: "Item 1", locationId: nil))
        let item2 = try #require(localData.createItem(homeId: home.id, name: "Item 2", locationId: nil))
        
        // Delete item 1
        localData.deleteItem(item1)
        
        let homeDetail = home.toHomeDetail()
        
        // Only non-deleted items should appear
        #expect(homeDetail.items.count == 1)
        #expect(homeDetail.items.first?.name == "Item 2")
    }
    
    @Test("Deleted locations filtered from HomeDetail")
    @MainActor
    func deletedLocationsFilteredFromHomeDetail() async {
        let localData = LocalDataManager.shared
        localData.clearAllData()
        
        let home = localData.createHome(name: "Test Home")
        let loc1 = try #require(localData.createLocation(homeId: home.id, name: "Room 1", parentId: nil, type: "room"))
        let loc2 = try #require(localData.createLocation(homeId: home.id, name: "Room 2", parentId: nil, type: "room"))
        
        // Delete location 1
        localData.deleteLocation(loc1)
        
        let homeDetail = home.toHomeDetail()
        
        // Only non-deleted locations should appear
        #expect(homeDetail.items.count == 1)
        #expect(homeDetail.locations.first?.name == "Room 2")
    }
}
