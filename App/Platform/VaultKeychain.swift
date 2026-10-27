import Foundation
import LocalAuthentication
import OSLog
import Security

/// Stores encrypted-vault passwords as generic passwords. Where the data-protection keychain is
/// available the item is gated by `.userPresence` (Touch ID). Ad-hoc signed builds lack the
/// entitlement (-34018), so those fall back to the legacy login keychain without gating.
enum VaultKeychain {
    static let service = "com.prabhatkumar.Sweepkey.vault"
    private static let log = Logger(subsystem: "com.prabhatkumar.Sweepkey", category: "keychain")

    enum Failure: Error, LocalizedError {
        case status(OSStatus)
        var errorDescription: String? {
            guard case .status(let status) = self else { return nil }
            return (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
        }
    }

    private static func query(account: String, dataProtection: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account]
        if dataProtection { q[kSecUseDataProtectionKeychain as String] = true }
        return q
    }

    /// Add first; on a duplicate update in place, so a failed save never loses the old password.
    private static func upsert(_ attributes: [String: Any], account: String, dataProtection: Bool) -> OSStatus {
        var add = query(account: account, dataProtection: dataProtection)
        add.merge(attributes) { _, new in new }
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecDuplicateItem else { return status }
        var update = attributes
        update.removeValue(forKey: kSecAttrAccessControl as String)
        return SecItemUpdate(query(account: account, dataProtection: dataProtection) as CFDictionary, update as CFDictionary)
    }

    /// Whether the last save landed in the Touch ID-gated keychain.
    @discardableResult
    static func save(password: String, account: String) throws -> Bool {
        let data = Data(password.utf8)
        if let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil) {
            let status = upsert(
                [kSecAttrAccessControl as String: access, kSecValueData as String: data],
                account: account, dataProtection: true)
            if status == errSecSuccess { return true }
            log.info("Gated keychain save unavailable (status \(status)); using the login keychain")
        }
        let status = upsert([kSecValueData as String: data], account: account, dataProtection: false)
        guard status == errSecSuccess else { throw Failure.status(status) }
        return false
    }

    /// nil when nothing is stored or the user cancelled the authentication prompt.
    static func load(account: String) throws -> String? {
        let context = LAContext()
        context.localizedReason = "Unlock the saved vault password"
        for dataProtection in [true, false] {
            var q = query(account: account, dataProtection: dataProtection)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            q[kSecUseAuthenticationContext as String] = context
            var item: CFTypeRef?
            let status = SecItemCopyMatching(q as CFDictionary, &item)
            switch status {
            case errSecSuccess:
                if let value = (item as? Data).flatMap({ String(data: $0, encoding: .utf8) }) { return value }
            case errSecUserCanceled:
                return nil
            case errSecItemNotFound, errSecAuthFailed, errSecMissingEntitlement:
                continue
            default:
                throw Failure.status(status)
            }
        }
        return nil
    }

    static func exists(account: String) -> Bool {
        for dataProtection in [true, false] {
            var q = query(account: account, dataProtection: dataProtection)
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            let context = LAContext()
            context.interactionNotAllowed = true
            q[kSecUseAuthenticationContext as String] = context
            let status = SecItemCopyMatching(q as CFDictionary, nil)
            // Gated items report interaction-not-allowed when present.
            if status == errSecSuccess || status == errSecInteractionNotAllowed { return true }
        }
        return false
    }

    static func delete(account: String) {
        for dataProtection in [true, false] {
            SecItemDelete(query(account: account, dataProtection: dataProtection) as CFDictionary)
        }
    }

    /// Whether Touch ID gating works in this build. Probed once per session.
    static let gatingAvailable: Bool = {
        let account = "sweepkey.probe.\(UUID().uuidString)"
        defer { delete(account: account) }
        return (try? save(password: "probe", account: account)) ?? false
    }()
}
