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

// One scope covers a complete sync, including retries and refresh. New sign-in
// and sign-out invalidate old scopes; refreshing the same session does not.
private enum APIRequestScope {
    @TaskLocal static var generation: UUID?
}

final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let sessionLock = NSRecursiveLock()
    private var generation = UUID()
    private var verifiedUserID: String?

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
        SecureTokenStore.migrateLegacyTokenIfNeeded()
    }

    var sessionGeneration: UUID { sessionLock.withLock { generation } }
    var localAccountID: String? { sessionLock.withLock { verifiedUserID } }

    func verifyLocalAccount(_ userID: String, generation expected: UUID) throws {
        try sessionLock.withLock {
            guard generation == expected else { throw CancellationError() }
            verifiedUserID = userID
        }
    }

    func withSessionScope<T>(_ operation: () async throws -> T) async rethrows -> T {
        try await APIRequestScope.$generation.withValue(APIRequestScope.generation ?? sessionGeneration) {
            try await operation()
        }
    }

    func requireCurrentSession(_ expected: UUID? = nil) throws {
        try sessionLock.withLock {
            guard generation == (expected ?? APIRequestScope.generation ?? generation), !Task.isCancelled else {
                throw CancellationError()
            }
        }
    }

    #if DEBUG
    private let baseURL = APIClient.debugBaseURL()
    #else
    private let baseURL = "https://cubbylog.com"
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
        sessionLock.withLock {
            SecureTokenStore.migrateLegacyTokenIfNeeded()
            return token != nil || refreshToken != nil
        }
    }
    
    func setToken(_ t: String?) { setAuthTokens(token: t, refreshToken: nil) }
    func setAuthTokens(token: String?, refreshToken: String?) {
        sessionLock.withLock {
            generation = UUID()
            verifiedUserID = nil
            self.token = token
            self.refreshToken = refreshToken
        }
    }

    func beginAccountTransition() {
        sessionLock.withLock {
            generation = UUID()
            verifiedUserID = nil
        }
    }

    func clearAuthTokens() {
        sessionLock.withLock {
            generation = UUID()
            verifiedUserID = nil
            SecureTokenStore.clearTokens()
        }
    }

    #if DEBUG
    private static func debugBaseURL() -> String {
        let rawOverride = ProcessInfo.processInfo.environment["CUBBYLOG_API_BASE_URL"]
            ?? ProcessInfo.processInfo.environment["STUFF_TRACKER_API_BASE_URL"]
        if let rawOverride {
            let override = rawOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            if !override.isEmpty {
                return override
            }
        }

        #if targetEnvironment(simulator)
        return "http://localhost:3002"
        #else
        return "https://cubbylog.com"
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

    struct MutationMetadata {
        let id: String
        let occurredAt: Date

        static func automatic() -> MutationMetadata {
            MutationMetadata(id: UUID().uuidString, occurredAt: Date())
        }
    }

    func request<T: Decodable>(
        _ method: String,
        path: String,
        body: (some Encodable)? = nil as String?,
        keyEncodingStrategy: JSONEncoder.KeyEncodingStrategy = .convertToSnakeCase,
        mutationMetadata: MutationMetadata? = nil
    ) async throws -> T {
        return try await withSessionScope {
            let bodyData = try body.map { try encodeBody($0, keyEncodingStrategy: keyEncodingStrategy) }
            let metadata = method == "GET" ? nil : mutationMetadata ?? .automatic()
            let data = try await performRequest(
                method,
                path: path,
                bodyData: bodyData,
                allowRefresh: true,
                errorFallback: "Unknown error",
                mutationMetadata: metadata
            )

            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        }
    }

    func requestEmpty(
        _ method: String,
        path: String,
        body: (some Encodable)? = nil as String?,
        keyEncodingStrategy: JSONEncoder.KeyEncodingStrategy = .convertToSnakeCase,
        mutationMetadata: MutationMetadata? = nil
    ) async throws {
        return try await withSessionScope {
            let bodyData = try body.map { try encodeBody($0, keyEncodingStrategy: keyEncodingStrategy) }
            let metadata = method == "GET" ? nil : mutationMetadata ?? .automatic()
            _ = try await performRequest(
                method,
                path: path,
                bodyData: bodyData,
                allowRefresh: true,
                errorFallback: "Request failed",
                mutationMetadata: metadata
            )
        }
    }

    private func performRequest(
        _ method: String,
        path: String,
        bodyData: Data?,
        allowRefresh: Bool,
        errorFallback: String,
        mutationMetadata: MutationMetadata?
    ) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try sessionLock.withLock {
            try requireCurrentSession()
            if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        }
        if let mutationMetadata {
            req.setValue(mutationMetadata.id, forHTTPHeaderField: "X-CubbyLog-Mutation-ID")
            req.setValue(ISO8601DateFormatter().string(from: mutationMetadata.occurredAt), forHTTPHeaderField: "X-CubbyLog-Occurred-At")
        }
        req.httpBody = bodyData

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            try requireCurrentSession()
            throw APIError.networkError(error)
        }
        try requireCurrentSession()

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, allowRefresh, path != "/auth/refresh", await refreshAccessTokenIfPossible() {
            return try await performRequest(
                method,
                path: path,
                bodyData: bodyData,
                allowRefresh: false,
                errorFallback: errorFallback,
                mutationMetadata: mutationMetadata
            )
        }

        try requireCurrentSession()
        guard (200..<300).contains(status) else {
            let msg = Self.errorMessage(from: data, fallback: errorFallback)
            throw APIError.httpError(status, msg)
        }

        return data
    }

    private func refreshAccessTokenIfPossible() async -> Bool {
        let currentRefreshToken: String? = sessionLock.withLock {
            guard (try? requireCurrentSession()) != nil else { return nil }
            return refreshToken
        }
        guard let refreshToken = currentRefreshToken else { return false }

        do {
            let response = try await refreshSession(refreshToken: refreshToken)
            try sessionLock.withLock {
                try requireCurrentSession()
                self.token = response.token
                self.refreshToken = response.refreshToken
            }
            return true
        } catch {
            sessionLock.withLock {
                // An old refresh must never clear a newer account's credentials.
                if (try? requireCurrentSession()) != nil,
                   case APIError.httpError(401, _) = error {
                    clearAuthTokens()
                }
            }
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
            (data, response) = try await session.data(for: req)
        } catch {
            try requireCurrentSession()
            throw APIError.networkError(error)
        }
        try requireCurrentSession()

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        try requireCurrentSession()
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

    func deleteAccount() async throws {
        try await requestEmpty("DELETE", path: "/account", body: DeleteAccountConfirmation())
    }

    private struct DeleteAccountConfirmation: Encodable {
        let confirmation = "DELETE"
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

    func createHome(name: String, icon: String? = nil, isFlagged: Bool? = nil, mutationMetadata: MutationMetadata? = nil) async throws -> Home {
        try await request("POST", path: "/homes", body: UpdateHomeBody(name: name, icon: icon, isFlagged: isFlagged), mutationMetadata: mutationMetadata)
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

    func updateHome(_ id: String, name: String, icon: String? = nil, isFlagged: Bool? = nil, mutationMetadata: MutationMetadata? = nil) async throws -> Home {
        try await request("PATCH", path: "/homes/\(id)", body: UpdateHomeBody(name: name, icon: icon, isFlagged: isFlagged), mutationMetadata: mutationMetadata)
    }

    func deleteHome(_ id: String, mutationMetadata: MutationMetadata? = nil) async throws {
        try await requestEmpty("DELETE", path: "/homes/\(id)", mutationMetadata: mutationMetadata)
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

    func createLocation(homeId: String, name: String, parentId: String?, type: String, sortOrder: Int = 0, icon: String? = nil, isFlagged: Bool? = nil, mutationMetadata: MutationMetadata? = nil) async throws -> Location {
        try await request("POST", path: "/homes/\(homeId)/locations",
                          body: LocationBody(name: name, parentId: parentId, type: type, sortOrder: sortOrder, icon: icon, isFlagged: isFlagged), mutationMetadata: mutationMetadata)
    }

    struct UpdateLocationBody: Encodable {
        let homeId: String?
        let name: String?
        let parentId: String?
        let sortOrder: Int?
        let icon: String?
        let isFlagged: Bool?

        init(homeId: String?, name: String?, parentId: String?, sortOrder: Int?, icon: String?, isFlagged: Bool? = nil) {
            self.homeId = homeId
            self.name = name
            self.parentId = parentId
            self.sortOrder = sortOrder
            self.icon = icon
            self.isFlagged = isFlagged
        }

        enum CodingKeys: String, CodingKey {
            case homeId, name, parentId, sortOrder, icon, isFlagged
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(homeId, forKey: .homeId)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encode(parentId, forKey: .parentId)
            try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
            try container.encode(icon, forKey: .icon)
            try container.encodeIfPresent(isFlagged, forKey: .isFlagged)
        }
    }

    func updateLocation(homeId: String, locationId: String, newHomeId: String? = nil, name: String? = nil, parentId: String? = nil, sortOrder: Int? = nil, icon: String? = nil, isFlagged: Bool? = nil, mutationMetadata: MutationMetadata? = nil) async throws -> Location {
        return try await request("PATCH", path: "/homes/\(homeId)/locations/\(locationId)",
                                 body: UpdateLocationBody(homeId: newHomeId, name: name, parentId: parentId, sortOrder: sortOrder, icon: icon, isFlagged: isFlagged), mutationMetadata: mutationMetadata)
    }

    func deleteLocation(homeId: String, locationId: String, mutationMetadata: MutationMetadata? = nil) async throws {
        try await requestEmpty("DELETE", path: "/homes/\(homeId)/locations/\(locationId)", mutationMetadata: mutationMetadata)
    }

    // MARK: - Items

    struct ItemBody: Encodable {
        let name: String
        let homeId: String?
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
        let sortOrder: Int?

        enum CodingKeys: String, CodingKey {
            case name, homeId, locationId, icon, notes, quantity, properties, photoUrls
            case documents, purchaseDate, serialNumber, modelNumber, warrantyExpiresDate
            case estimatedValueCents, isFlagged, sortOrder
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(homeId, forKey: .homeId)
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
            try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
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

    func createItem(homeId: String, body: ItemBody, mutationMetadata: MutationMetadata? = nil) async throws -> Item {
        try await request("POST", path: "/homes/\(homeId)/items", body: body, mutationMetadata: mutationMetadata)
    }

    func updateItem(homeId: String, itemId: String, body: ItemBody, mutationMetadata: MutationMetadata? = nil) async throws -> Item {
        try await request("PATCH", path: "/homes/\(homeId)/items/\(itemId)", body: body, mutationMetadata: mutationMetadata)
    }

    func deleteItem(homeId: String, itemId: String, mutationMetadata: MutationMetadata? = nil) async throws {
        try await requestEmpty("DELETE", path: "/homes/\(homeId)/items/\(itemId)", mutationMetadata: mutationMetadata)
    }

    func activity(homeId: String, itemId: String? = nil, cursor: String? = nil, actorId: String? = nil, action: String? = nil, entityType: String? = nil, from: Date? = nil) async throws -> ActivityPage {
        var components = URLComponents()
        components.path = "/homes/\(homeId)/activity"
        components.queryItems = [
            itemId.map { URLQueryItem(name: "entity_id", value: $0) },
            cursor.map { URLQueryItem(name: "cursor", value: $0) },
            actorId.map { URLQueryItem(name: "actor_id", value: $0) },
            action.map { URLQueryItem(name: "action", value: $0) },
            entityType.map { URLQueryItem(name: "entity_type", value: $0) },
            from.map { URLQueryItem(name: "from", value: ISO8601DateFormatter().string(from: $0)) },
        ].compactMap { $0 }
        return try await request("GET", path: components.string ?? components.path)
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
        return try await withSessionScope {
            let upload: ItemUploadResponse = try await request(
                "POST",
                path: "/homes/\(homeId)/items/uploads",
                body: ItemUploadBody(kind: kind, fileName: fileName, contentType: contentType, sizeBytes: data.count),
                keyEncodingStrategy: .useDefaultKeys
            )

            try requireCurrentSession()
            guard let url = URL(string: upload.uploadUrl) else { throw APIError.invalidURL }
            var req = URLRequest(url: url)
            req.httpMethod = "PUT"
            for (header, value) in upload.headers {
                req.setValue(value, forHTTPHeaderField: header)
            }

            let (responseData, response): (Data, URLResponse)
            do {
                (responseData, response) = try await session.upload(for: req, from: data)
            } catch {
                try requireCurrentSession()
                throw APIError.networkError(error)
            }
            try requireCurrentSession()

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let msg = Self.errorMessage(from: responseData, fallback: "Upload failed")
                throw APIError.httpError(status, msg)
            }

            return upload
        }
    }

}

struct AuthResponse: Codable {
    let token: String
    let refreshToken: String?
    let user: User
}
