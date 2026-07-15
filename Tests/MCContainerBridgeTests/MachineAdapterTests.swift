import Foundation
@testable import MCContainerBridge
import MCModel
import Testing

@Suite("Machine adapter")
struct MachineAdapterTests {
    @Test func `all nine operations preserve stable mappings`() async throws {
        let existing = MachineDetail.fixture(id: "existing-machine")
        let process = FakeMachineProcessTransport(id: "machine-process", exitCode: 23)
        let backend = FakeMachineBackend(machines: [existing], process: process)
        let kernelURL = URL(fileURLWithPath: "/private/tmp/mc-kernels/kernel-1")
        let adapter = MachineAdapter(
            client: backend,
            capabilities: FakeMachineCapabilities(nestedVirtualizationSupported: true),
            kernels: FakeMachineKernelResolver(values: ["kernel-1": kernelURL]),
            processID: { "stable-process" }
        )
        let create = MachineCreateRequest(
            name: "builder",
            imageReference: "ghcr.io/example/machine:1",
            resources: RuntimeResources(cpuCount: 4, memoryBytes: 4 * 1024 * 1024 * 1024),
            homeMount: "rw",
            homeSharingConsent: HomeSharingConsent(token: UUID()),
            kernelIdentifier: "kernel-1",
            nestedVirtualization: true
        )
        let run = MachineRunRequest(
            create: MachineCreateRequest(
                name: "runner",
                imageReference: "ghcr.io/example/machine:1",
                resources: RuntimeResources(cpuCount: 2, memoryBytes: 2 * 1024 * 1024 * 1024)
            ),
            process: ProcessRequest(
                resourceID: "must-not-leak",
                arguments: ["/bin/echo", "hello"],
                environment: [KeyValue(key: "LANG", value: "C")],
                workingDirectory: "/workspace",
                user: "1000:1000",
                tty: true,
                interactive: true
            )
        )

        _ = try await adapter.create(create)
        let session = try await adapter.run(run)
        #expect(try await session.wait() == ProcessExit(code: 23))
        _ = try await adapter.list()
        _ = try await adapter.inspect(id: "existing")
        _ = try await adapter.set(
            id: "existing",
            request: MachineSetRequest(
                resources: RuntimeResources(cpuCount: 6, memoryBytes: 6 * 1024 * 1024 * 1024),
                homeMount: "ro",
                homeSharingConsent: HomeSharingConsent(token: UUID()),
                nestedVirtualization: true
            )
        )
        try await adapter.setDefault(id: "existing")
        let records = try await collect(adapter.logs(id: "existing", options: LogOptions()))
        let stopped = try await adapter.stop(ids: ["existing"], force: true)
        let deleted = try await adapter.delete(ids: ["existing"], force: true)

        let createPlan = try #require(await backend.createPlans.first)
        #expect(createPlan.name == create.name)
        #expect(createPlan.imageReference == create.imageReference)
        #expect(createPlan.resources == create.resources)
        #expect(createPlan.homeMount == "rw")
        #expect(createPlan.networks.isEmpty)
        #expect(createPlan.kernelURL == kernelURL)
        #expect(createPlan.nestedVirtualization)
        let processPlan = try #require(await backend.processPlans.first)
        #expect(processPlan.machineID == "runner")
        #expect(processPlan.processID == "stable-process")
        #expect(processPlan.arguments == run.process.arguments)
        #expect(processPlan.environment == run.process.environment)
        #expect(processPlan.workingDirectory == run.process.workingDirectory)
        #expect(processPlan.user == run.process.user)
        #expect(processPlan.terminal == run.process.tty)
        #expect(processPlan.interactive == run.process.interactive)
        let setPlan = try #require(await backend.setPlans.first)
        #expect(setPlan.resources?.cpuCount == 6)
        #expect(setPlan.homeMount == "ro")
        #expect(setPlan.nestedVirtualization == true)
        #expect(records.map(\.bytes) == [Data("machine-log".utf8)])
        #expect(stopped == [BatchItemResult(id: "existing", succeeded: true)])
        #expect(deleted == [BatchItemResult(id: "existing", succeeded: true)])
        #expect(await backend.operationIDs == [
            "create:builder", "create:runner", "boot:runner", "process:runner",
            "list", "list", "inspect:existing-machine", "list", "set:existing-machine",
            "list", "default:existing-machine", "list", "logs:existing-machine",
            "list", "stop:existing-machine", "list", "delete:existing-machine"
        ])
    }

    @Test func `home sharing consent is required consumed once and never reaches backend`() async throws {
        let backend = FakeMachineBackend()
        let adapter = MachineAdapter(client: backend)
        let token = UUID()
        let first = MachineCreateRequest.fixture(
            name: "shared-one",
            homeMount: "ro",
            consent: HomeSharingConsent(token: token)
        )

        _ = try await adapter.create(first)
        await #expect(throws: MachineAdapterError.homeSharingConsentRequired) {
            try await adapter.create(
                .fixture(name: "missing", homeMount: "rw", consent: nil)
            )
        }
        await #expect(throws: MachineAdapterError.homeSharingConsentAlreadyUsed) {
            try await adapter.create(
                .fixture(
                    name: "shared-two",
                    homeMount: "rw",
                    consent: HomeSharingConsent(token: token)
                )
            )
        }

        #expect(await backend.createPlans.map(\.name) == ["shared-one"])
        #expect(await backend.createPlans.allSatisfy { $0.homeMount == "ro" })
    }

    @Test func `unsupported machine capabilities fail before backend access`() async {
        let backend = FakeMachineBackend()
        let adapter = MachineAdapter(
            client: backend,
            capabilities: FakeMachineCapabilities(nestedVirtualizationSupported: false)
        )

        await #expect(throws: MachineAdapterError.nestedVirtualizationUnsupported) {
            try await adapter.create(.fixture(name: "nested", nestedVirtualization: true))
        }
        await #expect(throws: MachineAdapterError.customNetworksUnsupported) {
            try await adapter.create(.fixture(name: "networked", networks: ["custom"]))
        }
        await #expect(throws: MachineAdapterError.customDiskUnsupported) {
            try await adapter.create(
                .fixture(
                    name: "disked",
                    resources: RuntimeResources(
                        cpuCount: 2,
                        memoryBytes: 2 * 1024 * 1024 * 1024,
                        diskBytes: 20 * 1024 * 1024 * 1024
                    )
                )
            )
        }
        await #expect(throws: MachineAdapterError.imageRequired) {
            try await adapter.create(.fixture(name: "imageless", imageReference: nil))
        }

        #expect(await backend.operationIDs.isEmpty)
    }

    @Test func `batch mutations preserve order and redact backend failures`() async throws {
        let backend = FakeMachineBackend(
            machines: [.fixture(id: "alpha"), .fixture(id: "beta")],
            deleteFailures: ["beta"]
        )
        let adapter = MachineAdapter(client: backend)

        let results = try await adapter.delete(ids: ["alpha", "beta"], force: true)

        #expect(results.map(\.id) == ["alpha", "beta"])
        #expect(results.map(\.succeeded) == [true, false])
        #expect(results[1].error?.code == "machine.delete.failed")
        #expect(results[1].error?.redactedDetails == "FakeMachineError")
        #expect(await backend.deletedIDs == ["alpha", "beta"])
    }

    @Test func `machine process preserves binary IO resize and exit behavior`() async throws {
        let transport = FakeMachineProcessTransport(id: "process", exitCode: 137)
        let backend = FakeMachineBackend(process: transport)
        let adapter = MachineAdapter(client: backend, processID: { "process" })
        let session = try await adapter.run(
            MachineRunRequest(
                create: .fixture(name: "interactive"),
                process: ProcessRequest(
                    resourceID: "interactive",
                    arguments: ["/bin/sh"],
                    tty: true,
                    interactive: true
                )
            )
        )
        let outputTask = Task { try await collect(session.output) }
        let bytes = Data([0x00, 0x80, 0xFF])

        try await session.send(bytes)
        try await session.resize(columns: 0, rows: 2000)
        try await transport.writeOutput(bytes)
        await transport.finishOutput()
        let output = try await outputTask.value
        let exit = try await session.wait()

        #expect(output.compactMap(\.terminalBytes).joined() == bytes)
        #expect(await transport.sentData == [bytes])
        #expect(await transport.resizeRequests == [MachineTerminalSize(columns: 1, rows: 1000)])
        #expect(exit == ProcessExit(code: 137))
        #expect(await transport.startedCount == 1)
    }
}

private func collect<T: Sendable>(_ stream: AsyncThrowingStream<T, any Error>) async throws -> [T] {
    var values: [T] = []
    for try await value in stream {
        values.append(value)
    }
    return values
}

private struct FakeMachineCapabilities: MachineCapabilityChecking {
    let nestedVirtualizationSupported: Bool
}

private struct FakeMachineKernelResolver: MachineKernelResolving {
    let values: [String: URL]

    func resolve(identifier: String) async throws -> URL {
        guard let value = values[identifier] else {
            throw FakeMachineError.notFound
        }
        return value
    }
}

private actor FakeMachineBackend: MachineBackend {
    private var machines: [MachineDetail]
    private let process: FakeMachineProcessTransport
    private let deleteFailures: Set<String>

    private(set) var operationIDs: [String] = []
    private(set) var createPlans: [MachineCreatePlan] = []
    private(set) var processPlans: [MachineProcessPlan] = []
    private(set) var setPlans: [MachineSetPlan] = []
    private(set) var deletedIDs: [String] = []

    init(
        machines: [MachineDetail] = [],
        process: FakeMachineProcessTransport = FakeMachineProcessTransport(id: "process"),
        deleteFailures: Set<String> = []
    ) {
        self.machines = machines
        self.process = process
        self.deleteFailures = deleteFailures
    }

    func create(_ plan: MachineCreatePlan) async throws -> MachineDetail {
        operationIDs.append("create:\(plan.name)")
        createPlans.append(plan)
        let detail = MachineDetail(
            summary: MachineSummary(
                id: plan.name,
                name: plan.name,
                state: .stopped,
                resources: plan.resources
            ),
            imageReference: plan.imageReference,
            homeMount: plan.homeMount,
            networks: plan.networks,
            kernelIdentifier: plan.kernelURL?.path,
            nestedVirtualization: plan.nestedVirtualization
        )
        machines.append(detail)
        return detail
    }

    func boot(id: String) async throws -> MachineDetail {
        operationIDs.append("boot:\(id)")
        guard let detail = machines.first(where: { $0.summary.id == id }) else {
            throw FakeMachineError.notFound
        }
        return MachineDetail(
            summary: MachineSummary(
                id: detail.summary.id,
                name: detail.summary.name,
                state: .running,
                resources: detail.summary.resources,
                isDefault: detail.summary.isDefault
            ),
            imageReference: detail.imageReference,
            homeMount: detail.homeMount,
            networks: detail.networks,
            kernelIdentifier: detail.kernelIdentifier,
            nestedVirtualization: detail.nestedVirtualization
        )
    }

    func list() async throws -> [MachineDetail] {
        operationIDs.append("list")
        return machines
    }

    func inspect(id: String) async throws -> MachineDetail {
        operationIDs.append("inspect:\(id)")
        guard let detail = machines.first(where: { $0.summary.id == id }) else {
            throw FakeMachineError.notFound
        }
        return detail
    }

    func set(id: String, plan: MachineSetPlan) async throws -> MachineDetail {
        operationIDs.append("set:\(id)")
        setPlans.append(plan)
        return try inspectWithoutRecording(id: id)
    }

    func setDefault(id: String) async throws {
        operationIDs.append("default:\(id)")
    }

    func logs(
        id: String,
        options _: LogOptions
    ) async throws -> AsyncThrowingStream<LogRecord, any Error> {
        operationIDs.append("logs:\(id)")
        return AsyncThrowingStream { continuation in
            continuation.yield(LogRecord(stream: "stdio", bytes: Data("machine-log".utf8)))
            continuation.finish()
        }
    }

    func stop(id: String, force _: Bool) async throws {
        operationIDs.append("stop:\(id)")
    }

    func delete(id: String, force _: Bool) async throws {
        operationIDs.append("delete:\(id)")
        deletedIDs.append(id)
        if deleteFailures.contains(id) {
            throw FakeMachineError.rejected
        }
    }

    func createProcess(_ plan: MachineProcessPlan) async throws -> any ContainerProcessTransport {
        operationIDs.append("process:\(plan.machineID)")
        processPlans.append(plan)
        return process
    }

    private func inspectWithoutRecording(id: String) throws -> MachineDetail {
        guard let detail = machines.first(where: { $0.summary.id == id }) else {
            throw FakeMachineError.notFound
        }
        return detail
    }
}

private enum FakeMachineError: Error {
    case notFound
    case rejected
}

private struct MachineTerminalSize: Equatable, Sendable {
    let columns: Int
    let rows: Int
}

private actor FakeMachineProcessTransport: ContainerProcessTransport {
    nonisolated let id: String
    nonisolated let terminal = true
    nonisolated let standardInput: FileHandle? = nil
    nonisolated let standardOutput: FileHandle?
    nonisolated let standardError: FileHandle? = nil

    private let outputPipe = Pipe()
    private let exitCode: Int32
    private(set) var sentData: [Data] = []
    private(set) var resizeRequests: [MachineTerminalSize] = []
    private(set) var startedCount = 0

    init(id: String, exitCode: Int32 = 0) {
        self.id = id
        self.exitCode = exitCode
        standardOutput = outputPipe.fileHandleForReading
    }

    func start() async throws {
        startedCount += 1
    }

    func resize(columns: Int, rows: Int) async throws {
        resizeRequests.append(MachineTerminalSize(columns: columns, rows: rows))
    }

    func send(_ data: Data) async throws {
        sentData.append(data)
    }

    func wait() async throws -> Int32 {
        exitCode
    }

    func terminate(signal _: String) async throws {}
    func detach() async throws {}

    func writeOutput(_ data: Data) throws {
        try outputPipe.fileHandleForWriting.write(contentsOf: data)
    }

    func finishOutput() {
        try? outputPipe.fileHandleForWriting.close()
    }
}

private extension MachineCreateRequest {
    static func fixture(
        name: String,
        imageReference: String? = "ghcr.io/example/machine:1",
        resources: RuntimeResources = RuntimeResources(
            cpuCount: 2,
            memoryBytes: 2 * 1024 * 1024 * 1024
        ),
        homeMount: String = "none",
        consent: HomeSharingConsent? = nil,
        networks: [String] = [],
        nestedVirtualization: Bool = false
    ) -> Self {
        Self(
            name: name,
            imageReference: imageReference,
            resources: resources,
            homeMount: homeMount,
            homeSharingConsent: consent,
            networks: networks,
            nestedVirtualization: nestedVirtualization
        )
    }
}

private extension MachineDetail {
    static func fixture(id: String) -> Self {
        Self(
            summary: MachineSummary(
                id: id,
                name: id,
                state: .stopped,
                resources: RuntimeResources(
                    cpuCount: 2,
                    memoryBytes: 2 * 1024 * 1024 * 1024
                )
            ),
            imageReference: "ghcr.io/example/machine:1",
            networks: ["default"]
        )
    }
}

private extension ProcessOutputChunk {
    var terminalBytes: Data? {
        guard case let .terminal(data) = self else { return nil }
        return data
    }
}

private extension [Data] {
    func joined() -> Data {
        reduce(into: Data()) { $0.append($1) }
    }
}
