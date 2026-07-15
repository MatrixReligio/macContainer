import Foundation
@testable import MCContainerBridge
import MCModel
import Security
import Testing

@Suite("Registry credential store", .serialized)
struct RegistryCredentialStoreTests {
    @Test func `isolated keychain stores device only internet passwords without changing search list`() async throws {
        let before = try KeychainFixture.searchListPaths()
        let fixture = try KeychainFixture()
        let store = RegistryCredentialStore(keychainPath: fixture.url)
        defer { fixture.close() }

        try await store.save(
            server: "docker.io",
            username: "alice",
            password: Data("secret".utf8)
        )
        let listed = try await store.list()
        let attributes = try fixture.attributes(server: "registry-1.docker.io")

        #expect(listed == [RegistrySummary(server: "registry-1.docker.io", username: "alice")])
        #expect(attributes[kSecClass as String] as? String == kSecClassInternetPassword as String)
        #expect(attributes[kSecAttrSecurityDomain as String] as? String == RegistryCredentialStore.securityDomain)
        #expect(
            RegistryCredentialStore.accessibility as String
                == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )

        try await store.delete(server: "docker.io")
        try await store.delete(server: "docker.io")
        #expect(try await store.list().isEmpty)

        fixture.close()
        #expect(try KeychainFixture.searchListPaths() == before)
        #expect(!FileManager.default.fileExists(atPath: fixture.url.path))
    }
}

private final class KeychainFixture {
    let parent: URL
    let url: URL

    private let originalSearchList: [SecKeychain]
    private var keychain: SecKeychain?
    private var isClosed = false

    init() throws {
        parent = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".artifacts/test-keychains")
        url = parent.appendingPathComponent("\(UUID().uuidString).keychain-db")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        originalSearchList = try Self.searchList()
        let password = Data(UUID().uuidString.utf8)
        var created: SecKeychain?
        let status = password.withUnsafeBytes { bytes in
            SecKeychainCreate(
                url.path,
                UInt32(bytes.count),
                bytes.baseAddress,
                false,
                nil,
                &created
            )
        }
        guard status == errSecSuccess, let created else {
            throw RegistryCredentialStoreError.keychain(status)
        }
        keychain = created
        let unlockStatus = password.withUnsafeBytes { bytes in
            SecKeychainUnlock(created, UInt32(bytes.count), bytes.baseAddress, true)
        }
        guard unlockStatus == errSecSuccess else {
            close()
            throw RegistryCredentialStoreError.keychain(unlockStatus)
        }
    }

    deinit {
        close()
    }

    func close() {
        guard !isClosed else {
            return
        }
        isClosed = true
        _ = SecKeychainSetSearchList(originalSearchList as CFArray)
        if let keychain {
            _ = SecKeychainDelete(keychain)
        }
        keychain = nil
        try? FileManager.default.removeItem(at: url)
        if (try? FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty) == true {
            try? FileManager.default.removeItem(at: parent)
        }
    }

    func attributes(server: String) throws -> [String: Any] {
        guard let keychain else {
            throw RegistryCredentialStoreError.malformedResult
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrSecurityDomain as String: RegistryCredentialStore.securityDomain,
            kSecAttrServer as String: server,
            kSecMatchSearchList as String: [keychain],
            kSecReturnAttributes as String: true,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let attributes = result as? [String: Any] else {
            throw RegistryCredentialStoreError.keychain(status)
        }
        return attributes
    }

    static func searchListPaths() throws -> [String] {
        try searchList().map(path)
    }

    private static func searchList() throws -> [SecKeychain] {
        var result: CFArray?
        let status = SecKeychainCopySearchList(&result)
        guard status == errSecSuccess, let keychains = result as? [SecKeychain] else {
            throw RegistryCredentialStoreError.keychain(status)
        }
        return keychains
    }

    private static func path(_ keychain: SecKeychain) throws -> String {
        var length: UInt32 = 0
        var bytes = [CChar](repeating: 0, count: 4096)
        length = UInt32(bytes.count)
        let status = bytes.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return errSecParam
            }
            return SecKeychainGetPath(keychain, &length, baseAddress)
        }
        guard status == errSecSuccess else {
            throw RegistryCredentialStoreError.keychain(status)
        }
        let count = bytes.firstIndex(of: 0) ?? bytes.endIndex
        let pathBytes = bytes[..<count].map(UInt8.init(bitPattern:))
        guard let path = String(bytes: pathBytes, encoding: .utf8) else {
            throw RegistryCredentialStoreError.keychain(errSecDecode)
        }
        return path
    }
}
