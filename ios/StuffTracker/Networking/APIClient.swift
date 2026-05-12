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
    private let baseURL = "http://192.168.4.45:3002"
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
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Unknown error"
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
        let (_, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(status) {
            throw APIError.httpError(status, "Request failed")
        }
    }

    // MARK: - Auth

    func signInWithGoogle(idToken: String) async throws -> AuthResponse {
        try await request("POST", path: "/auth/google", body: ["idToken": idToken])
    }

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
    }

    func createLocation(homeId: String, name: String, parentId: String?, type: String, sortOrder: Int = 0) async throws -> Location {
        try await request("POST", path: "/homes/\(homeId)/locations",
                          body: LocationBody(name: name, parentId: parentId, type: type, sortOrder: sortOrder))
    }

    func updateLocation(homeId: String, locationId: String, name: String? = nil, parentId: String? = nil, sortOrder: Int? = nil) async throws -> Location {
        struct Body: Encodable { let name: String?; let parentId: String?; let sortOrder: Int? }
        return try await request("PATCH", path: "/homes/\(homeId)/locations/\(locationId)",
                                 body: Body(name: name, parentId: parentId, sortOrder: sortOrder))
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
