import Foundation
import Security

// MARK: - Keychain Errors

enum KeychainError: Error, LocalizedError {
    case duplicateItem
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .duplicateItem:
            return "Item already exists in Keychain"
        case .itemNotFound:
            return "Item not found in Keychain"
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            return "Keychain error: \(message) (\(status))"
        case .invalidData:
            return "Could not encode/decode Keychain data"
        }
    }
}

// MARK: - Keychain Service

/// Wraps macOS Keychain (Security.framework) for secure credential storage.
/// Uses kSecClassGenericPassword with service + account keys.
final class KeychainService: Sendable {
    // Legacy Basic Auth / PAT tokens
    static let jiraService = "io.devflow.jira"
    static let githubService = "io.devflow.github"
    static let copilotService = "io.devflow.copilot"

    // Jira OAuth 2.0 tokens
    static let jiraOAuthService = "io.devflow.jira.oauth"

    // GitHub Copilot OAuth (Device Flow GitHub token)
    static let copilotGitHubService = "io.devflow.copilot.github"
    // Copilot API-specific short-lived token
    static let copilotTokenService = "io.devflow.copilot.token"

    // MARK: - Base Query

    private func baseQuery(service: String, account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }

    // MARK: - Save

    func save(service: String, account: String, token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        var query = baseQuery(service: service, account: account)
        query[kSecValueData] = data

        let status = SecItemAdd(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            throw KeychainError.duplicateItem
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Retrieve

    func retrieve(service: String, account: String) throws -> String {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard
                let data = result as? Data,
                let string = String(data: data, encoding: .utf8)
            else {
                throw KeychainError.invalidData
            }
            return string
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Update

    func update(service: String, account: String, newToken: String) throws {
        guard let data = newToken.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let query = baseQuery(service: service, account: account) as CFDictionary
        let attributes: [CFString: Any] = [kSecValueData: data]

        let status = SecItemUpdate(query, attributes as CFDictionary)

        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Delete

    func delete(service: String, account: String) throws {
        let query = baseQuery(service: service, account: account) as CFDictionary
        let status = SecItemDelete(query)

        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Upsert (Save or Update)

    func saveOrUpdate(service: String, account: String, token: String) throws {
        do {
            try save(service: service, account: account, token: token)
        } catch KeychainError.duplicateItem {
            try update(service: service, account: account, newToken: token)
        }
    }
}
