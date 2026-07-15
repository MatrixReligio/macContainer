import ContainerizationOCI
import Foundation
import MCModel
import Security

public enum RegistryCredentialStoreError: Error, Equatable, Sendable {
    case keychain(OSStatus)
    case malformedResult
}

public actor RegistryCredentialStore: RegistryCredentialStorage {
    public static let securityDomain = "com.apple.container.registry"
    static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String

    private let keychainPath: URL?

    public init(keychainPath: URL? = nil) {
        self.keychainPath = keychainPath
    }

    public func save(server: String, username: String, password: Data) throws {
        let server = Self.canonicalServer(server)
        var match = try query(server: server)
        let attributes: [String: Any] = [
            kSecAttrAccount as String: username,
            kSecValueData as String: password,
            kSecAttrAccessible as String: Self.accessibility,
            kSecAttrSynchronizable as String: false
        ]
        let updateStatus = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw RegistryCredentialStoreError.keychain(updateStatus)
        }

        match[kSecAttrAccount as String] = username
        match[kSecValueData as String] = password
        match[kSecAttrAccessible as String] = Self.accessibility
        match[kSecAttrSynchronizable as String] = false
        match.removeValue(forKey: kSecMatchSearchList as String)
        if let keychain = try openKeychain() {
            match[kSecUseKeychain as String] = keychain
        }
        let addStatus = SecItemAdd(match as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw RegistryCredentialStoreError.keychain(addStatus)
        }
    }

    public func delete(server: String) throws {
        let status = try SecItemDelete(
            query(server: Self.canonicalServer(server)) as CFDictionary
        )
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw RegistryCredentialStoreError.keychain(status)
        }
    }

    public func list() throws -> [RegistrySummary] {
        var query = try query(server: nil)
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw RegistryCredentialStoreError.keychain(status)
        }
        let dictionaries: [[String: Any]]
        if let multiple = result as? [[String: Any]] {
            dictionaries = multiple
        } else if let single = result as? [String: Any] {
            dictionaries = [single]
        } else {
            throw RegistryCredentialStoreError.malformedResult
        }
        return try dictionaries.map { item in
            guard let server = item[kSecAttrServer as String] as? String,
                  let username = item[kSecAttrAccount as String] as? String
            else {
                throw RegistryCredentialStoreError.malformedResult
            }
            return RegistrySummary(server: server, username: username)
        }
    }

    private func query(server: String?) throws -> [String: Any] {
        var result: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrSecurityDomain as String: Self.securityDomain
        ]
        if let server {
            result[kSecAttrServer as String] = server
        }
        if let keychain = try openKeychain() {
            result[kSecMatchSearchList as String] = [keychain]
        }
        return result
    }

    private func openKeychain() throws -> SecKeychain? {
        guard let keychainPath else {
            return nil
        }
        var keychain: SecKeychain?
        let status = SecKeychainOpen(keychainPath.path, &keychain)
        guard status == errSecSuccess else {
            throw RegistryCredentialStoreError.keychain(status)
        }
        return keychain
    }

    private static func canonicalServer(_ server: String) -> String {
        Reference.resolveDomain(domain: server)
    }
}
