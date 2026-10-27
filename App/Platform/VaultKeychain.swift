import Foundation
import LocalAuthentication
import Security

/// Stores encrypted-vault passwords as generic passwords gated by `.userPresence`
/// (Touch ID or the login password) on read. Account = destination path.
enum VaultKeychain {
    static let service = "com.prabhatkumar.Cleaner.vault"

    enum Failure: Error, LocalizedError {
        case status(OSStatus)
        var errorDescription: String? {
            guard case .status(let status) = self else { return nil }
            return (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecUseDataProtectionKeychain as String: true]
    }

    static func save(password: String, account: String) throws {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, &error)
        else { throw error?.takeRetainedValue() ?? Failure.status(errSecParam) }
        SecItemDelete(baseQuery(account: account) as CFDictionary)
        var query = baseQuery(account: account)
        query[kSecAttrAccessControl as String] = access
        query[kSecValueData as String] = Data(password.utf8)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.status(status) }
    }

    /// nil when nothing is stored or the user cancelled the authentication prompt.
    static func load(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.localizedReason = "Unlock the saved vault password"
        query[kSecUseAuthenticationContext as String] = context
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
        case errSecItemNotFound, errSecUserCanceled, errSecAuthFailed:
            return nil
        default:
            throw Failure.status(status)
        }
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
