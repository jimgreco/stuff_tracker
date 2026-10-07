import Foundation
import SwiftData

// Versioned lossless recovery archive. Keep raw JSON blobs, dates, tombstones,
// queue failures and relationship identities; API DTOs deliberately omit these.
struct InventoryArchive: Codable, Equatable {
    var version = 1
    var homes: [HomeRecord]
    var locations: [LocationRecord]
    var items: [ItemRecord]
    var operations: [OperationRecord]
    var isEmpty: Bool { homes.isEmpty && locations.isEmpty && items.isEmpty && operations.isEmpty }

    // Recovery into an account already used on this device keeps both sources.
    // Any overlapping identity stops the whole import for explicit review/export.
    func merging(with other: InventoryArchive) throws -> InventoryArchive {
        guard Set(homes.map(\.id)).isDisjoint(with: other.homes.map(\.id)),
              Set(locations.map(\.id)).isDisjoint(with: other.locations.map(\.id)),
              Set(items.map(\.id)).isDisjoint(with: other.items.map(\.id)),
              Set(operations.map(\.id)).isDisjoint(with: other.operations.map(\.id)) else {
            throw CocoaError(.fileWriteFileExists)
        }
        var merged = self
        merged.homes = (homes + other.homes).sorted { $0.id < $1.id }
        merged.locations = (locations + other.locations).sorted { $0.id < $1.id }
        merged.items = (items + other.items).sorted { $0.id < $1.id }
        merged.operations = (operations + other.operations).sorted { $0.id < $1.id }
        return merged
    }

    @MainActor init(context: ModelContext) throws {
        homes = try context.fetch(FetchDescriptor<LocalHome>()).map(HomeRecord.init).sorted { $0.id < $1.id }
        locations = try context.fetch(FetchDescriptor<LocalLocation>()).map(LocationRecord.init).sorted { $0.id < $1.id }
        items = try context.fetch(FetchDescriptor<LocalItem>()).map(ItemRecord.init).sorted { $0.id < $1.id }
        operations = try context.fetch(FetchDescriptor<SyncOperation>()).map(OperationRecord.init).sorted { $0.id < $1.id }
    }

    @MainActor func restore(into context: ModelContext) throws {
        guard version == 1, try InventoryArchive(context: context).isEmpty else {
            throw CocoaError(.fileWriteFileExists)
        }
        var homeModels: [String: LocalHome] = [:]
        for record in homes {
            let model = record.makeModel()
            context.insert(model)
            homeModels[model.id] = model
        }
        for record in locations {
            let model = record.makeModel()
            context.insert(model)
            model.home = record.relationshipHomeID.flatMap { homeModels[$0] }
        }
        for record in items {
            let model = record.makeModel()
            context.insert(model)
            model.home = record.relationshipHomeID.flatMap { homeModels[$0] }
        }
        for record in operations { context.insert(record.makeModel()) }
        try context.save()
        guard try InventoryArchive(context: ModelContext(context.container)) == self else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    struct HomeRecord: Codable, Equatable {
        var clientCreateID: String?
        var id: String
        var name: String
        var ownerId: String?
        var role: String
        var icon: String?
        var isFlagged: Bool
        var sortOrder: Int
        var needsSync: Bool
        var isDeleted: Bool
        var createdAt: Date
        var updatedAt: Date

        @MainActor init(_ model: LocalHome) {
            clientCreateID = model.clientCreateID
            id = model.id
            name = model.name
            ownerId = model.ownerId
            role = model.role
            icon = model.icon
            isFlagged = model.isFlagged
            sortOrder = model.sortOrder
            needsSync = model.needsSync
            isDeleted = model.isDeleted
            createdAt = model.createdAt
            updatedAt = model.updatedAt
        }

        @MainActor func makeModel() -> LocalHome {
            let model = LocalHome(name: name)
            model.id = id
            model.name = name
            model.ownerId = ownerId
            model.role = role
            model.icon = icon
            model.isFlagged = isFlagged
            model.sortOrder = sortOrder
            model.needsSync = needsSync
            model.isDeleted = isDeleted
            model.createdAt = createdAt
            model.updatedAt = updatedAt
            model.clientCreateID = clientCreateID
            return model
        }
    }

    struct LocationRecord: Codable, Equatable {
        var clientCreateID: String?
        var id: String
        var homeId: String
        var parentId: String?
        var name: String
        var type: String
        var sortOrder: Int
        var icon: String?
        var isFlagged: Bool
        var needsSync: Bool
        var isDeleted: Bool
        var createdAt: Date
        var updatedAt: Date
        var relationshipHomeID: String?

        @MainActor init(_ model: LocalLocation) {
            clientCreateID = model.clientCreateID
            id = model.id
            homeId = model.homeId
            parentId = model.parentId
            name = model.name
            type = model.type
            sortOrder = model.sortOrder
            icon = model.icon
            isFlagged = model.isFlagged
            needsSync = model.needsSync
            isDeleted = model.isDeleted
            createdAt = model.createdAt
            updatedAt = model.updatedAt
            relationshipHomeID = model.home?.id
        }

        @MainActor func makeModel() -> LocalLocation {
            let model = LocalLocation(homeId: homeId, name: name, type: type)
            model.id = id
            model.homeId = homeId
            model.parentId = parentId
            model.name = name
            model.type = type
            model.sortOrder = sortOrder
            model.icon = icon
            model.isFlagged = isFlagged
            model.needsSync = needsSync
            model.isDeleted = isDeleted
            model.createdAt = createdAt
            model.updatedAt = updatedAt
            model.clientCreateID = clientCreateID
            return model
        }
    }

    struct ItemRecord: Codable, Equatable {
        var clientCreateID: String?
        var id: String
        var homeId: String
        var locationId: String?
        var name: String
        var icon: String?
        var notes: String?
        var quantity: Int
        var propertiesData: Data?
        var photoUrls: [String]
        var documentsData: Data?
        var purchaseDate: String?
        var serialNumber: String?
        var modelNumber: String?
        var warrantyExpiresDate: String?
        var estimatedValueCents: Int?
        var isFlagged: Bool
        var sortOrder: Int
        var createdBy: String?
        var needsSync: Bool
        var isDeleted: Bool
        var createdAt: Date
        var updatedAt: Date
        var relationshipHomeID: String?

        @MainActor init(_ model: LocalItem) {
            clientCreateID = model.clientCreateID
            id = model.id
            homeId = model.homeId
            locationId = model.locationId
            name = model.name
            icon = model.icon
            notes = model.notes
            quantity = model.quantity
            propertiesData = model.propertiesData
            photoUrls = model.photoUrls
            documentsData = model.documentsData
            purchaseDate = model.purchaseDate
            serialNumber = model.serialNumber
            modelNumber = model.modelNumber
            warrantyExpiresDate = model.warrantyExpiresDate
            estimatedValueCents = model.estimatedValueCents
            isFlagged = model.isFlagged
            sortOrder = model.sortOrder
            createdBy = model.createdBy
            needsSync = model.needsSync
            isDeleted = model.isDeleted
            createdAt = model.createdAt
            updatedAt = model.updatedAt
            relationshipHomeID = model.home?.id
        }

        @MainActor func makeModel() -> LocalItem {
            let model = LocalItem(homeId: homeId, name: name)
            model.id = id
            model.homeId = homeId
            model.locationId = locationId
            model.name = name
            model.icon = icon
            model.notes = notes
            model.quantity = quantity
            model.propertiesData = propertiesData
            model.photoUrls = photoUrls
            model.documentsData = documentsData
            model.purchaseDate = purchaseDate
            model.serialNumber = serialNumber
            model.modelNumber = modelNumber
            model.warrantyExpiresDate = warrantyExpiresDate
            model.estimatedValueCents = estimatedValueCents
            model.isFlagged = isFlagged
            model.sortOrder = sortOrder
            model.createdBy = createdBy
            model.needsSync = needsSync
            model.isDeleted = isDeleted
            model.createdAt = createdAt
            model.updatedAt = updatedAt
            model.clientCreateID = clientCreateID
            return model
        }
    }

    struct OperationRecord: Codable, Equatable {
        var id: String
        var entityType: String
        var entityId: String
        var operation: String
        var payload: Data?
        var createdAt: Date
        var failureCount: Int
        var lastError: String?

        @MainActor init(_ model: SyncOperation) {
            id = model.id
            entityType = model.entityType
            entityId = model.entityId
            operation = model.operation
            payload = model.payload
            createdAt = model.createdAt
            failureCount = model.failureCount
            lastError = model.lastError
        }

        @MainActor func makeModel() -> SyncOperation {
            let model = SyncOperation(entityType: entityType, entityId: entityId, operation: operation)
            model.id = id
            model.entityType = entityType
            model.entityId = entityId
            model.operation = operation
            model.payload = payload
            model.createdAt = createdAt
            model.failureCount = failureCount
            model.lastError = lastError
            return model
        }
    }
}
