import ContainerAPIClient
import ContainerizationOCI
import ContainerPersistence
import Foundation
import MCModel

public protocol RegistryVerifier: Sendable {
    func verify(server: String, username: String, password: Data) async throws -> String
}

public protocol RegistryCredentialStorage: Sendable {
    func save(server: String, username: String, password: Data) async throws
    func delete(server: String) async throws
    func list() async throws -> [RegistrySummary]
}

public enum RegistryAdapterError: Error, Equatable, Sendable {
    case verificationFailed
    case credentialStorageFailed
}

public struct RegistryAdapter: RegistryOperations, Sendable {
    private let verifier: any RegistryVerifier
    private let store: any RegistryCredentialStorage
    private let coordinator: OperationCoordinator

    public init(
        verifier: any RegistryVerifier = AppleRegistryVerifier(),
        store: any RegistryCredentialStorage = RegistryCredentialStore(),
        coordinator: OperationCoordinator = OperationCoordinator()
    ) {
        self.verifier = verifier
        self.store = store
        self.coordinator = coordinator
    }

    public func login(_ request: RegistryLoginRequest) async throws -> RegistrySummary {
        var password = request.password
        defer { password.resetBytes(in: password.indices) }
        let canonicalServer: String
        do {
            canonicalServer = try await verifier.verify(
                server: request.server,
                username: request.username,
                password: password
            )
        } catch {
            throw RegistryAdapterError.verificationFailed
        }
        do {
            let passwordForStorage = password
            return try await coordinator.withLock(.registry(canonicalServer)) {
                try await store.save(
                    server: canonicalServer,
                    username: request.username,
                    password: passwordForStorage
                )
                return RegistrySummary(server: canonicalServer, username: request.username)
            }
        } catch {
            throw RegistryAdapterError.credentialStorageFailed
        }
    }

    public func logout(server: String) async throws {
        do {
            try await coordinator.withLock(.registry(server)) {
                try await store.delete(server: server)
            }
        } catch {
            throw RegistryAdapterError.credentialStorageFailed
        }
    }

    public func list() async throws -> [RegistrySummary] {
        do {
            return try await store.list().sorted { $0.server < $1.server }
        } catch {
            throw RegistryAdapterError.credentialStorageFailed
        }
    }
}

public struct AppleRegistryVerifier: RegistryVerifier, Sendable {
    public init() {}

    public func verify(server: String, username: String, password: Data) async throws -> String {
        guard let password = String(data: password, encoding: .utf8) else {
            throw RegistryAdapterError.verificationFailed
        }
        let configuration: ContainerSystemConfig = try await ConfigurationLoader.load()
        let canonicalServer = Reference.resolveDomain(domain: server)
        let scheme = try RequestScheme.auto.schemeFor(
            host: canonicalServer,
            internalDnsDomain: configuration.dns.domain
        )
        guard let url = URL(string: "\(scheme)://\(canonicalServer)"),
              let host = url.host
        else {
            throw RegistryAdapterError.verificationFailed
        }
        let client = RegistryClient(
            host: host,
            scheme: scheme.rawValue,
            port: url.port,
            authentication: BasicAuthentication(username: username, password: password),
            retryOptions: RetryOptions(
                maxRetries: 3,
                retryInterval: 300_000_000,
                shouldRetry: { $0.status.code >= 500 }
            )
        )
        try await client.ping()
        return canonicalServer
    }
}
