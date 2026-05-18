import Foundation
import Security

enum SecureTokenStore {
    private static let service = "com.jimgreco.stufftracker.auth"
    private static let account = "jwt_token"
    private static let legacyDefaultsKey = "jwt_token"

    static var token: String? {
        get {
            var query = baseQuery()
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
        set {
            guard let newValue, !newValue.isEmpty else {
                SecItemDelete(baseQuery() as CFDictionary)
                return
            }

            let data = Data(newValue.utf8)
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]

            let status = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                var query = baseQuery()
                query[kSecValueData as String] = data
                query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                SecItemAdd(query as CFDictionary, nil)
            }
        }
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

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
