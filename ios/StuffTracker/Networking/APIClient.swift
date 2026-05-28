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

    private init() {
        SecureTokenStore.migrateLegacyTokenIfNeeded()
    }

    #if DEBUG
    private let baseURL = APIClient.debugBaseURL()
    #else
    private let baseURL = "https://stuff-tracker.jim-greco.com"
    #endif

    private var token: String? {
        get { SecureTokenStore.token }
        set { SecureTokenStore.token = newValue }
    }

    private var refreshToken: String? {
        get { SecureTokenStore.refreshToken }
        set { SecureTokenStore.refreshToken = newValue }
    }

    var hasToken: Bool {
        SecureTokenStore.migrateLegacyTokenIfNeeded()
        return token != nil || refreshToken != nil
    }
    
    func setToken(_ t: String?) { token = t }
    func setAuthTokens(token: String?, refreshToken: String?) {
        self.token = token
        self.refreshToken = refreshToken
    }

    func clearAuthTokens() {
        SecureTokenStore.clearTokens()
    }

    #if DEBUG
    private static func debugBaseURL() -> String {
        if let rawOverride = ProcessInfo.processInfo.environment["STUFF_TRACKER_API_BASE_URL"] {
            let override = rawOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            if !override.isEmpty {
                return override
            }
        }

        #if targetEnvironment(simulator)
        return "http://localhost:3002"
        #else
        return "https://stuff-tracker.jim-greco.com"
        #endif
    }
    #endif

    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private func encodeBody<T: Encodable>(
        _ body: T,
        keyEncodingStrategy: JSONEncoder.KeyEncodingStrategy
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = keyEncodingStrategy
        return try encoder.encode(body)
    }

    private struct ErrorResponse: Decodable {
        let error: String?
        let message: String?
        let details: [ValidationDetail]?

        var displayMessage: String? {
            let base = error ?? message
            guard let detail = details?.first, !detail.message.isEmpty else {
                return base
            }

            let detailMessage = detail.pathDescription.isEmpty
                ? detail.message
                : "\(detail.pathDescription): \(detail.message)"

            guard let base, !base.isEmpty else {
                return detailMessage
            }
            return "\(base): \(detailMessage)"
        }
    }

    private struct ValidationDetail: Decodable {
        let message: String
        let path: [ValidationPathComponent]

        var pathDescription: String {
            path.map(\.description).joined(separator: ".")
        }
    }

    private enum ValidationPathComponent: Decodable, CustomStringConvertible {
        case string(String)
        case int(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .string(string)
            } else {
                self = .int(try container.decode(Int.self))
            }
        }

        var description: String {
            switch self {
            case .string(let value): return value
            case .int(let value): return String(value)
            }
        }
    }

    static func errorMessage(from data: Data, fallback: String = "Unknown error") -> String {
        if let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           let message = decoded.displayMessage,
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
        body: (some Encodable)? = nil as String?,
        keyEncodingStrategy: JSONEncoder.KeyEncodingStrategy = .convertToSnakeCase
    ) async throws -> T {
        let bodyData = try body.map { try encodeBody($0, keyEncodingStrategy: keyEncodingStrategy) }
        let data = try await performRequest(
            method,
            path: path,
            bodyData: bodyData,
            allowRefresh: true,
            errorFallback: "Unknown error"
        )

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func requestEmpty(
        _ method: String,
        path: String,
        body: (some Encodable)? = nil as String?,
        keyEncodingStrategy: JSONEncoder.KeyEncodingStrategy = .convertToSnakeCase
    ) async throws {
        let bodyData = try body.map { try encodeBody($0, keyEncodingStrategy: keyEncodingStrategy) }
        _ = try await performRequest(
            method,
            path: path,
            bodyData: bodyData,
            allowRefresh: true,
            errorFallback: "Request failed"
        )
    }

    private func performRequest(
        _ method: String,
        path: String,
        bodyData: Data?,
        allowRefresh: Bool,
        errorFallback: String
    ) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        req.httpBody = bodyData

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.networkError(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, allowRefresh, path != "/auth/refresh", await refreshAccessTokenIfPossible() {
            return try await performRequest(
                method,
                path: path,
                bodyData: bodyData,
                allowRefresh: false,
                errorFallback: errorFallback
            )
        }

        guard (200..<300).contains(status) else {
            let msg = Self.errorMessage(from: data, fallback: errorFallback)
            throw APIError.httpError(status, msg)
        }

        return data
    }

    private func refreshAccessTokenIfPossible() async -> Bool {
        guard let refreshToken else {
            return false
        }

        do {
            let response = try await refreshSession(refreshToken: refreshToken)
            setAuthTokens(token: response.token, refreshToken: response.refreshToken)
            return true
        } catch {
            clearAuthTokens()
            return false
        }
    }

    // MARK: - Auth

    struct GoogleSignInBody: Encodable {
        let idToken: String
    }

    struct RefreshBody: Encodable {
        let refreshToken: String
    }

    struct AppleSignInBody: Encodable {
        let identityToken: String
        let fullName: FullName?

        struct FullName: Encodable {
            let givenName: String?
            let familyName: String?
        }

        init(identityToken: String, fullName: PersonNameComponents?) {
            self.identityToken = identityToken
            self.fullName = fullName.map {
                FullName(givenName: $0.givenName, familyName: $0.familyName)
            }
        }
    }

    func signInWithGoogle(idToken: String) async throws -> AuthResponse {
        try await request(
            "POST",
            path: "/auth/google",
            body: GoogleSignInBody(idToken: idToken),
            keyEncodingStrategy: .useDefaultKeys
        )
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
        let body = AppleSignInBody(identityToken: identityToken, fullName: fullName)
        return try await request(
            "POST",
            path: "/auth/apple",
            body: body,
            keyEncodingStrategy: .useDefaultKeys
        )
    }

    private func refreshSession(refreshToken: String) async throws -> AuthResponse {
        guard let url = URL(string: baseURL + "/auth/refresh") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encodeBody(RefreshBody(refreshToken: refreshToken), keyEncodingStrategy: .useDefaultKeys)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.networkError(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let msg = Self.errorMessage(from: data, fallback: "Session refresh failed")
            throw APIError.httpError(status, msg)
        }

        do {
            return try decoder.decode(AuthResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func logoutAll() async throws {
        try await requestEmpty("POST", path: "/auth/logout-all")
    }

    // MARK: - Account plan

    struct SubscriptionProductsResponse: Decodable {
        let productIds: [String]
    }

    struct AppStoreTransactionBody: Encodable {
        let signedTransactionInfo: String
    }

    struct AppStoreTransactionSyncResponse: Decodable {
        struct Result: Decodable {
            let applied: Bool
            let status: String?
            let productId: String?
            let expiresAt: String?
        }

        let result: Result
        let plan: AccountPlan
    }

    func getAccountPlan() async throws -> AccountPlan {
        try await request("GET", path: "/account/plan")
    }

    func getSubscriptionProductIds() async throws -> [String] {
        let response: SubscriptionProductsResponse = try await request("GET", path: "/account/subscription-products")
        return response.productIds
    }

    func syncAppStoreTransaction(signedTransactionInfo: String) async throws -> AccountPlan {
        let response: AppStoreTransactionSyncResponse = try await request(
            "POST",
            path: "/account/app-store/transactions",
            body: AppStoreTransactionBody(signedTransactionInfo: signedTransactionInfo),
            keyEncodingStrategy: .useDefaultKeys
        )
        return response.plan
    }

    // MARK: - Homes

    func listHomes() async throws -> [Home] {
        try await request("GET", path: "/homes")
    }

    func createHome(name: String, icon: String? = nil, isFlagged: Bool? = nil) async throws -> Home {
        try await request("POST", path: "/homes", body: UpdateHomeBody(name: name, icon: icon, isFlagged: isFlagged))
    }

    func getHome(_ id: String) async throws -> HomeDetail {
        try await request("GET", path: "/homes/\(id)")
    }

    struct UpdateHomeBody: Encodable {
        let name: String
        let icon: String?
        let isFlagged: Bool?

        init(name: String, icon: String?, isFlagged: Bool? = nil) {
            self.name = name
            self.icon = icon
            self.isFlagged = isFlagged
        }

        enum CodingKeys: String, CodingKey {
            case name, icon, isFlagged
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(icon, forKey: .icon)
            try container.encodeIfPresent(isFlagged, forKey: .isFlagged)
        }
    }

    func updateHome(_ id: String, name: String, icon: String? = nil, isFlagged: Bool? = nil) async throws -> Home {
        try await request("PATCH", path: "/homes/\(id)", body: UpdateHomeBody(name: name, icon: icon, isFlagged: isFlagged))
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
        let icon: String?
        let isFlagged: Bool?

        init(name: String, parentId: String?, type: String, sortOrder: Int?, icon: String?, isFlagged: Bool? = nil) {
            self.name = name
            self.parentId = parentId
            self.type = type
            self.sortOrder = sortOrder
            self.icon = icon
            self.isFlagged = isFlagged
        }

        enum CodingKeys: String, CodingKey {
            case name, parentId, type, sortOrder, icon, isFlagged
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(parentId, forKey: .parentId)
            try container.encode(type, forKey: .type)
            try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
            try container.encode(icon, forKey: .icon)
            try container.encodeIfPresent(isFlagged, forKey: .isFlagged)
        }
    }

    func createLocation(homeId: String, name: String, parentId: String?, type: String, sortOrder: Int = 0, icon: String? = nil, isFlagged: Bool? = nil) async throws -> Location {
        try await request("POST", path: "/homes/\(homeId)/locations",
                          body: LocationBody(name: name, parentId: parentId, type: type, sortOrder: sortOrder, icon: icon, isFlagged: isFlagged))
    }

    struct UpdateLocationBody: Encodable {
        let name: String?
        let parentId: String?
        let sortOrder: Int?
        let icon: String?
        let isFlagged: Bool?

        init(name: String?, parentId: String?, sortOrder: Int?, icon: String?, isFlagged: Bool? = nil) {
            self.name = name
            self.parentId = parentId
            self.sortOrder = sortOrder
            self.icon = icon
            self.isFlagged = isFlagged
        }

        enum CodingKeys: String, CodingKey {
            case name, parentId, sortOrder, icon, isFlagged
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encode(parentId, forKey: .parentId)
            try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
            try container.encode(icon, forKey: .icon)
            try container.encodeIfPresent(isFlagged, forKey: .isFlagged)
        }
    }

    func updateLocation(homeId: String, locationId: String, name: String? = nil, parentId: String? = nil, sortOrder: Int? = nil, icon: String? = nil, isFlagged: Bool? = nil) async throws -> Location {
        return try await request("PATCH", path: "/homes/\(homeId)/locations/\(locationId)",
                                 body: UpdateLocationBody(name: name, parentId: parentId, sortOrder: sortOrder, icon: icon, isFlagged: isFlagged))
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
        let properties: [ItemProperty]?
        let photoUrls: [String]?
        let documents: [ItemDocument]?
        let purchaseDate: String?
        let serialNumber: String?
        let modelNumber: String?
        let warrantyExpiresDate: String?
        let estimatedValueCents: Int?
        let isFlagged: Bool?

        enum CodingKeys: String, CodingKey {
            case name, locationId, icon, notes, quantity, properties, photoUrls
            case documents, purchaseDate, serialNumber, modelNumber, warrantyExpiresDate
            case estimatedValueCents, isFlagged
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(locationId, forKey: .locationId)
            try container.encodeIfPresent(icon, forKey: .icon)
            try container.encode(notes, forKey: .notes)
            try container.encodeIfPresent(quantity, forKey: .quantity)
            try container.encodeIfPresent(properties, forKey: .properties)
            try container.encodeIfPresent(photoUrls, forKey: .photoUrls)
            try container.encodeIfPresent(documents, forKey: .documents)
            try container.encodeIfPresent(purchaseDate, forKey: .purchaseDate)
            try container.encodeIfPresent(serialNumber, forKey: .serialNumber)
            try container.encodeIfPresent(modelNumber, forKey: .modelNumber)
            try container.encodeIfPresent(warrantyExpiresDate, forKey: .warrantyExpiresDate)
            try container.encodeIfPresent(estimatedValueCents, forKey: .estimatedValueCents)
            try container.encodeIfPresent(isFlagged, forKey: .isFlagged)
        }
    }

    enum ItemAttachmentKind: String, Encodable {
        case photo
        case document
    }

    struct ItemUploadResponse: Decodable {
        let uploadUrl: String
        let fileUrl: String
        let key: String
        let headers: [String: String]
    }

    struct ItemUploadBody: Encodable {
        let kind: ItemAttachmentKind
        let fileName: String
        let contentType: String
        let sizeBytes: Int

        enum CodingKeys: String, CodingKey {
            case kind
            case fileName = "file_name"
            case contentType = "content_type"
            case sizeBytes = "size_bytes"
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

    func uploadItemAttachment(
        homeId: String,
        kind: ItemAttachmentKind,
        fileName: String,
        contentType: String,
        data: Data
    ) async throws -> ItemUploadResponse {
        let upload: ItemUploadResponse = try await request(
            "POST",
            path: "/homes/\(homeId)/items/uploads",
            body: ItemUploadBody(kind: kind, fileName: fileName, contentType: contentType, sizeBytes: data.count),
            keyEncodingStrategy: .useDefaultKeys
        )

        guard let url = URL(string: upload.uploadUrl) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        for (header, value) in upload.headers {
            req.setValue(value, forHTTPHeaderField: header)
        }

        let (responseData, response): (Data, URLResponse)
        do {
            (responseData, response) = try await URLSession.shared.upload(for: req, from: data)
        } catch {
            throw APIError.networkError(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let msg = Self.errorMessage(from: responseData, fallback: "Upload failed")
            throw APIError.httpError(status, msg)
        }

        return upload
    }
}

struct AuthResponse: Codable {
    let token: String
    let refreshToken: String?
    let user: User
}
