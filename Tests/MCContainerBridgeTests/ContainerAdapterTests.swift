import Foundation
@testable import MCContainerBridge
import MCModel
import Testing

@Suite("Container adapter")
struct ContainerAdapterTests {
    @Test func `create maps every behavior affecting field`() async throws {
        let backend = FakeContainerBackend(containers: [.fixture(id: "mapped")])
        let request = ContainerCreateRequest.fixture
        let adapter = ContainerAdapter(client: backend)

        _ = try await adapter.create(request)

        let mapped = try #require(await backend.createPlans.first)
        #expect(mapped.name == request.name)
        #expect(mapped.imageReference == request.imageReference)
        #expect(mapped.arguments == request.arguments)
        #expect(mapped.environment == request.environment)
        #expect(mapped.resources == request.resources)
        #expect(mapped.mounts == request.mounts)
        #expect(mapped.networks == request.networks)
        #expect(mapped.publishedPorts == request.publishedPorts)
        #expect(mapped.platform == request.platform)
        #expect(mapped.workingDirectory == request.workingDirectory)
        #expect(mapped.readOnlyRoot == request.readOnlyRoot)
        #expect(mapped.capabilitiesToAdd == request.capabilitiesToAdd)
        #expect(mapped.capabilitiesToDrop == request.capabilitiesToDrop)
        #expect(mapped.temporaryFilesystems == request.temporaryFilesystems)
        #expect(mapped.dnsServers == request.dnsServers)
        #expect(mapped.noDNS == request.noDNS)
        #expect(mapped.nestedVirtualization == request.nestedVirtualization)
        #expect(mapped.autoRemove == false)
    }

    @Test func `batch mutation preserves order and partial failures`() async throws {
        let backend = FakeContainerBackend(
            containers: [.fixture(id: "a"), .fixture(id: "b")],
            deleteFailures: ["b"]
        )
        let adapter = ContainerAdapter(client: backend)

        let results = try await adapter.delete(ids: ["a", "b"], force: true)

        #expect(results.map(\.id) == ["a", "b"])
        #expect(results.map(\.succeeded) == [true, false])
        #expect(results[1].error?.redactedDetails == "TestBackendError")
        #expect(await backend.deletedIDs == ["a", "b"])
        #expect(await backend.deleteForceValues == [true, true])
    }

    @Test func `ambiguous prefix fails before mutation`() async throws {
        let backend = FakeContainerBackend(containers: [
            .fixture(id: "api-one"),
            .fixture(id: "api-two")
        ])
        let adapter = ContainerAdapter(client: backend)

        let results = try await adapter.kill(ids: ["api"], signal: "SIGTERM")

        #expect(results.count == 1)
        #expect(results[0].id == "api")
        #expect(results[0].succeeded == false)
        #expect(results[0].error?.code == "container.identifier.ambiguous")
        #expect(await backend.killedIDs.isEmpty)
    }

    @Test func `unique prefix resolves once before mutation`() async throws {
        let backend = FakeContainerBackend(containers: [
            .fixture(id: "unique-container"),
            .fixture(id: "other")
        ])
        let adapter = ContainerAdapter(client: backend)

        let results = try await adapter.stop(ids: ["unique"], timeout: .seconds(7))

        #expect(results == [BatchItemResult(id: "unique", succeeded: true)])
        #expect(await backend.stoppedIDs == ["unique-container"])
        #expect(await backend.stopTimeouts == [.seconds(7)])
    }

    @Test func `run composes create bootstrap wait and remove in one lock`() async throws {
        let process = FakeContainerProcessTransport(id: "run-init", exitCode: 17)
        let backend = FakeContainerBackend(
            containers: [.fixture(id: "demo")],
            bootstrapProcess: process
        )
        let adapter = ContainerAdapter(client: backend)

        let result = try await adapter.run(
            ContainerRunRequest(create: .fixture, attach: true, removeAfterExit: true)
        )

        #expect(result.container.id == "demo")
        #expect(result.processExit == ProcessExit(code: 17))
        #expect(result.cleanupError == nil)
        #expect(await backend.events == ["create:demo", "bootstrap:demo", "delete:demo"])
        #expect(await process.startedCount == 1)
        #expect(await process.waitCount == 1)
        #expect(await backend.createPlans.first?.autoRemove == true)
    }

    @Test func `run reports cleanup failure separately from process exit`() async throws {
        let backend = FakeContainerBackend(
            containers: [.fixture(id: "demo")],
            deleteFailures: ["demo"],
            bootstrapProcess: FakeContainerProcessTransport(id: "run-init", exitCode: 0)
        )
        let adapter = ContainerAdapter(client: backend)

        let result = try await adapter.run(
            ContainerRunRequest(create: .fixture, attach: true, removeAfterExit: true)
        )

        #expect(result.processExit == ProcessExit(code: 0))
        #expect(result.cleanupError?.code == "container.delete.failed")
        #expect(result.cleanupError?.redactedDetails == "TestBackendError")
    }

    @Test func `run accepts native auto remove winning the cleanup race`() async throws {
        let backend = FakeContainerBackend(
            containers: [.fixture(id: "demo")],
            deleteFailures: ["demo"],
            removeBeforeDeleteFailure: ["demo"],
            bootstrapProcess: FakeContainerProcessTransport(id: "run-init", exitCode: 0)
        )
        let adapter = ContainerAdapter(client: backend)

        let result = try await adapter.run(
            ContainerRunRequest(create: .fixture, attach: true, removeAfterExit: true)
        )

        #expect(result.processExit == ProcessExit(code: 0))
        #expect(result.cleanupError == nil)
        #expect(await backend.events == ["create:demo", "bootstrap:demo", "delete:demo"])
    }

    @Test func `copy rejects unsupported endpoint pairs before backend access`() async {
        let backend = FakeContainerBackend(containers: [.fixture(id: "demo")])
        let adapter = ContainerAdapter(client: backend)

        await #expect(throws: ContainerAdapterError.unsupportedCopyEndpoints) {
            try await adapter.copy(
                CopyRequest(
                    source: .local(URL(fileURLWithPath: "/private/tmp/source")),
                    destination: .local(URL(fileURLWithPath: "/private/tmp/destination"))
                )
            )
        }

        #expect(await backend.copyEvents.isEmpty)
    }

    @Test func `prune removes stopped non-machine containers and totals only successful bytes`() async throws {
        let backend = FakeContainerBackend(
            containers: [
                .fixture(id: "stopped-a", state: .stopped),
                .fixture(id: "running", state: .running),
                .fixture(id: "stopped-b", state: .stopped)
            ],
            deleteFailures: ["stopped-b"],
            diskUsage: ["stopped-a": 10, "stopped-b": 20]
        )
        let adapter = ContainerAdapter(client: backend)

        let result = try await adapter.prune()

        #expect(result == PruneResult(deletedIDs: ["stopped-a"], reclaimedBytes: 10))
    }

    @Test func `binary log tail handles a final unterminated line`() {
        let bytes = Data([0xFF, 0x0A, 0x00, 0x80])

        let result = AppleContainerBackend.tailData(bytes, lines: 1)

        #expect(result == Data([0x00, 0x80]))
    }

    @Test func `log timestamp option controls record metadata without changing bytes`() {
        let now = Date(timeIntervalSince1970: 1234)
        let bytes = Data([0x00, 0xFF])

        let timestamped = AppleContainerBackend.logRecord(
            bytes,
            timestamps: true,
            now: now
        )
        let raw = AppleContainerBackend.logRecord(
            bytes,
            timestamps: false,
            now: now
        )

        #expect(timestamped == LogRecord(timestamp: now, stream: "stdio", bytes: bytes))
        #expect(raw == LogRecord(timestamp: nil, stream: "stdio", bytes: bytes))
    }

    @Test func `stats derives CPU fraction from monotonic usage samples`() async throws {
        let firstDate = Date(timeIntervalSince1970: 10)
        let backend = FakeContainerBackend(
            containers: [.fixture(id: "demo")],
            statsValues: [
                BackendContainerStats(
                    id: "demo",
                    timestamp: firstDate,
                    cpuUsageMicroseconds: 100,
                    memoryBytes: 1000,
                    networkReceiveBytes: 2000,
                    networkTransmitBytes: 3000
                ),
                BackendContainerStats(
                    id: "demo",
                    timestamp: firstDate.addingTimeInterval(1),
                    cpuUsageMicroseconds: 500_100,
                    memoryBytes: 2000,
                    networkReceiveBytes: 4000,
                    networkTransmitBytes: 6000
                )
            ]
        )
        let adapter = ContainerAdapter(client: backend, statsInterval: .milliseconds(1))
        let stream = try await adapter.stats(id: "demo")

        let samples = try await first(2, from: stream)

        #expect(samples.count == 2)
        #expect(samples[0].cpuFraction == 0)
        #expect(abs(samples[1].cpuFraction - 0.5) < 0.000_001)
        #expect(samples[1].memoryBytes == 2000)
        #expect(samples[1].networkReceiveBytes == 4000)
        #expect(samples[1].networkTransmitBytes == 6000)
    }

    @Test func `remaining container entrypoints delegate through typed plans`() async throws {
        let process = FakeContainerProcessTransport(id: "init", exitCode: 0)
        let backend = FakeContainerBackend(
            containers: [.fixture(id: "demo")],
            bootstrapProcess: process
        )
        let adapter = ContainerAdapter(client: backend, processID: { "stable-process" })

        #expect(try await adapter.list().map(\.id) == ["demo"])
        #expect(try await adapter.inspect(id: "dem").summary.id == "demo")
        #expect(try await adapter.start(ids: ["dem"]).first?.succeeded == true)
        let session = try await adapter.exec(
            ProcessRequest(
                resourceID: "dem",
                arguments: ["/bin/echo", "hello"],
                environment: [KeyValue(key: "A", value: "B")],
                workingDirectory: "/workspace",
                user: "1000:1000",
                tty: true,
                interactive: true
            )
        )
        try await session.detach()
        try await adapter.export(
            id: "dem",
            destination: URL(fileURLWithPath: "/private/tmp/MacContainer-export-test.tar")
        )
        _ = try await first(1, from: adapter.logs(id: "dem", options: LogOptions()))
        try await adapter.copy(
            CopyRequest(
                source: .local(URL(fileURLWithPath: "/private/tmp/source")),
                destination: .container(id: "dem", path: "/workspace/source")
            )
        )
        try await adapter.copy(
            CopyRequest(
                source: .container(id: "dem", path: "/workspace/result"),
                destination: .local(URL(fileURLWithPath: "/private/tmp/result"))
            )
        )

        let plan = try #require(await backend.processPlans.first)
        #expect(plan.containerID == "demo")
        #expect(plan.processID == "stable-process")
        #expect(plan.arguments == ["/bin/echo", "hello"])
        #expect(plan.environment == [KeyValue(key: "A", value: "B")])
        #expect(plan.workingDirectory == "/workspace")
        #expect(plan.user == "1000:1000")
        #expect(plan.terminal)
        #expect(plan.interactive)
        #expect(await backend.exportedIDs == ["demo"])
        #expect(await backend.copyEvents.count == 2)
    }

    private func first<Element: Sendable>(
        _ count: Int,
        from stream: AsyncThrowingStream<Element, any Error>
    ) async throws -> [Element] {
        var result: [Element] = []
        for try await element in stream {
            result.append(element)
            if result.count == count {
                break
            }
        }
        return result
    }
}

private extension ContainerCreateRequest {
    static let fixture = ContainerCreateRequest(
        name: "demo",
        imageReference: "registry.example/demo:latest",
        arguments: ["serve", "--port", "8080"],
        environment: [KeyValue(key: "MODE", value: "test")],
        resources: RuntimeResources(cpuCount: 3, memoryBytes: 3_221_225_472, diskBytes: 20_000_000_000),
        mounts: [Mount(source: "/private/tmp/source,with-comma", destination: "/workspace", readOnly: true)],
        networks: ["frontend", "backend"],
        publishedPorts: [PortMapping(hostAddress: "127.0.0.1", hostPort: 8080, containerPort: 80, protocolName: "tcp")],
        platform: "linux/arm64",
        workingDirectory: "/workspace",
        readOnlyRoot: true,
        capabilitiesToAdd: ["CAP_NET_BIND_SERVICE"],
        capabilitiesToDrop: ["CAP_SYS_ADMIN"],
        temporaryFilesystems: ["/run", "/tmp"],
        dnsServers: ["1.1.1.1", "8.8.8.8"],
        noDNS: false,
        nestedVirtualization: true
    )
}

private extension ContainerDetail {
    static func fixture(id: String, state: RuntimeResourceState = .running) -> ContainerDetail {
        ContainerDetail(
            summary: ContainerSummary(
                id: id,
                name: id,
                imageReference: "example/image:latest",
                state: state,
                createdAt: Date(timeIntervalSince1970: 1)
            ),
            resources: RuntimeResources(cpuCount: 2, memoryBytes: 1_073_741_824)
        )
    }
}

private enum TestBackendError: Error {
    case failed
}

private actor FakeContainerBackend: ContainerBackend {
    private var containers: [ContainerDetail]
    private let deleteFailures: Set<String>
    private let removeBeforeDeleteFailure: Set<String>
    private let bootstrapProcess: FakeContainerProcessTransport
    private let diskUsageValues: [String: Int64]
    private var statsValues: [BackendContainerStats]

    private(set) var createPlans: [ContainerCreatePlan] = []
    private(set) var deletedIDs: [String] = []
    private(set) var deleteForceValues: [Bool] = []
    private(set) var killedIDs: [String] = []
    private(set) var stoppedIDs: [String] = []
    private(set) var stopTimeouts: [Duration?] = []
    private(set) var events: [String] = []
    private(set) var copyEvents: [String] = []
    private(set) var processPlans: [ContainerProcessPlan] = []
    private(set) var exportedIDs: [String] = []

    init(
        containers: [ContainerDetail],
        deleteFailures: Set<String> = [],
        removeBeforeDeleteFailure: Set<String> = [],
        bootstrapProcess: FakeContainerProcessTransport = FakeContainerProcessTransport(id: "init", exitCode: 0),
        diskUsage: [String: Int64] = [:],
        statsValues: [BackendContainerStats] = []
    ) {
        self.containers = containers
        self.deleteFailures = deleteFailures
        self.removeBeforeDeleteFailure = removeBeforeDeleteFailure
        self.bootstrapProcess = bootstrapProcess
        diskUsageValues = diskUsage
        self.statsValues = statsValues
    }

    func create(_ plan: ContainerCreatePlan) async throws -> ContainerDetail {
        createPlans.append(plan)
        let detail = containers.first(where: { $0.summary.id == plan.name }) ?? .fixture(id: plan.name)
        events.append("create:\(detail.summary.id)")
        return detail
    }

    func list() async throws -> [ContainerDetail] {
        containers
    }

    func get(id: String) async throws -> ContainerDetail {
        guard let result = containers.first(where: { $0.summary.id == id }) else {
            throw TestBackendError.failed
        }
        return result
    }

    func bootstrap(id: String, attach _: Bool) async throws -> any ContainerProcessTransport {
        events.append("bootstrap:\(id)")
        return bootstrapProcess
    }

    func stop(id: String, timeout: Duration?) async throws {
        stoppedIDs.append(id)
        stopTimeouts.append(timeout)
    }

    func kill(id: String, signal _: String) async throws {
        killedIDs.append(id)
    }

    func delete(id: String, force: Bool) async throws {
        deletedIDs.append(id)
        deleteForceValues.append(force)
        events.append("delete:\(id)")
        if deleteFailures.contains(id) {
            if removeBeforeDeleteFailure.contains(id) {
                containers.removeAll { $0.summary.id == id }
            }
            throw TestBackendError.failed
        }
    }

    func createProcess(_ plan: ContainerProcessPlan) async throws -> any ContainerProcessTransport {
        processPlans.append(plan)
        return FakeContainerProcessTransport(id: plan.processID, exitCode: 0)
    }

    func logs(id _: String, options _: LogOptions) async throws -> AsyncThrowingStream<LogRecord, any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func stats(id: String) async throws -> BackendContainerStats {
        if !statsValues.isEmpty {
            if statsValues.count == 1 {
                return statsValues[0]
            }
            return statsValues.removeFirst()
        }
        return BackendContainerStats(
            id: id,
            timestamp: Date(),
            cpuUsageMicroseconds: 0,
            memoryBytes: 0,
            networkReceiveBytes: 0,
            networkTransmitBytes: 0
        )
    }

    func copyIn(id: String, source: URL, destination: String) async throws {
        copyEvents.append("in:\(id):\(source.path):\(destination)")
    }

    func copyOut(id: String, source: String, destination: URL) async throws {
        copyEvents.append("out:\(id):\(source):\(destination.path)")
    }

    func export(id: String, destination _: URL) async throws {
        exportedIDs.append(id)
    }

    func diskUsage(id: String) async throws -> Int64 {
        diskUsageValues[id, default: 0]
    }
}

private actor FakeContainerProcessTransport: ContainerProcessTransport {
    nonisolated let id: String
    nonisolated let terminal = false
    nonisolated let standardInput: FileHandle? = nil
    nonisolated let standardOutput: FileHandle? = nil
    nonisolated let standardError: FileHandle? = nil
    private let exitCode: Int32
    private(set) var startedCount = 0
    private(set) var waitCount = 0

    init(id: String, exitCode: Int32) {
        self.id = id
        self.exitCode = exitCode
    }

    func start() async throws {
        startedCount += 1
    }

    func resize(columns _: Int, rows _: Int) async throws {}
    func send(_ data: Data) async throws {}

    func wait() async throws -> Int32 {
        waitCount += 1
        return exitCode
    }

    func terminate(signal _: String) async throws {}
    func detach() async throws {}
}
