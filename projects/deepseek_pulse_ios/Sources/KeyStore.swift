import Foundation
import Security

/// The API key lives in the iOS Keychain and is never written into app source or logs.
///
/// Writes are non-destructive. The previous implementation called SecItemDelete before SecItemAdd,
/// so a failed add lost the stored key. The adapter now asks KeyStoreMutationRoute how to proceed:
///
///   * SecItemUpdate succeeds            -> value replaced in place
///   * errSecItemNotFound                -> SecItemAdd creates a new item
///   * any other status                  -> failure, existing item untouched
///
/// Service, account and accessibility are unchanged, and the key value is never logged.
enum KeyStore {

    private static let service = "com.waqas.deepseekpulse.apikey"
    private static let account = "deepseek-api-key"

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// The attribute being replaced on an existing item.
    private static func attributes(for data: Data) -> [String: Any] {
        [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
    }

    /// Stores the key without ever destroying a previously stored one on failure.
    /// - Returns: true only when the new value was actually persisted.
    @discardableResult
    static func save(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Saving an empty key means removal, and removal has its own explicit path.
            return delete()
        }
        guard let data = trimmed.data(using: .utf8) else { return false }

        // Probe by attempting the update; the status tells us whether an item exists.
        let query = baseQuery()
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes(for: data) as CFDictionary)
        let route = KeyStoreMutationRoute.route(probeStatus: updateStatus,
                                                itemMissingStatus: errSecItemNotFound)

        switch route {
        case .updateExisting:
            return true
        case .fail:
            // Leave whatever is stored untouched. Nothing is deleted here.
            return false
        case .addNew:
            var addQuery = baseQuery()
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
    }

    static func load() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    /// Removes the key. An already-absent item counts as success, because the requested end state
    /// (no key stored) is true.
    @discardableResult
    static func delete() -> Bool {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
