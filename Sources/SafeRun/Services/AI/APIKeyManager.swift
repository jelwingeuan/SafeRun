import Foundation
import Security

protocol CredentialStorage: Sendable {
    func save(_ credential: String) throws
    func retrieve() throws -> String?
    func replace(_ credential: String) throws
    func delete() throws
}

struct APIKeyManager: Sendable {
    private let storage: any CredentialStorage

    init(storage: any CredentialStorage = KeychainCredentialStorage()) {
        self.storage = storage
    }

    /// Local syntax validation only. Use checkConnection to verify model access.
    func validate(_ key: String) -> Bool {
        key.hasPrefix("sk-") && (20...512).contains(key.utf8.count)
            && key.utf8.allSatisfy { byte in
                (65...90).contains(byte) || (97...122).contains(byte)
                    || (48...57).contains(byte) || byte == 45 || byte == 95
            }
    }

    func save(_ key: String) throws {
        guard validate(key) else { throw AIPlannerError.invalidAPIKey }
        do { try storage.save(key) }
        catch AIPlannerError.credentialAlreadyExists { throw AIPlannerError.credentialAlreadyExists }
        catch { throw AIPlannerError.credentialStorage }
    }

    func retrieve() throws -> String? {
        let key: String?
        do { key = try storage.retrieve() }
        catch { throw AIPlannerError.credentialStorage }
        if let key, !validate(key) { throw AIPlannerError.invalidAPIKey }
        return key
    }

    func replace(_ key: String) throws {
        guard validate(key) else { throw AIPlannerError.invalidAPIKey }
        do { try storage.replace(key) }
        catch { throw AIPlannerError.credentialStorage }
    }

    func delete() throws {
        do { try storage.delete() }
        catch { throw AIPlannerError.credentialStorage }
    }
}

struct KeychainCredentialStorage: CredentialStorage {
    private let service = "com.saferun.openai"
    private let account = "api-key"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func save(_ credential: String) throws {
        var attributes = query
        attributes[kSecValueData as String] = Data(credential.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem { throw AIPlannerError.credentialAlreadyExists }
        guard status == errSecSuccess else { throw AIPlannerError.credentialStorage }
    }

    func retrieve() throws -> String? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw AIPlannerError.credentialStorage
        }
        return key
    }

    func replace(_ credential: String) throws {
        let status = SecItemUpdate(query as CFDictionary,
                                   [kSecValueData as String: Data(credential.utf8)] as CFDictionary)
        guard status == errSecSuccess else { throw AIPlannerError.credentialStorage }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AIPlannerError.credentialStorage
        }
    }
}
