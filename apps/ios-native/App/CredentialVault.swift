import Foundation
import Security

enum CredentialVault {
    private static let service = "com.ahrsn.t3native.server-tokens"
    private static func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }
    static func save(_ token: String, for id: UUID) throws {
        var item = query(id)
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
                                       kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(item as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            item.merge(attributes) { _, new in new }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw ClientError("Could not save the server credential in Keychain.") }
        } else if status != errSecSuccess { throw ClientError("Could not update the server credential in Keychain.") }
    }
    static func token(for id: UUID) throws -> String {
        var item = query(id); item[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw ClientError("This server has no saved credential. Pair it again.")
        }
        return token
    }
    static func remove(_ id: UUID) { SecItemDelete(query(id) as CFDictionary) }
}
