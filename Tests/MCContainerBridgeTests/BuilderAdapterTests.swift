@testable import MCContainerBridge
import MCModel
import Testing

@Suite("Builder adapter")
struct BuilderAdapterTests {
    @Test func `all lifecycle operations delegate with exact resources`() async throws {
        let resources = RuntimeResources(cpuCount: 6, memoryBytes: 8_589_934_592, diskBytes: 30_000_000_000)
        let backend = FakeBuilderBackend()
        let adapter = BuilderAdapter(client: backend)

        let started = try await adapter.start(BuilderStartRequest(resources: resources))
        let status = try await adapter.status()
        try await adapter.stop()
        try await adapter.delete()

        #expect(started == BuilderSummary(state: .running, resources: resources))
        #expect(status.state == .running)
        #expect(await backend.resources == [resources])
        #expect(await backend.operationIDs == ["start", "status", "stop", "delete"])
    }
}

private actor FakeBuilderBackend: BuilderBackend {
    private(set) var operationIDs: [String] = []
    private(set) var resources: [RuntimeResources] = []

    func start(resources: RuntimeResources) async throws -> BuilderSummary {
        operationIDs.append("start")
        self.resources.append(resources)
        return BuilderSummary(state: .running, resources: resources)
    }

    func status() async throws -> BuilderSummary {
        operationIDs.append("status")
        return BuilderSummary(state: .running, resources: resources.last)
    }

    func stop() async throws {
        operationIDs.append("stop")
    }

    func delete() async throws {
        operationIDs.append("delete")
    }
}
