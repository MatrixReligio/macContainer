import Foundation
@testable import MCContainerBridge
import MCModel
import Testing

@Suite("Volume adapter")
struct VolumeAdapterTests {
    @Test func `covers all operations and rejects duplicate creation`() async throws {
        let existing = VolumeDetail(
            summary: VolumeSummary(name: "data", createdAt: Date(timeIntervalSince1970: 10)),
            source: "/private/volume/data",
            labels: ["team": "app"]
        )
        let backend = FakeVolumeBackend(volumes: [existing])
        let adapter = VolumeAdapter(client: backend)

        await #expect(throws: VolumeAdapterError.duplicateName("data")) {
            try await adapter.create(VolumeCreateRequest(name: "data"))
        }
        _ = try await adapter.create(VolumeCreateRequest(name: "cache", labels: ["type": "cache"]))
        _ = try await adapter.delete(names: ["data"])
        _ = try await adapter.prune()
        _ = try await adapter.list()
        _ = try await adapter.inspect(name: "data")

        #expect(await backend.createdNames == ["cache"])
        #expect(await backend.operationIDs == [
            "list", "list", "create", "delete", "prune", "list", "inspect"
        ])
    }

    @Test func `invalid volume name fails before backend access`() async {
        let backend = FakeVolumeBackend(volumes: [])
        let adapter = VolumeAdapter(client: backend)

        await #expect(throws: VolumeAdapterError.invalidName("../escape")) {
            try await adapter.create(VolumeCreateRequest(name: "../escape"))
        }

        #expect(await backend.operationIDs.isEmpty)
    }

    @Test func `batch deletion preserves task cancellation`() async {
        let backend = FakeVolumeBackend(volumes: [])
        let adapter = VolumeAdapter(client: backend)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await adapter.delete(names: ["data"])
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await backend.operationIDs.isEmpty)
    }
}

private actor FakeVolumeBackend: VolumeBackend {
    private let volumes: [VolumeDetail]
    private(set) var operationIDs: [String] = []
    private(set) var createdNames: [String] = []

    init(volumes: [VolumeDetail]) {
        self.volumes = volumes
    }

    func create(_ request: VolumeCreateRequest) async throws -> VolumeDetail {
        operationIDs.append("create")
        createdNames.append(request.name)
        return VolumeDetail(summary: VolumeSummary(name: request.name), labels: request.labels)
    }

    func delete(name _: String) async throws {
        operationIDs.append("delete")
    }

    func prune() async throws -> PruneResult {
        operationIDs.append("prune")
        return PruneResult(deletedIDs: ["unused"], reclaimedBytes: 100)
    }

    func list() async throws -> [VolumeDetail] {
        operationIDs.append("list")
        return volumes
    }

    func inspect(name: String) async throws -> VolumeDetail {
        operationIDs.append("inspect")
        guard let volume = volumes.first(where: { $0.summary.name == name }) else {
            throw FakeVolumeError.notFound(name)
        }
        return volume
    }
}

private enum FakeVolumeError: Error {
    case notFound(String)
}
