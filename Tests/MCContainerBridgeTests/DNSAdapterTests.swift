import Foundation
@testable import MCContainerBridge
import MCModel
import Testing

@Suite("DNS adapter")
struct DNSAdapterTests {
    @Test func `create normalizes a strict suffix and optional IPv4 redirect`() async throws {
        let backend = FakeDNSBackend()
        let adapter = DNSAdapter(backend: backend)

        let entry = try await adapter.create(.init(name: "Dev.Example", addresses: ["192.0.2.10"]))

        #expect(entry == .init(name: "dev.example", addresses: ["192.0.2.10"]))
        #expect(await backend.created == [.init(name: "dev.example", redirectIPv4: "192.0.2.10")])
    }

    @Test(arguments: [
        "", ".example", "example..test", "-bad.test", "bad-.test",
        "containerization.example", "bad/path", String(repeating: "a", count: 64) + ".test"
    ])
    func `unsafe suffix is rejected before privileged access`(_ name: String) async {
        let backend = FakeDNSBackend()
        let adapter = DNSAdapter(backend: backend)

        await #expect(throws: DNSAdapterError.invalidName(name)) {
            try await adapter.create(.init(name: name, addresses: []))
        }
        #expect(await backend.created.isEmpty)
    }

    @Test func `create accepts at most one IPv4 redirect`() async {
        let backend = FakeDNSBackend()
        let adapter = DNSAdapter(backend: backend)

        await #expect(throws: DNSAdapterError.invalidAddresses) {
            try await adapter.create(.init(name: "dev.example", addresses: ["::1"]))
        }
        await #expect(throws: DNSAdapterError.invalidAddresses) {
            try await adapter.create(.init(name: "dev.example", addresses: ["192.0.2.1", "192.0.2.2"]))
        }
        #expect(await backend.created.isEmpty)
    }

    @Test func `list is stable and delete reports each independent result`() async throws {
        let backend = FakeDNSBackend(
            entries: [.init(name: "z.test", addresses: []), .init(name: "a.test", addresses: ["192.0.2.3"])],
            deleteFailures: ["missing.test"]
        )
        let adapter = DNSAdapter(backend: backend)

        #expect(try await adapter.list().map(\.name) == ["a.test", "z.test"])
        let results = try await adapter.delete(names: ["z.test", "missing.test"])
        #expect(results.map(\.id) == ["z.test", "missing.test"])
        #expect(results.map(\.succeeded) == [true, false])
    }
}

private actor FakeDNSBackend: DNSBackend {
    struct CreateCall: Equatable, Sendable {
        let name: String
        let redirectIPv4: String?
    }

    var entries: [DNSEntry]
    var deleteFailures: Set<String>
    var created: [CreateCall] = []

    init(entries: [DNSEntry] = [], deleteFailures: Set<String> = []) {
        self.entries = entries
        self.deleteFailures = deleteFailures
    }

    func create(name: String, redirectIPv4: String?) async throws -> DNSEntry {
        created.append(.init(name: name, redirectIPv4: redirectIPv4))
        return .init(name: name, addresses: redirectIPv4.map { [$0] } ?? [])
    }

    func delete(name: String) async throws {
        if deleteFailures.contains(name) {
            throw DNSAdapterTestFailure.missing
        }
    }

    func list() async throws -> [DNSEntry] {
        entries
    }
}

private enum DNSAdapterTestFailure: Error {
    case missing
}
