import ContainerAPIClient
import ContainerResource
import Foundation
import MCModel

public struct AppleVolumeBackend: VolumeBackend, Sendable {
    private let containerClient: ContainerClient

    public init(containerClient: ContainerClient = ContainerClient()) {
        self.containerClient = containerClient
    }

    public func create(_ request: VolumeCreateRequest) async throws -> VolumeDetail {
        try await Self.detail(
            ClientVolume.create(
                name: request.name,
                labels: request.labels
            )
        )
    }

    public func delete(name: String) async throws {
        try await ClientVolume.delete(name: name)
    }

    public func prune() async throws -> PruneResult {
        let volumes = try await ClientVolume.list()
        let containers = try await containerClient.list()
        let inUse = Set(
            containers.flatMap { snapshot in
                snapshot.configuration.mounts.compactMap { mount in
                    mount.isVolume ? mount.volumeName : nil
                }
            }
        )
        let candidates = volumes.filter { !inUse.contains($0.name) }
        var deleted: [String] = []
        var reclaimed: Int64 = 0
        for candidate in candidates {
            do {
                let bytes = try await ClientVolume.volumeDiskUsage(name: candidate.name)
                try await ClientVolume.delete(name: candidate.name)
                deleted.append(candidate.name)
                reclaimed = Self.addClamped(reclaimed, Int64(clamping: bytes))
            } catch {
                continue
            }
        }
        return PruneResult(deletedIDs: deleted, reclaimedBytes: reclaimed)
    }

    public func list() async throws -> [VolumeDetail] {
        try await ClientVolume.list().map(Self.detail)
    }

    public func inspect(name: String) async throws -> VolumeDetail {
        try await Self.detail(ClientVolume.inspect(name))
    }

    private static func detail(_ volume: VolumeConfiguration) -> VolumeDetail {
        VolumeDetail(
            summary: VolumeSummary(name: volume.name, createdAt: volume.creationDate),
            source: volume.source,
            labels: volume.labels
        )
    }

    private static func addClamped(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? .max : result
    }
}
