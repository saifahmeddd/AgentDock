import Foundation
import Security

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain returned status \(status)."
        }
    }
}

actor KeychainService {
    static let shared = KeychainService()

    // Named credential slots
    enum Credential: String {
        case nimAPIKey = "AgentDock.NIM/default"
        case notionToken = "AgentDock.Notion/token"
        case notionPageID = "AgentDock.Notion/pageID"
        case linearAPIKey = "AgentDock.Linear/apiKey"
        case linearTeamID = "AgentDock.Linear/teamID"

        fileprivate var service: String { String(rawValue.split(separator: "/").first ?? "") }
        fileprivate var account: String { String(rawValue.split(separator: "/").last ?? "") }
    }

    // MARK: - Generic CRUD

    func save(_ value: String, for credential: Credential) throws {
        try save(value, service: credential.service, account: credential.account)
    }

    func load(_ credential: Credential) throws -> String? {
        try load(service: credential.service, account: credential.account)
    }

    func delete(_ credential: Credential) throws {
        try delete(service: credential.service, account: credential.account)
    }

    // MARK: - Legacy API key helpers (backwards compatibility)

    func saveAPIKey(_ key: String) throws {
        try save(key, for: .nimAPIKey)
    }

    func loadAPIKey() throws -> String? {
        try load(.nimAPIKey)
    }

    func deleteAPIKey() throws {
        try delete(.nimAPIKey)
    }

    // MARK: - Private

    private func save(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(service: service, account: account)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if status == errSecSuccess { return }

        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
            return
        }

        throw KeychainError.unexpectedStatus(status)
    }

    private func load(service: String, account: String) throws -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
