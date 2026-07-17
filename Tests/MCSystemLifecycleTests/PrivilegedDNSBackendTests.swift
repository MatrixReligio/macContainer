import MCContainerBridge
import MCModel
@testable import MCSystemLifecycle
import Testing

@Suite("Privileged DNS backend")
struct PrivilegedDNSBackendTests {
    @Test func `production DNS mutations cross the authenticated helper boundary`() async throws {
        let helper = RecordingDNSDomainHelper()
        let reader = RecordingDNSReader(entries: [
            .init(name: "dev.example", addresses: ["192.0.2.10"])
        ])
        let backend = PrivilegedDNSBackend(helper: helper, reader: reader)

        let created = try await backend.create(name: "dev.example", redirectIPv4: "192.0.2.10")
        try await backend.delete(name: "dev.example")

        #expect(created == .init(name: "dev.example", addresses: ["192.0.2.10"]))
        #expect(await helper.created == [
            .init(name: "dev.example", redirectIPv4: "192.0.2.10")
        ])
        #expect(await helper.deleted == ["dev.example"])
        #expect(try await backend.list() == [
            .init(name: "dev.example", addresses: ["192.0.2.10"])
        ])
        #expect(await reader.listCalls == 1)
    }

    @Test func `failed helper mutation does not report a created domain`() async {
        let backend = PrivilegedDNSBackend(
            helper: RecordingDNSDomainHelper(createError: DNSDomainHelperFailure.denied),
            reader: RecordingDNSReader()
        )

        await #expect(throws: DNSDomainHelperFailure.denied) {
            try await backend.create(name: "dev.example", redirectIPv4: nil)
        }
    }
}

private actor RecordingDNSDomainHelper: DNSDomainPrivilegedHelping {
    private let createError: DNSDomainHelperFailure?
    var created: [DNSDomainRequest] = []
    var deleted: [String] = []

    init(createError: DNSDomainHelperFailure? = nil) {
        self.createError = createError
    }

    func createDNSDomain(_ request: DNSDomainRequest) async throws {
        if let createError {
            throw createError
        }
        created.append(request)
    }

    func deleteDNSDomain(name: String) async throws {
        deleted.append(name)
    }
}

private actor RecordingDNSReader: DNSBackend {
    let entries: [DNSEntry]
    var listCalls = 0

    init(entries: [DNSEntry] = []) {
        self.entries = entries
    }

    func create(name _: String, redirectIPv4 _: String?) async throws -> DNSEntry {
        Issue.record("Privileged DNS reader must never mutate the host")
        return .init(name: "unexpected", addresses: [])
    }

    func delete(name _: String) async throws {
        Issue.record("Privileged DNS reader must never mutate the host")
    }

    func list() async throws -> [DNSEntry] {
        listCalls += 1
        return entries
    }
}

private enum DNSDomainHelperFailure: Error {
    case denied
}
