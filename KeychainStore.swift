import Foundation
import Security

/// Stores and retrieves per-provider API keys from the macOS Keychain.
/// Keys are scoped to the app's bundle identifier so they survive app restarts.
public struct KeychainStore {

    private static let service = Bundle.main.bundleIdentifier ?? "com.subtitle-burner"

    // MARK: - Public API

    public static func save(key: String, for provider: String) {
        let account = accountName(for: provider)
        let data = Data(key.utf8)

        // Try update first
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist yet — add it
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    public static func load(for provider: String) -> String? {
        let account = accountName(for: provider)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8),
              !string.isEmpty else { return nil }
        return string
    }

    public static func delete(for provider: String) {
        let account = accountName(for: provider)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Private

    private static func accountName(for provider: String) -> String {
        "api-key-\(provider.lowercased().replacingOccurrences(of: " ", with: "-"))"
    }
}
