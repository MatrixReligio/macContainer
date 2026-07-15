import Foundation
import MCModel

public struct BackendTransferProgress: Equatable, Sendable {
    public let phase: String
    public let completedBytes: Int64
    public let totalBytes: Int64?
    public let completedLayers: Int
    public let totalLayers: Int?

    public init(
        phase: String,
        completedBytes: Int64,
        totalBytes: Int64? = nil,
        completedLayers: Int = 0,
        totalLayers: Int? = nil
    ) {
        self.phase = phase
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.completedLayers = completedLayers
        self.totalLayers = totalLayers
    }
}

public struct BackendImageLoadResult: Equatable, Sendable {
    public let images: [ImageDetail]
    public let rejectedMembers: [String]

    public init(images: [ImageDetail], rejectedMembers: [String]) {
        self.images = images
        self.rejectedMembers = rejectedMembers
    }
}

public protocol ImageBackend: Sendable {
    func list() async throws -> [ImageDetail]
    func pull(
        _ request: ImageTransferRequest,
        progress: @escaping @Sendable (BackendTransferProgress) async -> Void
    ) async throws -> ImageDetail
    func push(
        _ request: ImageTransferRequest,
        progress: @escaping @Sendable (BackendTransferProgress) async -> Void
    ) async throws
    func save(references: [String], destination: URL) async throws
    func load(source: URL) async throws -> BackendImageLoadResult
    func tag(source: String, target: String) async throws
    func delete(reference: String) async throws
    func prune() async throws -> PruneResult
    func inspect(reference: String) async throws -> ImageDetail
}

public enum ImageAdapterError: Error, Equatable, Sendable {
    case invalidLocalURL
    case archiveContainsRejectedMembers
}

public struct ImageAdapter: ImageOperations, Sendable {
    private let client: any ImageBackend
    private let coordinator: OperationCoordinator

    public init(
        client: any ImageBackend = AppleImageBackend(),
        coordinator: OperationCoordinator = OperationCoordinator()
    ) {
        self.client = client
        self.coordinator = coordinator
    }

    public func list() async throws -> [ImageSummary] {
        try await client.list().map(\.summary)
    }

    public func pull(
        _ request: ImageTransferRequest
    ) async throws -> AsyncThrowingStream<TransferProgress, any Error> {
        transferStream(key: request.reference) { progress in
            _ = try await client.pull(request, progress: progress)
        }
    }

    public func push(
        _ request: ImageTransferRequest
    ) async throws -> AsyncThrowingStream<TransferProgress, any Error> {
        transferStream(key: request.reference) { progress in
            try await client.push(request, progress: progress)
        }
    }

    public func save(references: [String], destination: URL) async throws {
        guard destination.isFileURL else {
            throw ImageAdapterError.invalidLocalURL
        }
        let access = SecurityScopedAccess([destination])
        defer { access.close() }
        try await coordinator.withLock(.lifecycle) {
            try await client.save(
                references: references,
                destination: destination.standardizedFileURL
            )
        }
    }

    public func load(source: URL) async throws -> [ImageSummary] {
        guard source.isFileURL else {
            throw ImageAdapterError.invalidLocalURL
        }
        let access = SecurityScopedAccess([source])
        defer { access.close() }
        return try await coordinator.withLock(.lifecycle) {
            let result = try await client.load(source: source.standardizedFileURL)
            guard result.rejectedMembers.isEmpty else {
                throw ImageAdapterError.archiveContainsRejectedMembers
            }
            return result.images.map(\.summary)
        }
    }

    public func tag(source: String, target: String) async throws {
        try await coordinator.withLock(.image(source)) {
            try await client.tag(source: source, target: target)
        }
    }

    public func delete(references: [String]) async throws -> [BatchItemResult] {
        var results: [BatchItemResult] = []
        results.reserveCapacity(references.count)
        for reference in references {
            do {
                try await coordinator.withLock(.image(reference)) {
                    try await client.delete(reference: reference)
                }
                results.append(BatchItemResult(id: reference, succeeded: true))
            } catch {
                results.append(
                    BatchItemResult(
                        id: reference,
                        succeeded: false,
                        error: Self.userFacing(error)
                    )
                )
            }
        }
        return results
    }

    public func prune() async throws -> PruneResult {
        try await coordinator.withLock(.lifecycle) {
            try await client.prune()
        }
    }

    public func inspect(reference: String) async throws -> ImageDetail {
        try await client.inspect(reference: reference)
    }

    private func transferStream(
        key: String,
        operation: @escaping @Sendable (
            @escaping @Sendable (BackendTransferProgress) async -> Void
        ) async throws -> Void
    ) -> AsyncThrowingStream<TransferProgress, any Error> {
        let (stream, continuation) = AsyncThrowingStream<TransferProgress, any Error>.makeStream()
        let accumulator = TransferProgressAccumulator()
        let task = Task {
            do {
                try await coordinator.withLock(.image(key)) {
                    try await operation { update in
                        let mapped = await accumulator.map(update)
                        continuation.yield(mapped)
                    }
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private static func userFacing(_ error: any Error) -> UserFacingError {
        UserFacingError(
            code: "image.delete.failed",
            messageKey: "error.image.delete.failed",
            recoveryKey: "recovery.image.delete.failed",
            redactedDetails: String(describing: type(of: error))
        )
    }
}

private actor TransferProgressAccumulator {
    private var completedBytes: Int64 = 0
    private var totalBytes: Int64?
    private var completedLayers = 0
    private var totalLayers: Int?

    func map(_ update: BackendTransferProgress) -> TransferProgress {
        completedBytes = max(completedBytes, update.completedBytes)
        completedLayers = max(completedLayers, update.completedLayers)
        totalBytes = Self.monotonicTotal(totalBytes, update.totalBytes, floor: completedBytes)
        totalLayers = Self.monotonicTotal(totalLayers, update.totalLayers, floor: completedLayers)
        return TransferProgress(
            phase: update.phase,
            completedBytes: completedBytes,
            totalBytes: totalBytes,
            completedLayers: completedLayers,
            totalLayers: totalLayers
        )
    }

    private static func monotonicTotal<Value: FixedWidthInteger>(
        _ previous: Value?,
        _ current: Value?,
        floor: Value
    ) -> Value? {
        guard previous != nil || current != nil else {
            return nil
        }
        return max(previous ?? 0, current ?? 0, floor)
    }
}
