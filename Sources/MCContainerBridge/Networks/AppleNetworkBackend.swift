import ContainerAPIClient
import ContainerizationExtras
import ContainerResource
import Foundation
import MCModel

public enum AppleNetworkBackendError: Error, Equatable, Sendable {
    case customGatewayUnsupported
    case customDNSServersUnsupported
    case protectedBuiltInNetwork
}

public struct AppleNetworkBackend: NetworkBackend, Sendable {
    private let networkClient: NetworkClient
    private let containerClient: ContainerClient

    public init(
        networkClient: NetworkClient = NetworkClient(),
        containerClient: ContainerClient = ContainerClient()
    ) {
        self.networkClient = networkClient
        self.containerClient = containerClient
    }

    public func create(_ request: NetworkCreateRequest) async throws -> NetworkDetail {
        guard request.gateway == nil else {
            throw AppleNetworkBackendError.customGatewayUnsupported
        }
        guard request.dnsServers.isEmpty else {
            throw AppleNetworkBackendError.customDNSServersUnsupported
        }
        let configuration = try NetworkConfiguration(
            name: request.name,
            mode: .nat,
            ipv4Subnet: request.subnet.map(CIDRv4.init),
            labels: ResourceLabels(request.labels),
            plugin: "container-network-vmnet"
        )
        return try await Self.detail(networkClient.create(configuration: configuration))
    }

    public func delete(id: String) async throws {
        let network = try await networkClient.get(id: id)
        guard !network.isBuiltin else {
            throw AppleNetworkBackendError.protectedBuiltInNetwork
        }
        try await networkClient.delete(id: id)
    }

    public func prune() async throws -> PruneResult {
        let containers = try await containerClient.list()
        let networks = try await networkClient.list()
        let inUse = Set(
            containers.flatMap { snapshot in
                snapshot.configuration.networks.map(\.network)
            }
        )
        let candidates = networks.filter { !$0.isBuiltin && !inUse.contains($0.id) }
        var deleted: [String] = []
        for candidate in candidates {
            try Task.checkCancellation()
            do {
                try await networkClient.delete(id: candidate.id)
                deleted.append(candidate.id)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        return PruneResult(deletedIDs: deleted)
    }

    public func list() async throws -> [NetworkDetail] {
        try await networkClient.list().map(Self.detail)
    }

    public func inspect(id: String) async throws -> NetworkDetail {
        try await Self.detail(networkClient.get(id: id))
    }

    private static func detail(_ network: NetworkResource) -> NetworkDetail {
        NetworkDetail(
            summary: NetworkSummary(
                id: network.id,
                name: network.name,
                state: .running,
                builtIn: network.isBuiltin
            ),
            subnet: network.status.ipv4Subnet.description,
            gateway: network.status.ipv4Gateway.description,
            plugin: network.configuration.plugin
        )
    }
}
