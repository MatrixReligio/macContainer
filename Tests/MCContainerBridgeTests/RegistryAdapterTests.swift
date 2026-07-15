import Foundation
@testable import MCContainerBridge
import MCModel
import Testing

@Suite("Registry adapter")
struct RegistryAdapterTests {
    @Test func `login verifies before storing and list exposes metadata only`() async throws {
        let verifier = FakeRegistryVerifier()
        let store = FakeRegistryCredentialStore()
        let adapter = RegistryAdapter(verifier: verifier, store: store)
        let password = Data("top-secret".utf8)

        let result = try await adapter.login(
            RegistryLoginRequest(server: "docker.io", username: "alice", password: password)
        )
        let listed = try await adapter.list()
        try await adapter.logout(server: "docker.io")
        try await adapter.logout(server: "docker.io")

        #expect(result == RegistrySummary(server: "registry-1.docker.io", username: "alice"))
        #expect(listed == [RegistrySummary(server: "registry-1.docker.io", username: "alice")])
        #expect(await verifier.events == ["verify:docker.io:alice"])
        #expect(await store.events == ["save:registry-1.docker.io:alice", "list", "delete:docker.io", "delete:docker.io"])
        #expect(await store.savedPassword == password)
    }

    @Test func `verification errors never expose password bytes`() async {
        let verifier = FakeRegistryVerifier(shouldFail: true)
        let adapter = RegistryAdapter(verifier: verifier, store: FakeRegistryCredentialStore())

        do {
            _ = try await adapter.login(
                RegistryLoginRequest(
                    server: "example.invalid",
                    username: "alice",
                    password: Data("do-not-leak".utf8)
                )
            )
            Issue.record("expected verification failure")
        } catch {
            #expect(error is RegistryAdapterError)
            #expect(!String(describing: error).contains("do-not-leak"))
        }
    }
}

private enum FakeRegistryError: Error {
    case rejected(String)
}

private actor FakeRegistryVerifier: RegistryVerifier {
    private let shouldFail: Bool
    private(set) var events: [String] = []

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func verify(server: String, username: String, password: Data) async throws -> String {
        events.append("verify:\(server):\(username)")
        if shouldFail {
            let exposedPassword = String(bytes: password, encoding: .utf8) ?? "unreadable"
            throw FakeRegistryError.rejected(exposedPassword)
        }
        return server == "docker.io" ? "registry-1.docker.io" : server
    }
}

private actor FakeRegistryCredentialStore: RegistryCredentialStorage {
    private(set) var events: [String] = []
    private(set) var savedPassword: Data?
    private var entries: [RegistrySummary] = []

    func save(server: String, username: String, password: Data) async throws {
        events.append("save:\(server):\(username)")
        savedPassword = password
        entries = [RegistrySummary(server: server, username: username)]
    }

    func delete(server: String) async throws {
        events.append("delete:\(server)")
        entries.removeAll { $0.server == server }
    }

    func list() async throws -> [RegistrySummary] {
        events.append("list")
        return entries
    }
}
