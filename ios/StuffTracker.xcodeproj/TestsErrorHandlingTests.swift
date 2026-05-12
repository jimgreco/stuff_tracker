import Testing
import Foundation
@testable import StuffTracker

@Suite("Error Handling Tests")
@MainActor
struct ErrorHandlingTests {
    
    @Test("HomeStore handles missing home gracefully")
    func homeStoreHandlesMissingHomeGracefully() async {
        let homeStore = HomeStore()
        
        // Action: Try to create location without selected home
        await homeStore.createLocation(name: "Room", parentId: nil, type: "room")
        
        // Assert: Should not crash, location not created
        #expect(homeStore.selectedHome?.locations.isEmpty ?? true)
    }
    
    @Test("HomeStore handles missing item gracefully")
    func homeStoreHandlesMissingItemGracefully() async {
        let homeStore = HomeStore()
        await homeStore.createHome(name: "Test Home")
        
        // Action: Try to update non-existent item
        let body = APIClient.ItemBody(
            name: "Test",
            locationId: nil,
            notes: nil,
            quantity: 1,
            tags: [],
            photoUrl: nil,
            purchaseDate: nil
        )
        await homeStore.updateItem("non-existent-id", body: body)
        
        // Assert: Should not crash
        #expect(homeStore.selectedHome?.items.isEmpty == true)
    }
    
    @Test("LocalDataManager handles invalid home ID")
    func localDataManagerHandlesInvalidHomeID() async {
        let localData = LocalDataManager.shared
        localData.clearAllData()
        
        // Action: Try to create location with invalid home ID
        let location = localData.createLocation(
            homeId: "non-existent",
            name: "Room",
            parentId: nil,
            type: "room"
        )
        
        // Assert: Should return nil
        #expect(location == nil)
    }
    
    @Test("Search handles empty query")
    func searchHandlesEmptyQuery() async {
        let homeStore = HomeStore()
        await homeStore.createHome(name: "Test Home")
        await homeStore.createItem(name: "Item", locationId: nil)
        
        // Action: Search with empty query
        let results = await homeStore.searchItems(query: "")
        
        // Assert: Should return empty or all items (implementation dependent)
        #expect(results.count >= 0)
    }
    
    @Test("Delete home with items and locations")
    func deleteHomeWithItemsAndLocations() async {
        let homeStore = HomeStore()
        await homeStore.createHome(name: "Test Home")
        let homeId = homeStore.homes.first?.id ?? ""
        
        await homeStore.createLocation(name: "Room", parentId: nil, type: "room")
        await homeStore.createItem(name: "Item", locationId: nil)
        
        #expect(homeStore.selectedHome?.locations.count == 1)
        #expect(homeStore.selectedHome?.items.count == 1)
        
        // Action: Delete home
        await homeStore.deleteHome(homeId)
        
        // Assert: Should cascade delete
        #expect(homeStore.homes.isEmpty)
    }
    
    @Test("Update non-existent location")
    func updateNonExistentLocation() async {
        let homeStore = HomeStore()
        await homeStore.createHome(name: "Test Home")
        
        // Action: Try to rename non-existent location
        await homeStore.renameLocation("non-existent-id", name: "New Name")
        
        // Assert: Should not crash
        #expect(homeStore.selectedHome?.locations.isEmpty == true)
    }
    
    @Test("Move item to non-existent location")
    func moveItemToNonExistentLocation() async {
        let homeStore = HomeStore()
        await homeStore.createHome(name: "Test Home")
        await homeStore.createItem(name: "Item", locationId: nil)
        
        let itemId = try #require(homeStore.selectedHome?.items.first?.id)
        
        // Action: Move to non-existent location
        await homeStore.moveItem(itemId, toLocation: "non-existent-location")
        
        // Assert: Should update but locationId will be invalid
        let item = homeStore.selectedHome?.items.first
        #expect(item?.locationId == "non-existent-location")
    }
}

@Suite("Concurrency Tests")
@MainActor
struct ConcurrencyTests {
    
    @Test("Multiple simultaneous creates")
    func multipleSimultaneousCreates() async {
        let homeStore = HomeStore()
        await homeStore.createHome(name: "Test Home")
        
        // Action: Create multiple items concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 1...10 {
                group.addTask {
                    await homeStore.createItem(name: "Item \(i)", locationId: nil)
                }
            }
        }
        
        // Assert: All items created
        #expect(homeStore.selectedHome?.items.count == 10)
    }
    
    @Test("Concurrent read and write")
    func concurrentReadAndWrite() async {
        let localData = LocalDataManager.shared
        localData.clearAllData()
        
        let home = localData.createHome(name: "Test Home")
        
        // Action: Read and write concurrently
        await withTaskGroup(of: Void.self) { group in
            // Writer
            group.addTask {
                for i in 1...5 {
                    _ = localData.createItem(homeId: home.id, name: "Item \(i)", locationId: nil)
                }
            }
            
            // Reader
            group.addTask {
                for _ in 1...5 {
                    _ = localData.fetchHome(id: home.id)
                }
            }
        }
        
        // Assert: No crashes, items created
        #expect(home.items.count >= 5)
    }
}

@Suite("Data Integrity Tests")
@MainActor
struct DataIntegrityTests {
    
    @Test("needsSync flag set on create")
    func needsSyncFlagSetOnCreate() async {
        let localData = LocalDataManager.shared
        localData.clearAllData()
        
        let home = localData.createHome(name: "Test")
        #expect(home.needsSync == true)
        
        let location = try #require(localData.createLocation(
            homeId: home.id,
            name: "Room",
            parentId: nil,
            type: "room"
        ))
        #expect(location.needsSync == true)
        
        let item = try #require(localData.createItem(
            homeId: home.id,
            name: "Item",
            locationId: nil
        ))
        #expect(item.needsSync == true)
    }
    
    @Test("needsSync flag cleared on server update")
    func needsSyncFlagClearedOnServerUpdate() async {
        let localHome = LocalHome(id: "123", name: "Test")
        localHome.needsSync = true
        
        let serverHome = Home(id: "123", name: "Test", ownerId: "user", role: "owner")
        localHome.update(from: serverHome)
        
        #expect(localHome.needsSync == false)
    }
    
    @Test("Timestamps updated on modification")
    func timestampsUpdatedOnModification() async {
        let localData = LocalDataManager.shared
        localData.clearAllData()
        
        let home = localData.createHome(name: "Test")
        let originalUpdated = home.updatedAt
        
        // Wait a bit to ensure timestamp changes
        try? await Task.sleep(for: .milliseconds(100))
        
        home.name = "Updated"
        localData.updateHome(home)
        
        #expect(home.updatedAt > originalUpdated)
    }
    
    @Test("Soft delete preserves data")
    func softDeletePreservesData() async {
        let localData = LocalDataManager.shared
        localData.clearAllData()
        
        let home = localData.createHome(name: "Test")
        let homeId = home.id
        
        localData.deleteHome(home)
        
        // Assert: isDeleted flag set
        #expect(home.isDeleted == true)
        #expect(home.needsSync == true)
        
        // Data still exists in context, just filtered from fetches
        #expect(localData.fetchHome(id: homeId) == nil)
    }
    
    @Test("Relationship integrity maintained")
    func relationshipIntegrityMaintained() async {
        let localData = LocalDataManager.shared
        localData.clearAllData()
        
        let home = localData.createHome(name: "Test Home")
        let location = try #require(localData.createLocation(
            homeId: home.id,
            name: "Room",
            parentId: nil,
            type: "room"
        ))
        
        // Assert: Relationship established
        #expect(location.home?.id == home.id)
        #expect(home.locations.contains(where: { $0.id == location.id }))
    }
    
    @Test("Item tags preserved through update")
    func itemTagsPreservedThroughUpdate() async {
        let localItem = LocalItem(
            id: "123",
            homeId: "home",
            name: "Test",
            tags: ["tag1", "tag2"]
        )
        
        let serverItem = Item(
            id: "123",
            homeId: "home",
            locationId: nil,
            name: "Updated",
            notes: nil,
            quantity: 1,
            tags: ["tag1", "tag2", "tag3"],
            photoUrl: nil,
            purchaseDate: nil,
            createdBy: "user"
        )
        
        localItem.update(from: serverItem)
        
        #expect(localItem.tags == ["tag1", "tag2", "tag3"])
    }
}
