import Foundation
import MCModel

public protocol ContainerBackend: Sendable {
    func create(_ plan: ContainerCreatePlan) async throws -> ContainerDetail
    func list() async throws -> [ContainerDetail]
    func get(id: String) async throws -> ContainerDetail
    func bootstrap(id: String, attach: Bool) async throws -> any ContainerProcessTransport
    func stop(id: String, timeout: Duration?) async throws
    func kill(id: String, signal: String) async throws
    func delete(id: String, force: Bool) async throws
    func createProcess(_ plan: ContainerProcessPlan) async throws -> any ContainerProcessTransport
    func logs(id: String, options: LogOptions) async throws -> AsyncThrowingStream<LogRecord, any Error>
    func stats(id: String) async throws -> BackendContainerStats
    func copyIn(id: String, source: URL, destination: String) async throws
    func copyOut(id: String, source: String, destination: URL) async throws
    func export(id: String, destination: URL) async throws
    func diskUsage(id: String) async throws -> Int64
}

public enum ContainerAdapterError: Error, Equatable, Sendable {
    case identifierNotFound(String)
    case ambiguousIdentifier(String)
    case unsupportedCopyEndpoints
    case invalidLocalURL
    case invalidContainerPath
}

public struct ContainerAdapter: ContainerOperations, Sendable {
    private let client: any ContainerBackend
    private let coordinator: OperationCoordinator
    private let processID: @Sendable () -> String
    private let statsInterval: Duration

    public init(
        client: any ContainerBackend,
        coordinator: OperationCoordinator = OperationCoordinator(),
        processID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
        statsInterval: Duration = .seconds(1)
    ) {
        self.client = client
        self.coordinator = coordinator
        self.processID = processID
        self.statsInterval = statsInterval
    }

    public func run(_ request: ContainerRunRequest) async throws -> ContainerRunResult {
        try await coordinator.withLock(.container(request.create.name)) {
            let plan = UpstreamValueMapper.containerCreatePlan(
                from: request.create,
                autoRemove: request.removeAfterExit
            )
            var created: ContainerDetail?
            do {
                let container = try await client.create(plan)
                created = container
                let transport = try await client.bootstrap(id: container.summary.id, attach: request.attach)
                let session = try await ContainerProcessAdapter.start(transport)
                guard request.attach else {
                    try await session.detach()
                    return ContainerRunResult(container: container.summary)
                }

                let exit = try await session.wait()
                var cleanupError: UserFacingError?
                if request.removeAfterExit {
                    cleanupError = try await removeAfterExit(id: container.summary.id)
                }
                return ContainerRunResult(
                    container: container.summary,
                    processExit: exit,
                    cleanupError: cleanupError
                )
            } catch {
                if request.removeAfterExit, let created {
                    try? await client.delete(id: created.summary.id, force: true)
                }
                throw error
            }
        }
    }

    public func create(_ request: ContainerCreateRequest) async throws -> ContainerSummary {
        try await coordinator.withLock(.container(request.name)) {
            try await client.create(UpstreamValueMapper.containerCreatePlan(from: request)).summary
        }
    }

    public func start(ids: [String]) async throws -> [BatchItemResult] {
        try await mutate(ids: ids, failureCode: "container.start.failed") { id in
            let transport = try await client.bootstrap(id: id, attach: false)
            let session = try await ContainerProcessAdapter.start(transport)
            try await session.detach()
        }
    }

    public func stop(ids: [String], timeout: Duration?) async throws -> [BatchItemResult] {
        try await mutate(ids: ids, failureCode: "container.stop.failed") { id in
            try await client.stop(id: id, timeout: timeout)
        }
    }

    public func kill(ids: [String], signal: String) async throws -> [BatchItemResult] {
        try await mutate(ids: ids, failureCode: "container.kill.failed") { id in
            try await client.kill(id: id, signal: signal)
        }
    }

    public func delete(ids: [String], force: Bool) async throws -> [BatchItemResult] {
        try await mutate(ids: ids, failureCode: "container.delete.failed") { id in
            try await client.delete(id: id, force: force)
        }
    }

    public func list() async throws -> [ContainerSummary] {
        try await client.list().map(\.summary)
    }

    public func exec(_ request: ProcessRequest) async throws -> any ProcessSession {
        let id = try await resolve(request.resourceID)
        return try await coordinator.withLock(.container(id)) {
            let plan = UpstreamValueMapper.containerProcessPlan(
                from: request,
                resolvedContainerID: id,
                processID: processID()
            )
            return try await ContainerProcessAdapter.start(client.createProcess(plan))
        }
    }

    public func export(id: String, destination: URL) async throws {
        guard destination.isFileURL else {
            throw ContainerAdapterError.invalidLocalURL
        }
        let resolved = try await resolve(id)
        try await coordinator.withLock(.container(resolved)) {
            try await client.export(id: resolved, destination: destination.standardizedFileURL)
        }
    }

    public func logs(
        id: String,
        options: LogOptions
    ) async throws -> AsyncThrowingStream<LogRecord, any Error> {
        try await client.logs(id: resolve(id), options: options)
    }

    public func inspect(id: String) async throws -> ContainerDetail {
        try await client.get(id: resolve(id))
    }

    public func stats(id: String) async throws -> AsyncThrowingStream<ContainerStats, any Error> {
        let resolved = try await resolve(id)
        let (stream, continuation) = AsyncThrowingStream<ContainerStats, any Error>.makeStream()
        let task = Task {
            var previous: BackendContainerStats?
            do {
                while !Task.isCancelled {
                    let current = try await client.stats(id: resolved)
                    continuation.yield(Self.mapStats(current, previous: previous))
                    previous = current
                    try await Task.sleep(for: statsInterval)
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

    public func copy(_ request: CopyRequest) async throws {
        switch (request.source, request.destination) {
        case let (.local(source), .container(id, path)):
            guard source.isFileURL else {
                throw ContainerAdapterError.invalidLocalURL
            }
            try Self.validateContainerPath(path)
            let resolved = try await resolve(id)
            try await coordinator.withLock(.container(resolved)) {
                try await client.copyIn(
                    id: resolved,
                    source: source.standardizedFileURL,
                    destination: path
                )
            }
        case let (.container(id, path), .local(destination)):
            guard destination.isFileURL else {
                throw ContainerAdapterError.invalidLocalURL
            }
            try Self.validateContainerPath(path)
            let resolved = try await resolve(id)
            try await coordinator.withLock(.container(resolved)) {
                try await client.copyOut(
                    id: resolved,
                    source: path,
                    destination: destination.standardizedFileURL
                )
            }
        case (.container, .container), (.local, .local):
            throw ContainerAdapterError.unsupportedCopyEndpoints
        }
    }

    public func prune() async throws -> PruneResult {
        let candidates = try await client.list().filter { $0.summary.state == .stopped }
        var deleted: [String] = []
        var reclaimed: Int64 = 0
        for candidate in candidates {
            try Task.checkCancellation()
            do {
                let bytes = try await coordinator.withLock(.container(candidate.summary.id)) {
                    let bytes = try await client.diskUsage(id: candidate.summary.id)
                    try await client.delete(id: candidate.summary.id, force: false)
                    return bytes
                }
                deleted.append(candidate.summary.id)
                reclaimed = reclaimed.addingClamped(bytes)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        return PruneResult(deletedIDs: deleted, reclaimedBytes: reclaimed)
    }

    private func mutate(
        ids: [String],
        failureCode: String,
        operation: @escaping @Sendable (String) async throws -> Void
    ) async throws -> [BatchItemResult] {
        let inventory = try await client.list().map(\.summary.id)
        var results: [BatchItemResult] = []
        results.reserveCapacity(ids.count)
        for requestedID in ids {
            try Task.checkCancellation()
            let resolved: String
            switch Self.resolve(requestedID, in: inventory) {
            case let .success(value):
                resolved = value
            case let .failure(error):
                results.append(
                    BatchItemResult(
                        id: requestedID,
                        succeeded: false,
                        error: Self.identifierError(error)
                    )
                )
                continue
            }

            do {
                try await coordinator.withLock(.container(resolved)) {
                    try await operation(resolved)
                }
                results.append(BatchItemResult(id: requestedID, succeeded: true))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                results.append(
                    BatchItemResult(
                        id: requestedID,
                        succeeded: false,
                        error: Self.userFacing(error, code: failureCode)
                    )
                )
            }
        }
        return results
    }

    private func resolve(_ requestedID: String) async throws -> String {
        let inventory = try await client.list().map(\.summary.id)
        return try Self.resolve(requestedID, in: inventory).get()
    }

    private func removeAfterExit(id: String) async throws -> UserFacingError? {
        do {
            try await client.delete(id: id, force: false)
            return nil
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Native auto-remove can win the race with this explicit cleanup.
            // In that case the requested final state has already been reached.
            if let inventory = try? await client.list() {
                if !inventory.contains(where: { $0.summary.id == id }) {
                    return nil
                }
            }
            return Self.userFacing(error, code: "container.delete.failed")
        }
    }

    private static func resolve(
        _ requestedID: String,
        in inventory: [String]
    ) -> Result<String, ContainerAdapterError> {
        if inventory.contains(requestedID) {
            return .success(requestedID)
        }
        let matches = inventory.filter { $0.hasPrefix(requestedID) }
        switch matches.count {
        case 0: return .failure(.identifierNotFound(requestedID))
        case 1: return .success(matches[0])
        default: return .failure(.ambiguousIdentifier(requestedID))
        }
    }

    private static func identifierError(_ error: ContainerAdapterError) -> UserFacingError {
        switch error {
        case .identifierNotFound:
            UserFacingError(
                code: "container.identifier.not-found",
                messageKey: "error.container.identifier.not-found"
            )
        case .ambiguousIdentifier:
            UserFacingError(
                code: "container.identifier.ambiguous",
                messageKey: "error.container.identifier.ambiguous"
            )
        default:
            UserFacingError(code: "container.invalid-request", messageKey: "error.container.invalid-request")
        }
    }

    private static func userFacing(_ error: any Error, code: String) -> UserFacingError {
        UserFacingError(
            code: code,
            messageKey: "error.\(code)",
            recoveryKey: "recovery.\(code)",
            redactedDetails: String(describing: type(of: error))
        )
    }

    private static func validateContainerPath(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard path.hasPrefix("/"), !components.contains(".."), !path.contains("\0") else {
            throw ContainerAdapterError.invalidContainerPath
        }
    }

    private static func mapStats(
        _ current: BackendContainerStats,
        previous: BackendContainerStats?
    ) -> ContainerStats {
        let cpuFraction: Double
        if let previous, current.cpuUsageMicroseconds >= previous.cpuUsageMicroseconds {
            let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)
            cpuFraction = elapsed > 0
                ? Double(current.cpuUsageMicroseconds - previous.cpuUsageMicroseconds) / (elapsed * 1_000_000)
                : 0
        } else {
            cpuFraction = 0
        }
        return ContainerStats(
            timestamp: current.timestamp,
            cpuFraction: cpuFraction,
            memoryBytes: Int64(clamping: current.memoryBytes),
            networkReceiveBytes: Int64(clamping: current.networkReceiveBytes),
            networkTransmitBytes: Int64(clamping: current.networkTransmitBytes)
        )
    }
}

private extension Int64 {
    func addingClamped(_ other: Int64) -> Int64 {
        let (result, overflow) = addingReportingOverflow(other)
        return overflow ? .max : result
    }
}
