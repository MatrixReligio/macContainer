import ContainerAPIClient
import ContainerizationExtras
import DNSServer
import Foundation
import MCModel
import SystemPackage

public protocol DNSBackend: Sendable {
    func create(name: String, redirectIPv4: String?) async throws -> DNSEntry
    func delete(name: String) async throws
    func list() async throws -> [DNSEntry]
}

public enum DNSAdapterError: Error, Equatable, Sendable {
    case invalidName(String)
    case invalidAddresses
}

public struct DNSAdapter: DNSOperations, Sendable {
    private let backend: any DNSBackend
    private let coordinator: OperationCoordinator

    public init(
        backend: any DNSBackend = AppleDNSBackend(),
        coordinator: OperationCoordinator = OperationCoordinator()
    ) {
        self.backend = backend
        self.coordinator = coordinator
    }

    public func create(_ request: DNSCreateRequest) async throws -> DNSEntry {
        let name = try Self.normalizedName(request.name)
        let address = try Self.redirectAddress(request.addresses)
        return try await coordinator.withLock(.systemService) {
            try await backend.create(name: name, redirectIPv4: address)
        }
    }

    public func delete(names: [String]) async throws -> [BatchItemResult] {
        var results: [BatchItemResult] = []
        results.reserveCapacity(names.count)
        for requestedName in names {
            try Task.checkCancellation()
            do {
                let name = try Self.normalizedName(requestedName)
                try await coordinator.withLock(.systemService) {
                    try await backend.delete(name: name)
                }
                results.append(BatchItemResult(id: requestedName, succeeded: true))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                results.append(Self.failure(id: requestedName, error: error))
            }
        }
        return results
    }

    public func list() async throws -> [DNSEntry] {
        try await backend.list().sorted { $0.name < $1.name }
    }

    static func normalizedName(_ rawValue: String) throws -> String {
        let name = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        let asciiLettersAndDigits = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        let valid = !name.isEmpty
            && name.utf8.count <= 253
            && !name.hasPrefix("containerization.")
            && labels.allSatisfy { label in
                guard !label.isEmpty,
                      label.utf8.count <= 63,
                      label.first != "-",
                      label.last != "-"
                else { return false }
                return label.unicodeScalars.allSatisfy {
                    asciiLettersAndDigits.contains($0) || $0 == "-"
                }
            }
        guard valid else {
            throw DNSAdapterError.invalidName(rawValue)
        }
        return name
    }

    private static func redirectAddress(_ addresses: [String]) throws -> String? {
        guard addresses.count <= 1 else {
            throw DNSAdapterError.invalidAddresses
        }
        guard let address = addresses.first else { return nil }
        guard let parsed = try? IPAddress(address), case .v4 = parsed else {
            throw DNSAdapterError.invalidAddresses
        }
        return parsed.description
    }

    private static func failure(id: String, error: any Error) -> BatchItemResult {
        let code = error is DNSAdapterError ? "dns.name.invalid" : "dns.delete.failed"
        return BatchItemResult(
            id: id,
            succeeded: false,
            error: UserFacingError(
                code: code,
                messageKey: "error.\(code)",
                redactedDetails: String(describing: type(of: error))
            )
        )
    }
}

public struct AppleDNSBackend: DNSBackend, @unchecked Sendable {
    private let resolver: HostDNSResolver
    private let packetFilter: PacketFilter
    private let resolverDirectory: URL

    public init(
        resolver: HostDNSResolver = HostDNSResolver(),
        packetFilter: PacketFilter = PacketFilter(),
        resolverDirectory: URL = URL(fileURLWithPath: HostDNSResolver.defaultConfigPath.string)
    ) {
        self.resolver = resolver
        self.packetFilter = packetFilter
        self.resolverDirectory = resolverDirectory
    }

    public func create(name: String, redirectIPv4: String?) async throws -> DNSEntry {
        let domain = try DNSName(name)
        let redirect = try redirectIPv4.map(IPAddress.init)
        try resolver.createDomain(name: domain, localhost: redirect)
        var packetFilterAdded = false
        do {
            if let redirect {
                try packetFilter.createRedirectRule(
                    from: redirect,
                    to: IPAddress("127.0.0.1"),
                    domain: domain
                )
                packetFilterAdded = true
                try packetFilter.reinitialize()
            }
            try HostDNSResolver.reinitialize()
            return DNSEntry(name: domain.pqdn, addresses: redirectIPv4.map { [$0] } ?? [])
        } catch {
            if packetFilterAdded, let redirect {
                try? packetFilter.removeRedirectRule(
                    from: redirect,
                    to: IPAddress("127.0.0.1"),
                    domain: domain
                )
                try? packetFilter.reinitialize()
            }
            _ = try? resolver.deleteDomain(name: domain)
            try? HostDNSResolver.reinitialize()
            throw error
        }
    }

    public func delete(name: String) async throws {
        let domain = try DNSName(name)
        let redirect = try resolver.deleteDomain(name: domain)
        do {
            try HostDNSResolver.reinitialize()
            if let redirect {
                try packetFilter.removeRedirectRule(
                    from: redirect,
                    to: IPAddress("127.0.0.1"),
                    domain: domain
                )
                try packetFilter.reinitialize()
            }
        } catch {
            if let redirect {
                try? packetFilter.createRedirectRule(
                    from: redirect,
                    to: IPAddress("127.0.0.1"),
                    domain: domain
                )
                try? packetFilter.reinitialize()
            }
            try? resolver.createDomain(name: domain, localhost: redirect)
            try? HostDNSResolver.reinitialize()
            throw error
        }
    }

    public func list() async throws -> [DNSEntry] {
        resolver.listDomains().map { domain in
            let address = configuredRedirect(for: domain.pqdn)
            return DNSEntry(name: domain.pqdn, addresses: address.map { [$0] } ?? [])
        }
    }

    private func configuredRedirect(for name: String) -> String? {
        let url = resolverDirectory.appending(path: "\(HostDNSResolver.containerizationPrefix)\(name)")
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return contents.split(whereSeparator: \.isNewline).lazy.compactMap { line -> String? in
            let prefix = "options localhost:"
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(prefix) else { return nil }
            let candidate = String(trimmed.dropFirst(prefix.count))
            guard let parsed = try? IPAddress(candidate), case .v4 = parsed else { return nil }
            return parsed.description
        }.first
    }
}
