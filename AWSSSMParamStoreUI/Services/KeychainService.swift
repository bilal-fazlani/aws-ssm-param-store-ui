import Foundation
import Security
import LocalAuthentication

/// Service for securely storing and retrieving credentials from macOS Keychain.
/// Uses `.userPresence` access control so items are protected by Touch ID or device passcode.
struct KeychainService {
    // v2 service name — cleanly abandons any old items stored without access control
    private static let serviceName = "com.bilal-fazlani.aws-ssm-param-store-ui.aws-credentials.v2"

    enum KeychainError: Error, LocalizedError {
        case duplicateItem
        case itemNotFound
        case unexpectedStatus(OSStatus)
        case invalidData

        var errorDescription: String? {
            switch self {
            case .duplicateItem:        return "Item already exists in Keychain"
            case .itemNotFound:         return "Item not found in Keychain"
            case .unexpectedStatus(let status): return "Keychain error: \(status)"
            case .invalidData:          return "Invalid data format"
            }
        }
    }

    // MARK: - Access Control

    /// Touch ID or device passcode, device-only (no iCloud sync of raw secrets).
    private static func makeAccessControl() -> SecAccessControl? {
        SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            .userPresence,
            nil
        )
    }

    // MARK: - Secret Key

    static func saveSecretKey(_ secretKey: String, for connectionId: UUID) throws {
        let account = connectionId.uuidString
        guard let data = secretKey.data(using: .utf8) else { throw KeychainError.invalidData }
        guard let access = makeAccessControl() else { throw KeychainError.unexpectedStatus(errSecParam) }

        // Delete first — kSecAttrAccessControl cannot be changed with SecItemUpdate
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: access
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    /// Read the secret key. Pass a pre-authenticated `LAContext` to avoid an extra UI prompt.
    static func getSecretKey(for connectionId: UUID, context: LAContext? = nil) -> String? {
        let account = connectionId.uuidString

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let context {
            query[kSecUseAuthenticationContext as String] = context
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    /// Check whether a secret key exists without triggering any authentication UI.
    static func hasSecretKey(for connectionId: UUID) -> Bool {
        let account = connectionId.uuidString

        // interactionNotAllowed = true: fail immediately rather than prompt
        let context = LAContext()
        context.interactionNotAllowed = true

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]

        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    static func deleteSecretKey(for connectionId: UUID) throws {
        let account = connectionId.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Session Token

    static func saveSessionToken(_ token: String, for connectionId: UUID) throws {
        let account = connectionId.uuidString + "-session-token"
        guard let data = token.data(using: .utf8) else { throw KeychainError.invalidData }
        guard let access = makeAccessControl() else { throw KeychainError.unexpectedStatus(errSecParam) }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: access
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    /// Read the session token. Pass a pre-authenticated `LAContext` to avoid an extra UI prompt.
    static func getSessionToken(for connectionId: UUID, context: LAContext? = nil) -> String? {
        let account = connectionId.uuidString + "-session-token"

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let context {
            query[kSecUseAuthenticationContext as String] = context
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    static func deleteSessionToken(for connectionId: UUID) throws {
        let account = connectionId.uuidString + "-session-token"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
