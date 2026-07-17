import Foundation
@testable import MCContainerBridge
import MCModel
import Testing

@Suite("System adapter")
struct SystemAdapterTests {
    @Test func `all system operations use the direct backend`() async throws {
        let backend = FakeSystemRuntimeBackend()
        let adapter = SystemAdapter(backend: backend)

        #expect(try await adapter.start(.init(healthTimeoutSeconds: 9)) == .init(state: .running))
        #expect(try await adapter.status() == .init(state: .running, activeContainers: 2, activeMachines: 1))
        #expect(try await adapter.version() == .init(version: "1.1.0", apiVersion: "1.1.0"))
        #expect(try await adapter.diskUsage() == .init(
            containersBytes: 10,
            imagesBytes: 20,
            volumesBytes: 30,
            reclaimableBytes: 6
        ))
        let records = try await collect(adapter.logs(.init(tail: 1)))
        #expect(records.map(\.bytes) == [Data("native-log".utf8)])
        #expect(try await adapter.stop(.init(stopActiveWorkloads: true, timeoutSeconds: 7)) == .init(state: .stopped))

        #expect(await backend.startTimeouts == [.seconds(9)])
        #expect(await backend.stopRequests == [.init(stopActiveWorkloads: true, timeout: .seconds(7))])
    }

    @Test func `invalid lifecycle timeouts fail before backend access`() async {
        let backend = FakeSystemRuntimeBackend()
        let adapter = SystemAdapter(backend: backend)

        await #expect(throws: SystemAdapterError.invalidTimeout) {
            try await adapter.start(.init(healthTimeoutSeconds: 0))
        }
        await #expect(throws: SystemAdapterError.invalidTimeout) {
            try await adapter.stop(.init(timeoutSeconds: -1))
        }
        #expect(await backend.startTimeouts.isEmpty)
        #expect(await backend.stopRequests.isEmpty)
    }

    @Test func `an unavailable service reports stopped without hiding cancellation`() async throws {
        let backend = FakeSystemRuntimeBackend(health: nil)
        let adapter = SystemAdapter(backend: backend)
        #expect(try await adapter.status() == .init(state: .stopped))
    }

    @Test func `an explicitly unhealthy service reports stopped`() async throws {
        let backend = FakeSystemRuntimeBackend(health: .init(healthy: false, version: "1.1.0"))
        let adapter = SystemAdapter(backend: backend)

        #expect(try await adapter.status() == .init(state: .stopped))
    }

    @Test func `Apple runtime version normalizes the upstream release description`() throws {
        #expect(try AppleSystemRuntimeBackend.semanticVersion(
            from: "container-apiserver version 1.1.0 (build: release, commit: abc123)"
        ) == "1.1.0")
        #expect(try AppleSystemRuntimeBackend.semanticVersion(from: "1.1.0") == "1.1.0")
    }

    @Test func `Apple runtime version rejects malformed upstream output`() {
        #expect(throws: SystemAdapterError.invalidRuntimeVersion("container-apiserver is current")) {
            try AppleSystemRuntimeBackend.semanticVersion(from: "container-apiserver is current")
        }
        #expect(throws: SystemAdapterError.invalidRuntimeVersion("1.1")) {
            try AppleSystemRuntimeBackend.semanticVersion(from: "1.1")
        }
    }

    @Test func `tail applies only to the initial unified log snapshot`() {
        let records = (0 ..< 5).map { index in
            LogRecord(
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                stream: "system",
                bytes: Data("record-\(index)".utf8)
            )
        }

        #expect(AppleUnifiedLogReader.recordsForPoll(records, tail: 2, isInitial: true) == Array(records.suffix(2)))
        #expect(AppleUnifiedLogReader.recordsForPoll(records, tail: 2, isInitial: false) == records)
    }

    @Test func `unified log cursor preserves duplicate records without replaying old entries`() {
        let timestamp = Date(timeIntervalSince1970: 10)
        let duplicate = LogRecord(
            timestamp: timestamp,
            stream: "system",
            bytes: Data("same".utf8)
        )
        let distinct = LogRecord(
            timestamp: timestamp,
            stream: "system",
            bytes: Data("different".utf8)
        )
        var cursor = UnifiedLogCursor(start: Date(timeIntervalSince1970: 0))

        #expect(cursor.freshRecords([duplicate, duplicate]) == [duplicate, duplicate])
        #expect(cursor.freshRecords([duplicate, duplicate, duplicate, distinct]) == [duplicate, distinct])
    }

    private func collect(
        _ stream: AsyncThrowingStream<LogRecord, any Error>
    ) async throws -> [LogRecord] {
        var values: [LogRecord] = []
        for try await value in stream {
            values.append(value)
        }
        return values
    }
}

private actor FakeSystemRuntimeBackend: SystemRuntimeBackend {
    struct StopRequest: Equatable, Sendable {
        let stopActiveWorkloads: Bool
        let timeout: Duration
    }

    private let configuredHealth: RuntimeHealth?
    var startTimeouts: [Duration] = []
    var stopRequests: [StopRequest] = []

    init(health: RuntimeHealth? = .init(healthy: true, version: "1.1.0")) {
        configuredHealth = health
    }

    func start(timeout: Duration) async throws {
        startTimeouts.append(timeout)
    }

    func stop(stopActiveWorkloads: Bool, timeout: Duration) async throws {
        stopRequests.append(.init(stopActiveWorkloads: stopActiveWorkloads, timeout: timeout))
    }

    func health(timeout _: Duration) async throws -> RuntimeHealth? {
        configuredHealth
    }

    func inventory() async throws -> WorkloadInventory {
        configuredHealth == nil
            ? .empty
            : .init(activeContainerIDs: ["one", "two"], activeMachineIDs: ["vm"])
    }

    func version() async throws -> RuntimeVersionSummary {
        .init(version: "1.1.0", apiVersion: "1.1.0")
    }

    func logs(_ options: LogOptions) async throws -> AsyncThrowingStream<LogRecord, any Error> {
        #expect(options.tail == 1)
        return AsyncThrowingStream { continuation in
            continuation.yield(.init(stream: "unified", bytes: Data("native-log".utf8)))
            continuation.finish()
        }
    }

    func diskUsage() async throws -> DiskUsageSummary {
        .init(containersBytes: 10, imagesBytes: 20, volumesBytes: 30, reclaimableBytes: 6)
    }
}
