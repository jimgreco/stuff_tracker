import Foundation
import SwiftData

// MARK: - Local SwiftData Models

@Model
final class LocalHome {
    @Attribute(.unique) var id: String
    var name: String
    var ownerId: String?
    var role: String
    var icon: String?
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
         needsSync: Bool = true,
         isDeleted: Bool = false) {
        self.id = id
        self.name = name
        self.ownerId = ownerId
        self.role = role
        self.icon = icon
        self.needsSync = needsSync
        self.isDeleted = isDeleted
        self.createdAt = Date()
        self.updatedAt = Date()
        self.locations = []
        self.items = []
    }

    // Convert to API model
    func toHome() -> Home {
        Home(id: id, name: name, ownerId: ownerId ?? "", role: role, icon: icon)
    }

    // Convert to HomeDetail
    func toHomeDetail() -> HomeDetail {
        HomeDetail(
            id: id,
            name: name,
            ownerId: ownerId ?? "",
            role: role,
            icon: icon,
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
         needsSync: Bool = true,
         isDeleted: Bool = false) {
        self.id = id
        self.homeId = homeId
        self.parentId = parentId
        self.name = name
        self.type = type
        self.sortOrder = sortOrder
        self.icon = icon
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
            icon: icon
        )
    }

    func update(from location: Location) {
        self.parentId = location.parentId
        self.name = location.name
        self.type = location.type.rawValue
        self.sortOrder = location.sortOrder
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
    var tags: [String]
    var photoUrl: String?
    var purchaseDate: String?
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
         tags: [String] = [],
         photoUrl: String? = nil,
         purchaseDate: String? = nil,
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
        self.tags = tags
        self.photoUrl = photoUrl
        self.purchaseDate = purchaseDate
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
            tags: tags,
            photoUrl: photoUrl,
            purchaseDate: purchaseDate,
            sortOrder: sortOrder,
            createdBy: createdBy ?? "",
            needsSync: needsSync
        )
    }

    func update(from item: Item) {
        self.locationId = item.locationId
        self.name = item.name
        self.icon = item.icon
        self.notes = item.notes
        self.quantity = item.quantity
        self.tags = item.tags
        self.photoUrl = item.photoUrl
        self.purchaseDate = item.purchaseDate
        self.sortOrder = item.sortOrder
        self.needsSync = false
        self.updatedAt = Date()
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
