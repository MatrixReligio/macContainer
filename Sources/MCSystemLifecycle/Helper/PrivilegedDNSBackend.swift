import MCContainerBridge
import MCModel

public protocol DNSDomainPrivilegedHelping: Sendable {
    func createDNSDomain(_ request: DNSDomainRequest) async throws
    func deleteDNSDomain(name: String) async throws
}

extension HelperClient: DNSDomainPrivilegedHelping {
    public func createDNSDomain(_ request: DNSDomainRequest) async throws {
        _ = try await perform(.createDNSDomain(request))
    }

    public func deleteDNSDomain(name: String) async throws {
        _ = try await perform(.deleteDNSDomain(name: name))
    }
}

public struct PrivilegedDNSBackend: DNSBackend, Sendable {
    private let helper: any DNSDomainPrivilegedHelping
    private let reader: any DNSBackend

    public init(
        helper: any DNSDomainPrivilegedHelping = HelperClient(),
        reader: any DNSBackend = AppleDNSBackend()
    ) {
        self.helper = helper
        self.reader = reader
    }

    public func create(name: String, redirectIPv4: String?) async throws -> DNSEntry {
        try await helper.createDNSDomain(.init(name: name, redirectIPv4: redirectIPv4))
        return DNSEntry(name: name, addresses: redirectIPv4.map { [$0] } ?? [])
    }

    public func delete(name: String) async throws {
        try await helper.deleteDNSDomain(name: name)
    }

    public func list() async throws -> [DNSEntry] {
        try await reader.list()
    }
}
