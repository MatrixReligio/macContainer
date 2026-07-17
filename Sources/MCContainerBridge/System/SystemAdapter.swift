import ContainerAPIClient
import Foundation
import MCModel
import OSLog

public protocol SystemRuntimeBackend: Sendable {
    func start(timeout: Duration) async throws
    func stop(stopActiveWorkloads: Bool, timeout: Duration) async throws
    func health(timeout: Duration) async throws -> RuntimeHealth?
    func inventory() async throws -> WorkloadInventory
    func version() async throws -> RuntimeVersionSummary
    func logs(_ options: LogOptions) async throws -> AsyncThrowingStream<LogRecord, any Error>
    func diskUsage() async throws -> DiskUsageSummary
}

public protocol UnifiedLogReading: Sendable {
    func logs(_ options: LogOptions) async throws -> AsyncThrowingStream<LogRecord, any Error>
}

public enum SystemAdapterError: Error, Equatable, Sendable {
    case invalidTimeout
    case invalidRuntimeVersion(String)
}

public struct SystemAdapter: SystemOperations, Sendable {
    private let backend: any SystemRuntimeBackend
    private let coordinator: OperationCoordinator

    public init(
        backend: any SystemRuntimeBackend = AppleSystemRuntimeBackend(),
        coordinator: OperationCoordinator = OperationCoordinator()
    ) {
        self.backend = backend
        self.coordinator = coordinator
    }

    public func start(_ request: SystemStartRequest) async throws -> SystemSummary {
        guard request.healthTimeoutSeconds > 0 else {
            throw SystemAdapterError.invalidTimeout
        }
        return try await coordinator.withLock(.systemService) {
            try await backend.start(timeout: .seconds(request.healthTimeoutSeconds))
            return SystemSummary(state: .running)
        }
    }

    public func stop(_ request: SystemStopRequest) async throws -> SystemSummary {
        guard request.timeoutSeconds > 0 else {
            throw SystemAdapterError.invalidTimeout
        }
        return try await coordinator.withLock(.systemService) {
            try await backend.stop(
                stopActiveWorkloads: request.stopActiveWorkloads,
                timeout: .seconds(request.timeoutSeconds)
            )
            return SystemSummary(state: .stopped)
        }
    }

    public func status() async throws -> SystemSummary {
        guard try await backend.health(timeout: .seconds(2))?.healthy == true else {
            return SystemSummary(state: .stopped)
        }
        let inventory = try await backend.inventory()
        return SystemSummary(
            state: .running,
            activeContainers: inventory.activeContainerIDs.count,
            activeMachines: inventory.activeMachineIDs.count
        )
    }

    public func version() async throws -> RuntimeVersionSummary {
        try await backend.version()
    }

    public func logs(
        _ options: LogOptions
    ) async throws -> AsyncThrowingStream<LogRecord, any Error> {
        try await backend.logs(options)
    }

    public func diskUsage() async throws -> DiskUsageSummary {
        try await backend.diskUsage()
    }
}

public struct AppleSystemRuntimeBackend: SystemRuntimeBackend, Sendable {
    private let controller: SystemServiceController
    private let workloads: any WorkloadManaging
    private let logReader: any UnifiedLogReading

    public init(
        controller: SystemServiceController = .production(),
        workloads: any WorkloadManaging = AppleWorkloadManager(),
        logReader: any UnifiedLogReading = AppleUnifiedLogReader()
    ) {
        self.controller = controller
        self.workloads = workloads
        self.logReader = logReader
    }

    public func start(timeout: Duration) async throws {
        _ = try await controller.start(timeout: timeout)
    }

    public func stop(stopActiveWorkloads: Bool, timeout: Duration) async throws {
        try await controller.stop(stopActiveWorkloads: stopActiveWorkloads, timeout: timeout)
    }

    public func health(timeout: Duration) async throws -> RuntimeHealth? {
        do {
            let health = try await ClientHealthCheck.ping(timeout: timeout)
            let version = try Self.semanticVersion(from: health.apiServerVersion)
            return RuntimeHealth(healthy: true, version: version)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    public func inventory() async throws -> WorkloadInventory {
        try await workloads.inventory()
    }

    public func version() async throws -> RuntimeVersionSummary {
        let health = try await ClientHealthCheck.ping(timeout: .seconds(2))
        let version = try Self.semanticVersion(from: health.apiServerVersion)
        return RuntimeVersionSummary(
            version: version,
            apiVersion: version
        )
    }

    static func semanticVersion(from releaseDescription: String) throws -> String {
        let value = releaseDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "container-apiserver version "
        let candidate: String
        if Self.isSemanticVersion(value) {
            candidate = value
        } else if value.hasPrefix(prefix),
                  let version = value.dropFirst(prefix.count).split(whereSeparator: { $0.isWhitespace }).first
        {
            candidate = String(version)
        } else {
            throw SystemAdapterError.invalidRuntimeVersion(releaseDescription)
        }
        guard Self.isSemanticVersion(candidate) else {
            throw SystemAdapterError.invalidRuntimeVersion(releaseDescription)
        }
        return candidate
    }

    private static func isSemanticVersion(_ value: String) -> Bool {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        return components.count == 3 && components.allSatisfy { component in
            !component.isEmpty && component.allSatisfy(\.isNumber)
        }
    }

    public func logs(
        _ options: LogOptions
    ) async throws -> AsyncThrowingStream<LogRecord, any Error> {
        try await logReader.logs(options)
    }

    public func diskUsage() async throws -> DiskUsageSummary {
        let usage = try await ClientDiskUsage.get()
        let reclaimable = saturatingSum([
            usage.containers.reclaimable,
            usage.images.reclaimable,
            usage.volumes.reclaimable
        ])
        return DiskUsageSummary(
            containersBytes: clampedInt64(usage.containers.sizeInBytes),
            imagesBytes: clampedInt64(usage.images.sizeInBytes),
            volumesBytes: clampedInt64(usage.volumes.sizeInBytes),
            reclaimableBytes: clampedInt64(reclaimable)
        )
    }

    private func saturatingSum(_ values: [UInt64]) -> UInt64 {
        values.reduce(0) { partial, value in
            let (result, overflow) = partial.addingReportingOverflow(value)
            return overflow ? .max : result
        }
    }

    private func clampedInt64(_ value: UInt64) -> Int64 {
        value > UInt64(Int64.max) ? Int64.max : Int64(value)
    }
}

public struct AppleUnifiedLogReader: UnifiedLogReading, Sendable {
    public static let subsystem = "com.apple.container"

    private let defaultLookback: TimeInterval
    private let pollInterval: Duration

    public init(defaultLookback: TimeInterval = 300, pollInterval: Duration = .milliseconds(500)) {
        self.defaultLookback = defaultLookback
        self.pollInterval = pollInterval
    }

    public func logs(
        _ options: LogOptions
    ) async throws -> AsyncThrowingStream<LogRecord, any Error> {
        if let tail = options.tail, tail < 0 {
            throw AppleUnifiedLogError.invalidTail
        }
        let start = options.since ?? Date(timeIntervalSinceNow: -defaultLookback)
        let pollInterval = pollInterval
        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    var cursor = UnifiedLogCursor(start: start)
                    var isInitial = true
                    repeat {
                        try Task.checkCancellation()
                        let records = try Self.recordsForPoll(
                            Self.snapshot(since: cursor.timestamp),
                            tail: options.tail,
                            isInitial: isInitial
                        )
                        isInitial = false
                        for record in cursor.freshRecords(records) {
                            continuation.yield(LogRecord(
                                timestamp: options.timestamps ? record.timestamp : nil,
                                stream: record.stream,
                                bytes: record.bytes
                            ))
                        }
                        guard options.follow else { break }
                        try await Task.sleep(for: pollInterval)
                    } while !Task.isCancelled
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func recordsForPoll(
        _ records: [LogRecord],
        tail: Int?,
        isInitial: Bool
    ) -> [LogRecord] {
        guard isInitial, let tail else {
            return records
        }
        return Array(records.suffix(tail))
    }

    private static func snapshot(since: Date) throws -> [LogRecord] {
        let store = try OSLogStore(scope: .system)
        let position = store.position(date: since)
        let predicate = NSPredicate(format: "subsystem == %@", subsystem)
        return try store.getEntries(at: position, matching: predicate).compactMap { entry in
            guard let entry = entry as? OSLogEntryLog else { return nil }
            return LogRecord(
                timestamp: entry.date,
                stream: entry.category.isEmpty ? entry.subsystem : entry.category,
                bytes: Data(entry.composedMessage.utf8)
            )
        }
    }
}

public enum AppleUnifiedLogError: Error, Equatable, Sendable {
    case invalidTail
}

private struct LogIdentity: Hashable, Sendable {
    let timestamp: Date?
    let stream: String
    let bytes: Data

    init(_ record: LogRecord) {
        timestamp = record.timestamp
        stream = record.stream
        bytes = record.bytes
    }
}

struct UnifiedLogCursor: Sendable {
    private(set) var timestamp: Date
    private var emittedAtTimestamp: [LogIdentity: Int] = [:]

    init(start: Date) {
        timestamp = start
    }

    mutating func freshRecords(_ records: [LogRecord]) -> [LogRecord] {
        var observedAtTimestamp: [LogIdentity: Int] = [:]
        var result: [LogRecord] = []
        result.reserveCapacity(records.count)
        for record in records {
            let recordTimestamp = record.timestamp ?? timestamp
            guard recordTimestamp >= timestamp else {
                continue
            }
            if recordTimestamp > timestamp {
                timestamp = recordTimestamp
                emittedAtTimestamp.removeAll(keepingCapacity: true)
                observedAtTimestamp.removeAll(keepingCapacity: true)
            }

            let identity = LogIdentity(record)
            let observedCount = observedAtTimestamp[identity, default: 0] + 1
            observedAtTimestamp[identity] = observedCount
            guard observedCount > emittedAtTimestamp[identity, default: 0] else {
                continue
            }
            result.append(record)
        }
        if !observedAtTimestamp.isEmpty {
            emittedAtTimestamp = observedAtTimestamp
        }
        return result
    }
}
