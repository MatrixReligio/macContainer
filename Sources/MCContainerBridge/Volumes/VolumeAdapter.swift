import Foundation
import MCModel

public protocol VolumeBackend: Sendable {
    func create(_ request: VolumeCreateRequest) async throws -> VolumeDetail
    func delete(name: String) async throws
    func prune() async throws -> PruneResult
    func list() async throws -> [VolumeDetail]
    func inspect(name: String) async throws -> VolumeDetail
}

public enum VolumeAdapterError: Error, Equatable, Sendable {
    case invalidName(String)
    case duplicateName(String)
}

public struct VolumeAdapter: VolumeOperations, Sendable {
    private let client: any VolumeBackend
    private let coordinator: OperationCoordinator

    public init(
        client: any VolumeBackend = AppleVolumeBackend(),
        coordinator: OperationCoordinator = OperationCoordinator()
    ) {
        self.client = client
        self.coordinator = coordinator
    }

    public func create(_ request: VolumeCreateRequest) async throws -> VolumeSummary {
        guard Self.validName(request.name) else {
            throw VolumeAdapterError.invalidName(request.name)
        }
        return try await coordinator.withLock(.volume(request.name)) {
            let existing = try await client.list()
            guard !existing.contains(where: { $0.summary.name == request.name }) else {
                throw VolumeAdapterError.duplicateName(request.name)
            }
            return try await client.create(request).summary
        }
    }

    public func delete(names: [String]) async throws -> [BatchItemResult] {
        var results: [BatchItemResult] = []
        results.reserveCapacity(names.count)
        for name in names {
            guard Self.validName(name) else {
                results.append(Self.failure(name: name, error: VolumeAdapterError.invalidName(name)))
                continue
            }
            do {
                try await coordinator.withLock(.volume(name)) {
                    try await client.delete(name: name)
                }
                results.append(BatchItemResult(id: name, succeeded: true))
            } catch {
                results.append(Self.failure(name: name, error: error))
            }
        }
        return results
    }

    public func prune() async throws -> PruneResult {
        try await coordinator.withLock(.lifecycle) {
            try await client.prune()
        }
    }

    public func list() async throws -> [VolumeSummary] {
        try await client.list().map(\.summary)
    }

    public func inspect(name: String) async throws -> VolumeDetail {
        guard Self.validName(name) else {
            throw VolumeAdapterError.invalidName(name)
        }
        return try await client.inspect(name: name)
    }

    private static func validName(_ name: String) -> Bool {
        guard name.count <= 255 else {
            return false
        }
        return name.range(
            of: "^[A-Za-z0-9][A-Za-z0-9_.-]*$",
            options: .regularExpression
        ) != nil
    }

    private static func failure(name: String, error: any Error) -> BatchItemResult {
        let code = error is VolumeAdapterError ? "volume.name.invalid" : "volume.delete.failed"
        return BatchItemResult(
            id: name,
            succeeded: false,
            error: UserFacingError(
                code: code,
                messageKey: "error.\(code)",
                redactedDetails: String(describing: type(of: error))
            )
        )
    }
}
