import Foundation
import SwiftData
import XCTest
@testable import StuffTracker

final class ShippedStoreMigrationTests: XCTestCase {
    @MainActor
    func testShippedSchemaMigratesPendingRowsAndDefaultsReplayIdentityToUnknown() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cubby-shipped-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaultsName = "cubby-shipped-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: root)
        }
        let legacyURL = root.appendingPathComponent("default.store")
        let homeID = UUID().uuidString
        let deletedHomeID = UUID().uuidString
        let locationID = UUID().uuidString
        let itemID = UUID().uuidString
        try autoreleasepool {
            let schema = Schema([ShippedInventorySchema.LocalHome.self, ShippedInventorySchema.LocalLocation.self,
                                 ShippedInventorySchema.LocalItem.self, ShippedInventorySchema.SyncOperation.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: legacyURL, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let home = ShippedInventorySchema.LocalHome(id: homeID, name: "Original home", ownerId: "proven-owner")
            let deletedHome = ShippedInventorySchema.LocalHome(id: deletedHomeID, name: "Deleted home", ownerId: "proven-owner")
            let location = ShippedInventorySchema.LocalLocation(id: locationID, homeId: homeID, name: "Original location", type: "room")
            let item = ShippedInventorySchema.LocalItem(id: itemID, homeId: homeID, locationId: locationID, name: "Original item")
            item.documentsData = Data([0, 255, 17])
            let operation = ShippedInventorySchema.SyncOperation(entityType: "item", entityId: itemID, operation: "create", payload: Data([1, 254]))
            operation.failureCount = 3
            operation.lastError = "Lost reply"
            context.insert(home); context.insert(deletedHome); context.insert(location); context.insert(item); context.insert(operation)
            location.home = home; item.home = home
            try context.save() // The shipped create path saves before later edits.
            location.isDeleted = true
            item.isDeleted = true
            deletedHome.isDeleted = true
            try context.save()
            // The shipped property's getter collides with PersistentModel.isDeleted;
            // inspect the stored value via a predicate, not that unreliable getter.
            XCTAssertEqual(try context.fetch(FetchDescriptor<ShippedInventorySchema.LocalLocation>(predicate: #Predicate { $0.isDeleted })).count, 1)
            XCTAssertEqual(try context.fetch(FetchDescriptor<ShippedInventorySchema.LocalItem>(predicate: #Predicate { $0.isDeleted })).count, 1)
            XCTAssertEqual(try context.fetch(FetchDescriptor<ShippedInventorySchema.LocalHome>(predicate: #Predicate { $0.isDeleted })).count, 1)
        }
        defaults.set(true, forKey: AuthStore.completedAuthenticationDefaultsKey)
        defaults.set("proven-owner", forKey: LocalDataManager.accountOwnerKey)
        let local = LocalDataManager(accountDefaults: defaults, storageRoot: root.appendingPathComponent("accounts"), legacyURL: legacyURL)
        XCTAssertEqual(try local.bindAccount(userID: "proven-owner"), .allowed)
        let archive = try InventoryArchive(context: XCTUnwrap(local.context))
        XCTAssertEqual(Set(archive.homes.map(\.id)), [homeID, deletedHomeID])
        XCTAssertEqual(archive.locations.map(\.id), [locationID])
        XCTAssertEqual(archive.items.map(\.id), [itemID])
        XCTAssertNil(archive.homes[0].clientCreateID)
        XCTAssertNil(archive.locations[0].clientCreateID)
        XCTAssertNil(archive.items[0].clientCreateID)
        XCTAssertTrue(archive.items[0].needsSync)
        XCTAssertTrue(archive.locations[0].isDeleted)
        XCTAssertTrue(archive.items[0].isDeleted)
        XCTAssertTrue(try XCTUnwrap(archive.homes.first { $0.id == deletedHomeID }).isDeleted)
        XCTAssertEqual(local.fetchDeletedHomes().map(\.id), [deletedHomeID])
        XCTAssertEqual(local.fetchDeletedItems().map(\.id), [itemID])
        let detail = try XCTUnwrap(local.fetchHome(id: homeID)).toHomeDetail()
        XCTAssertTrue(detail.locations.isEmpty)
        XCTAssertTrue(detail.items.isEmpty)
        XCTAssertEqual(archive.items[0].relationshipHomeID, homeID)
        XCTAssertEqual(archive.items[0].documentsData, Data([0, 255, 17]))
        XCTAssertEqual(archive.operations[0].failureCount, 3)
        XCTAssertEqual(archive.operations[0].lastError, "Lost reply")
        XCTAssertEqual(archive.operations[0].payload, Data([1, 254]))
        // New client identities remain durable through account-store reopening.
        let newItem = try XCTUnwrap(local.createItem(homeId: homeID, name: "New durable create", locationId: nil))
        let newID = newItem.id
        local.deactivateAccount()
        let reopened = LocalDataManager(accountDefaults: defaults, storageRoot: root.appendingPathComponent("accounts"), legacyURL: legacyURL)
        XCTAssertEqual(try reopened.bindAccount(userID: "proven-owner"), .allowed)
        XCTAssertEqual(reopened.fetchItem(id: newID)?.clientCreateID, newID)
        XCTAssertNil(try XCTUnwrap(reopened.fetchDeletedItems().first { $0.id == itemID }).clientCreateID)
    }
}

// Freeze the shipped 5854a24 model declarations. Namespaced models preserve the
// original entity names and attributes, before clientCreateID existed.
private enum ShippedInventorySchema {

    // MARK: - Local SwiftData Models

    @Model
    final class LocalHome {
        @Attribute(.unique) var id: String
        var name: String
        var ownerId: String?
        var role: String
        var icon: String?
        var isFlagged: Bool = false
        var sortOrder: Int = 0
        var needsSync: Bool
        var isDeleted: Bool
        var createdAt: Date
        var updatedAt: Date

        @Relationship(deleteRule: .cascade, inverse: \LocalLocation.home)
        var locations: [LocalLocation]

        @Relationship(deleteRule: .cascade, inverse: \LocalItem.home)
        var items: [LocalItem]

        init(id: String = UUID().uuidString,
             name: String,
             ownerId: String? = nil,
             role: String = "owner",
             icon: String? = nil,
             isFlagged: Bool = false,
             sortOrder: Int = 0,
             needsSync: Bool = true,
             isDeleted: Bool = false) {
            self.id = id
            self.name = name
            self.ownerId = ownerId
            self.role = role
            self.icon = icon
            self.isFlagged = isFlagged
            self.sortOrder = sortOrder
            self.needsSync = needsSync
            self.isDeleted = isDeleted
            self.createdAt = Date()
            self.updatedAt = Date()
            self.locations = []
            self.items = []
        }

        // Convert to API model
        func toHome() -> Home {
            Home(id: id, name: name, ownerId: ownerId ?? "", role: role, icon: icon, isFlagged: isFlagged)
        }

        // Convert to HomeDetail
        func toHomeDetail() -> HomeDetail {
            HomeDetail(
                id: id,
                name: name,
                ownerId: ownerId ?? "",
                role: role,
                icon: icon,
                isFlagged: isFlagged,
                locations: locations.filter { !$0.isDeleted }.map { $0.toLocation() },
                items: items.filter { !$0.isDeleted }.map { $0.toItem() }
            )
        }

        // Update from server model
        func update(from home: Home) {
            self.name = home.name
            self.ownerId = home.ownerId
            self.role = home.role
            self.icon = home.icon
            self.isFlagged = home.isFlagged
            self.needsSync = false
            self.updatedAt = Date()
        }
    }

    @Model
    final class LocalLocation {
        @Attribute(.unique) var id: String
        var homeId: String
        var parentId: String?
        var name: String
        var type: String // "floor", "room" or "container"
        var sortOrder: Int
        var icon: String?
        var isFlagged: Bool = false
        var needsSync: Bool
        var isDeleted: Bool
        var createdAt: Date
        var updatedAt: Date

        var home: LocalHome?

        init(id: String = UUID().uuidString,
             homeId: String,
             parentId: String? = nil,
             name: String,
             type: String,
             sortOrder: Int = 0,
             icon: String? = nil,
             isFlagged: Bool = false,
             needsSync: Bool = true,
             isDeleted: Bool = false) {
            self.id = id
            self.homeId = homeId
            self.parentId = parentId
            self.name = name
            self.type = type
            self.sortOrder = sortOrder
            self.icon = icon
            self.isFlagged = isFlagged
            self.needsSync = needsSync
            self.isDeleted = isDeleted
            self.createdAt = Date()
            self.updatedAt = Date()
        }

        func toLocation() -> Location {
            Location(
                id: id,
                homeId: homeId,
                parentId: parentId,
                name: name,
                type: Location.LocationType(rawValue: type) ?? .room,
                sortOrder: sortOrder,
                icon: icon,
                isFlagged: isFlagged
            )
        }

        func update(from location: Location) {
            self.homeId = location.homeId
            self.parentId = location.parentId
            self.name = location.name
            self.type = location.type.rawValue
            self.sortOrder = location.sortOrder
            self.icon = location.icon
            self.isFlagged = location.isFlagged
            self.needsSync = false
            self.updatedAt = Date()
        }
    }

    @Model
    final class LocalItem {
        @Attribute(.unique) var id: String
        var homeId: String
        var locationId: String?
        var name: String
        var icon: String?
        var notes: String?
        var quantity: Int
        var propertiesData: Data?
        var photoUrls: [String] = []
        var documentsData: Data?
        var purchaseDate: String?
        var serialNumber: String?
        var modelNumber: String?
        var warrantyExpiresDate: String?
        var estimatedValueCents: Int?
        var isFlagged: Bool = false
        var sortOrder: Int = 0
        var createdBy: String?
        var needsSync: Bool
        var isDeleted: Bool
        var createdAt: Date
        var updatedAt: Date

        var home: LocalHome?

        init(id: String = UUID().uuidString,
             homeId: String,
             locationId: String? = nil,
             name: String,
             icon: String? = nil,
             notes: String? = nil,
             quantity: Int = 1,
             properties: [ItemProperty] = [],
             photoUrls: [String] = [],
             documents: [ItemDocument] = [],
             purchaseDate: String? = nil,
             serialNumber: String? = nil,
             modelNumber: String? = nil,
             warrantyExpiresDate: String? = nil,
             estimatedValueCents: Int? = nil,
             isFlagged: Bool = false,
             sortOrder: Int = 0,
             createdBy: String? = nil,
             needsSync: Bool = true,
             isDeleted: Bool = false) {
            self.id = id
            self.homeId = homeId
            self.locationId = locationId
            self.name = name
            self.icon = icon
            self.notes = notes
            self.quantity = quantity
            self.propertiesData = Self.encodedProperties(properties)
            self.photoUrls = photoUrls
            self.documentsData = Self.encodedDocuments(documents)
            self.purchaseDate = purchaseDate
            self.serialNumber = serialNumber
            self.modelNumber = modelNumber
            self.warrantyExpiresDate = warrantyExpiresDate
            self.estimatedValueCents = estimatedValueCents
            self.isFlagged = isFlagged
            self.sortOrder = sortOrder
            self.createdBy = createdBy
            self.needsSync = needsSync
            self.isDeleted = isDeleted
            self.createdAt = Date()
            self.updatedAt = Date()
        }

        func toItem() -> Item {
            Item(
                id: id,
                homeId: homeId,
                locationId: locationId,
                name: name,
                icon: icon,
                notes: notes,
                quantity: quantity,
                properties: properties,
                photoUrls: photoUrls,
                documents: documents,
                purchaseDate: purchaseDate,
                serialNumber: serialNumber,
                modelNumber: modelNumber,
                warrantyExpiresDate: warrantyExpiresDate,
                estimatedValueCents: estimatedValueCents,
                isFlagged: isFlagged,
                sortOrder: sortOrder,
                createdBy: createdBy ?? "",
                needsSync: needsSync
            )
        }

        func update(from item: Item) {
            self.homeId = item.homeId
            self.locationId = item.locationId
            self.name = item.name
            self.icon = item.icon
            self.notes = item.notes
            self.quantity = item.quantity
            self.properties = item.properties
            self.photoUrls = item.photoUrls
            self.documents = item.documents
            self.purchaseDate = item.purchaseDate
            self.serialNumber = item.serialNumber
            self.modelNumber = item.modelNumber
            self.warrantyExpiresDate = item.warrantyExpiresDate
            self.estimatedValueCents = item.estimatedValueCents
            self.isFlagged = item.isFlagged
            self.sortOrder = item.sortOrder
            self.needsSync = false
            self.updatedAt = Date()
        }

        var properties: [ItemProperty] {
            get {
                guard let propertiesData,
                      let decoded = try? JSONDecoder().decode([ItemProperty].self, from: propertiesData) else {
                    return []
                }
                return decoded
            }
            set {
                propertiesData = Self.encodedProperties(newValue)
            }
        }

        var documents: [ItemDocument] {
            get {
                guard let documentsData,
                      let decoded = try? JSONDecoder().decode([ItemDocument].self, from: documentsData) else {
                    return []
                }
                return decoded
            }
            set {
                documentsData = Self.encodedDocuments(newValue)
            }
        }

        private static func encodedProperties(_ properties: [ItemProperty]) -> Data? {
            try? JSONEncoder().encode(properties)
        }

        private static func encodedDocuments(_ documents: [ItemDocument]) -> Data? {
            try? JSONEncoder().encode(documents)
        }
    }

    // MARK: - Sync Operation

    @Model
    final class SyncOperation {
        @Attribute(.unique) var id: String
        var entityType: String // "home", "location", "item"
        var entityId: String
        var operation: String // "create", "update", "delete"
        var payload: Data? // JSON encoded data
        var createdAt: Date
        var failureCount: Int
        var lastError: String?

        init(entityType: String,
             entityId: String,
             operation: String,
             payload: Data? = nil) {
            self.id = UUID().uuidString
            self.entityType = entityType
            self.entityId = entityId
            self.operation = operation
            self.payload = payload
            self.createdAt = Date()
            self.failureCount = 0
        }
    }
}
