@testable import MCContainerBridge
import MCModel
import Testing

@Suite("Network adapter")
struct NetworkAdapterTests {
    @Test func `covers all operations and protects the built in network`() async throws {
        let builtIn = NetworkDetail(
            summary: NetworkSummary(id: "default", name: "default", state: .running, builtIn: true),
            subnet: "192.168.64.0/24",
            gateway: "192.168.64.1",
            plugin: "container-network-vmnet"
        )
        let custom = NetworkDetail(
            summary: NetworkSummary(id: "frontend", name: "frontend", state: .running),
            subnet: "10.0.0.0/24",
            gateway: "10.0.0.1",
            dnsServers: ["1.1.1.1"],
            plugin: "container-network-vmnet"
        )
        let backend = FakeNetworkBackend(networks: [builtIn, custom])
        let adapter = NetworkAdapter(client: backend)
        let request = NetworkCreateRequest(
            name: "new-network",
            subnet: "10.10.0.0/24",
            gateway: "10.10.0.1",
            dnsServers: ["1.1.1.1", "8.8.8.8"],
            labels: ["team": "app"],
            hostOnly: true,
            options: ["mtu": "1400"]
        )

        _ = try await adapter.create(request)
        let deleted = try await adapter.delete(ids: ["default", "frontend"])
        _ = try await adapter.prune()
        _ = try await adapter.list()
        let inspected = try await adapter.inspect(id: "frontend")

        #expect(await backend.createRequests == [request])
        #expect(await backend.deletedIDs == ["frontend"])
        #expect(deleted[0].error?.code == "network.builtin.protected")
        #expect(deleted[1].succeeded)
        #expect(inspected == custom)
        #expect(await backend.operationIDs == [
            "list", "create", "list", "delete", "prune", "list", "list", "inspect"
        ])
    }

    @Test func `batch deletion preserves task cancellation`() async {
        let network = NetworkDetail(
            summary: NetworkSummary(id: "frontend", name: "frontend", state: .running)
        )
        let backend = FakeNetworkBackend(networks: [network])
        let adapter = NetworkAdapter(client: backend)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await adapter.delete(ids: ["frontend"])
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await backend.deletedIDs.isEmpty)
    }
}

private actor FakeNetworkBackend: NetworkBackend {
    private let networks: [NetworkDetail]
    private(set) var operationIDs: [String] = []
    private(set) var createRequests: [NetworkCreateRequest] = []
    private(set) var deletedIDs: [String] = []

    init(networks: [NetworkDetail]) {
        self.networks = networks
    }

    func create(_ request: NetworkCreateRequest) async throws -> NetworkDetail {
        operationIDs.append("create")
        createRequests.append(request)
        return NetworkDetail(summary: NetworkSummary(id: request.name, name: request.name, state: .running))
    }

    func delete(id: String) async throws {
        operationIDs.append("delete")
        deletedIDs.append(id)
    }

    func prune() async throws -> PruneResult {
        operationIDs.append("prune")
        return PruneResult(deletedIDs: ["unused"])
    }

    func list() async throws -> [NetworkDetail] {
        operationIDs.append("list")
        return networks
    }

    func inspect(id: String) async throws -> NetworkDetail {
        operationIDs.append("inspect")
        guard let network = networks.first(where: { $0.summary.id == id }) else {
            throw FakeNetworkError.notFound(id)
        }
        return network
    }
}

private enum FakeNetworkError: Error {
    case notFound(String)
}
