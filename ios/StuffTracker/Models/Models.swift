import Foundation
import SwiftUI

// MARK: - User

struct User: Codable, Identifiable {
    let id: String
    let email: String
    let name: String
    let avatarUrl: String?
}

// MARK: - Account plan

struct AccountPlan: Codable {
    let tier: String
    let isPaid: Bool
    let entitlement: AccountEntitlement?
    let limits: AccountQuotaLimits
    let usage: AccountQuotaUsage
    let remaining: AccountQuotaRemaining
}

struct AccountEntitlement: Codable {
    let source: String
    let productId: String?
    let expiresAt: String?
    let appStoreEnvironment: String?
}

struct AccountQuotaLimits: Codable {
    let totalContainersAndItems: Int
    let images: Int
    let documents: Int
}

struct AccountQuotaUsage: Codable {
    let containers: Int
    let items: Int
    let totalContainersAndItems: Int
    let images: Int
    let documents: Int
}

struct AccountQuotaRemaining: Codable {
    let totalContainersAndItems: Int?
    let images: Int?
    let documents: Int?
}

// MARK: - Home

struct Home: Codable, Identifiable {
    let id: String
    var name: String
    let ownerId: String
    var role: String // "owner" | "admin" | "editor" | "viewer"
    var icon: String?
    var isFlagged: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, ownerId, role, icon, isFlagged
    }

    init(id: String, name: String, ownerId: String, role: String, icon: String? = nil, isFlagged: Bool = false) {
        self.id = id
        self.name = name
        self.ownerId = ownerId
        self.role = role
        self.icon = icon
        self.isFlagged = isFlagged
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        ownerId = try c.decode(String.self, forKey: .ownerId)
        role = try c.decode(String.self, forKey: .role)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        isFlagged = try c.decodeIfPresent(Bool.self, forKey: .isFlagged) ?? false
    }
}

// MARK: - Location (room or container)

struct Location: Codable, Identifiable, Hashable {
    let id: String
    let homeId: String
    var parentId: String?
    var name: String
    var type: LocationType
    var sortOrder: Int
    var icon: String?
    var isFlagged: Bool

    enum LocationType: String, Codable {
        case floor
        case room
        case container
    }

    private enum CodingKeys: String, CodingKey {
        case id, homeId, parentId, name, type, sortOrder, icon, isFlagged
    }

    init(id: String, homeId: String, parentId: String? = nil, name: String, type: LocationType, sortOrder: Int, icon: String? = nil, isFlagged: Bool = false) {
        self.id = id
        self.homeId = homeId
        self.parentId = parentId
        self.name = name
        self.type = type
        self.sortOrder = sortOrder
        self.icon = icon
        self.isFlagged = isFlagged
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        homeId = try c.decode(String.self, forKey: .homeId)
        parentId = try c.decodeIfPresent(String.self, forKey: .parentId)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(LocationType.self, forKey: .type)
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        isFlagged = try c.decodeIfPresent(Bool.self, forKey: .isFlagged) ?? false
    }
}

// MARK: - Item

struct ItemDocument: Codable, Identifiable, Hashable {
    var id: String
    var url: String
    var name: String
    var contentType: String?

    init(id: String = UUID().uuidString, url: String, name: String, contentType: String? = nil) {
        self.id = id
        self.url = url
        self.name = name
        self.contentType = contentType
    }
}

struct ItemProperty: Codable, Identifiable, Hashable {
    var id: String
    var key: String
    var value: String

    init(id: String = UUID().uuidString, key: String = "", value: String = "") {
        self.id = id
        self.key = key
        self.value = value
    }
}

struct Item: Codable, Identifiable {
    let id: String
    let homeId: String
    var locationId: String?
    var name: String
    var icon: String?
    var notes: String?
    var quantity: Int
    var properties: [ItemProperty]
    var photoUrls: [String]
    var documents: [ItemDocument]
    var purchaseDate: String?
    var serialNumber: String?
    var modelNumber: String?
    var warrantyExpiresDate: String?
    var estimatedValueCents: Int?
    var isFlagged: Bool
    var sortOrder: Int
    let createdBy: String
    var needsSync: Bool

    private enum CodingKeys: String, CodingKey {
        case id, homeId, locationId, name, icon, notes, quantity, properties, photoUrls
        case documents, purchaseDate, serialNumber, modelNumber, warrantyExpiresDate
        case estimatedValueCents, isFlagged, sortOrder, createdBy
    }

    init(id: String, homeId: String, locationId: String? = nil, name: String, icon: String? = nil,
         notes: String? = nil, quantity: Int = 1, properties: [ItemProperty] = [], photoUrls: [String] = [],
         documents: [ItemDocument] = [],
         purchaseDate: String? = nil, serialNumber: String? = nil, modelNumber: String? = nil,
         warrantyExpiresDate: String? = nil, estimatedValueCents: Int? = nil,
         isFlagged: Bool = false, sortOrder: Int = 0, createdBy: String = "", needsSync: Bool = false) {
        self.id = id; self.homeId = homeId; self.locationId = locationId; self.name = name
        self.icon = icon; self.notes = notes; self.quantity = quantity; self.properties = properties
        self.photoUrls = photoUrls
        self.documents = documents
        self.purchaseDate = purchaseDate
        self.serialNumber = serialNumber
        self.modelNumber = modelNumber
        self.warrantyExpiresDate = warrantyExpiresDate
        self.estimatedValueCents = estimatedValueCents
        self.isFlagged = isFlagged
        self.sortOrder = sortOrder
        self.createdBy = createdBy; self.needsSync = needsSync
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        homeId = try c.decode(String.self, forKey: .homeId)
        locationId = try c.decodeIfPresent(String.self, forKey: .locationId)
        name = try c.decode(String.self, forKey: .name)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        quantity = try c.decodeIfPresent(Int.self, forKey: .quantity) ?? 1
        properties = try c.decodeIfPresent([ItemProperty].self, forKey: .properties) ?? []
        photoUrls = try c.decodeIfPresent([String].self, forKey: .photoUrls) ?? []
        documents = try c.decodeIfPresent([ItemDocument].self, forKey: .documents) ?? []
        purchaseDate = try c.decodeIfPresent(String.self, forKey: .purchaseDate)
        serialNumber = try c.decodeIfPresent(String.self, forKey: .serialNumber)
        modelNumber = try c.decodeIfPresent(String.self, forKey: .modelNumber)
        warrantyExpiresDate = try c.decodeIfPresent(String.self, forKey: .warrantyExpiresDate)
        estimatedValueCents = try c.decodeIfPresent(Int.self, forKey: .estimatedValueCents)
        isFlagged = try c.decodeIfPresent(Bool.self, forKey: .isFlagged) ?? false
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy) ?? ""
        needsSync = false
    }
}

// MARK: - HomeDetail (full tree response)

struct HomeDetail: Codable {
    let id: String
    var name: String
    let ownerId: String
    let role: String
    var icon: String?
    var isFlagged: Bool
    var locations: [Location]
    var items: [Item]

    private enum CodingKeys: String, CodingKey {
        case id, name, ownerId, role, icon, isFlagged, locations, items
    }

    init(id: String, name: String, ownerId: String, role: String, icon: String? = nil, isFlagged: Bool = false, locations: [Location], items: [Item]) {
        self.id = id
        self.name = name
        self.ownerId = ownerId
        self.role = role
        self.icon = icon
        self.isFlagged = isFlagged
        self.locations = locations
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        ownerId = try c.decode(String.self, forKey: .ownerId)
        role = try c.decode(String.self, forKey: .role)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        isFlagged = try c.decodeIfPresent(Bool.self, forKey: .isFlagged) ?? false
        locations = try c.decodeIfPresent([Location].self, forKey: .locations) ?? []
        items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
    }
}

// MARK: - Member

struct Member: Codable, Identifiable {
    let id: String
    let email: String
    let name: String
    let avatarUrl: String?
    var role: String
}

// MARK: - Convenience tree helpers

extension HomeDetail {
    /// Top-level locations (floors and rooms with no parent)
    var topLevelLocations: [Location] {
        locations.filter { $0.parentId == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func children(of locationId: String) -> [Location] {
        locations.filter { $0.parentId == locationId }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func items(in locationId: String?) -> [Item] {
        items.filter { $0.locationId == locationId }.sorted { $0.sortOrder < $1.sortOrder }
    }
}
