import Foundation
import Security

enum SecureTokenStore {
    private static let service = "com.jimgreco.stufftracker.auth"
    private static let accessTokenAccount = "jwt_token"
    private static let refreshTokenAccount = "refresh_token"
    private static let legacyDefaultsKey = "jwt_token"

    static var token: String? {
        get { readToken(account: accessTokenAccount) }
        set { writeToken(newValue, account: accessTokenAccount) }
    }

    static var refreshToken: String? {
        get { readToken(account: refreshTokenAccount) }
        set { writeToken(newValue, account: refreshTokenAccount) }
    }

    static func clearTokens() {
        token = nil
        refreshToken = nil
    }

    static func migrateLegacyTokenIfNeeded() {
        guard token == nil,
              let legacyToken = UserDefaults.standard.string(forKey: legacyDefaultsKey),
              !legacyToken.isEmpty else {
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
            return
        }

        token = legacyToken
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }

    private static func readToken(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }

        return token
    }

    private static func writeToken(_ token: String?, account: String) {
        guard let token, !token.isEmpty else {
            SecItemDelete(baseQuery(account: account) as CFDictionary)
            return
        }

        let data = Data(token.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(baseQuery(account: account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery(account: account)
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
