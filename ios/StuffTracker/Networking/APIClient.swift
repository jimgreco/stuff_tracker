import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case httpError(Int, String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .decodingError(let e): return "Decode error: \(e.localizedDescription)"
        case .networkError(let e): return e.localizedDescription
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    #if DEBUG
    #if targetEnvironment(simulator)
    private let baseURL = "http://localhost:3002"
    #else
    private let baseURL = "http://192.168.4.45:3002"
    #endif
    #else
    private let baseURL = "https://stuff-tracker.jim-greco.com"
    #endif

    private var token: String? {
        get { UserDefaults.standard.string(forKey: "jwt_token") }
        set { UserDefaults.standard.set(newValue, forKey: "jwt_token") }
    }

    var hasToken: Bool { token != nil }
    
    func setToken(_ t: String?) { token = t }

    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private lazy var encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    private struct ErrorResponse: Decodable {
        let error: String?
        let message: String?
    }

    static func errorMessage(from data: Data, fallback: String = "Unknown error") -> String {
        if let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           let message = decoded.error ?? decoded.message,
           !message.isEmpty {
            return message
        }

        if let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return fallback
    }

    // MARK: - Core request

    func request<T: Decodable>(
        _ method: String,
        path: String,
        body: (some Encodable)? = nil as String?
    ) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.httpBody = try encoder.encode(body)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.networkError(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let msg = Self.errorMessage(from: data)
            throw APIError.httpError(status, msg)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func requestEmpty(_ method: String, path: String, body: (some Encodable)? = nil as String?) async throws {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try encoder.encode(body) }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.networkError(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(status) {
            let msg = Self.errorMessage(from: data, fallback: "Request failed")
            throw APIError.httpError(status, msg)
        }
    }

    // MARK: - Auth

    func signInWithGoogle(idToken: String) async throws -> AuthResponse {
        try await request("POST", path: "/auth/google", body: ["idToken": idToken])
    }

    #if DEBUG
    func signInForLocalDevelopment(
        email: String = "dev@stufftracker.local",
        name: String = "Local Dev"
    ) async throws -> AuthResponse {
        struct Body: Encodable {
            let email: String
            let name: String
        }

        return try await request("POST", path: "/auth/dev", body: Body(email: email, name: name))
    }
    #endif

    func signInWithApple(identityToken: String, fullName: PersonNameComponents?) async throws -> AuthResponse {
        struct Body: Encodable {
            let identityToken: String
            let fullName: FullName?
            struct FullName: Encodable {
                let givenName: String?
                let familyName: String?
            }
        }
        let body = Body(
            identityToken: identityToken,
            fullName: fullName.map { Body.FullName(givenName: $0.givenName, familyName: $0.familyName) }
        )
        return try await request("POST", path: "/auth/apple", body: body)
    }

    // MARK: - Homes

    func listHomes() async throws -> [Home] {
        try await request("GET", path: "/homes")
    }

    func createHome(name: String) async throws -> Home {
        try await request("POST", path: "/homes", body: ["name": name])
    }

    func getHome(_ id: String) async throws -> HomeDetail {
        try await request("GET", path: "/homes/\(id)")
    }

    func updateHome(_ id: String, name: String) async throws -> Home {
        try await request("PATCH", path: "/homes/\(id)", body: ["name": name])
    }

    func deleteHome(_ id: String) async throws {
        try await requestEmpty("DELETE", path: "/homes/\(id)")
    }

    // MARK: - Members

    func listMembers(homeId: String) async throws -> [Member] {
        try await request("GET", path: "/homes/\(homeId)/members")
    }

    func inviteMember(homeId: String, email: String, role: String) async throws {
        struct Body: Encodable { let email: String; let role: String }
        try await requestEmpty("POST", path: "/homes/\(homeId)/members", body: Body(email: email, role: role))
    }

    func updateMember(homeId: String, userId: String, role: String) async throws {
        try await requestEmpty("PATCH", path: "/homes/\(homeId)/members/\(userId)", body: ["role": role])
    }

    func removeMember(homeId: String, userId: String) async throws {
        try await requestEmpty("DELETE", path: "/homes/\(homeId)/members/\(userId)")
    }

    // MARK: - Locations

    struct LocationBody: Encodable {
        let name: String
        let parentId: String?
        let type: String
        let sortOrder: Int?

        enum CodingKeys: String, CodingKey {
            case name, parentId, type, sortOrder
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(parentId, forKey: .parentId)
            try container.encode(type, forKey: .type)
            try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
        }
    }

    func createLocation(homeId: String, name: String, parentId: String?, type: String, sortOrder: Int = 0) async throws -> Location {
        try await request("POST", path: "/homes/\(homeId)/locations",
                          body: LocationBody(name: name, parentId: parentId, type: type, sortOrder: sortOrder))
    }

    struct UpdateLocationBody: Encodable {
        let name: String?
        let parentId: String?
        let sortOrder: Int?

        enum CodingKeys: String, CodingKey {
            case name, parentId, sortOrder
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encode(parentId, forKey: .parentId)
            try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
        }
    }

    func updateLocation(homeId: String, locationId: String, name: String? = nil, parentId: String? = nil, sortOrder: Int? = nil) async throws -> Location {
        return try await request("PATCH", path: "/homes/\(homeId)/locations/\(locationId)",
                                 body: UpdateLocationBody(name: name, parentId: parentId, sortOrder: sortOrder))
    }

    func deleteLocation(homeId: String, locationId: String) async throws {
        try await requestEmpty("DELETE", path: "/homes/\(homeId)/locations/\(locationId)")
    }

    // MARK: - Items

    struct ItemBody: Encodable {
        let name: String
        let locationId: String?
        let icon: String?
        let notes: String?
        let quantity: Int?
        let tags: [String]?
        let photoUrl: String?
        let purchaseDate: String?

        enum CodingKeys: String, CodingKey {
            case name, locationId, icon, notes, quantity, tags, photoUrl, purchaseDate
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(locationId, forKey: .locationId)
            try container.encodeIfPresent(icon, forKey: .icon)
            try container.encode(notes, forKey: .notes)
            try container.encodeIfPresent(quantity, forKey: .quantity)
            try container.encodeIfPresent(tags, forKey: .tags)
            try container.encode(photoUrl, forKey: .photoUrl)
            try container.encodeIfPresent(purchaseDate, forKey: .purchaseDate)
        }
    }

    func createItem(homeId: String, body: ItemBody) async throws -> Item {
        try await request("POST", path: "/homes/\(homeId)/items", body: body)
    }

    func updateItem(homeId: String, itemId: String, body: ItemBody) async throws -> Item {
        try await request("PATCH", path: "/homes/\(homeId)/items/\(itemId)", body: body)
    }

    func deleteItem(homeId: String, itemId: String) async throws {
        try await requestEmpty("DELETE", path: "/homes/\(homeId)/items/\(itemId)")
    }

    func searchItems(homeId: String, query: String) async throws -> [Item] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try await request("GET", path: "/homes/\(homeId)/items/search?q=\(encoded)")
    }
}

struct AuthResponse: Codable {
    let token: String
    let user: User
}
