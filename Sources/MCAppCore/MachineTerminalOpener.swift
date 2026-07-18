import Foundation
import MCContainerBridge
import MCModel

public protocol MachineTerminalOpening: Sendable {
    func open(machineID: String) async throws -> any ProcessSession
}

public protocol ContainerTerminalOpening: Sendable {
    func open(containerID: String) async throws -> any ProcessSession
}

public struct ProductionContainerTerminalOpener: ContainerTerminalOpening, Sendable {
    private let bridge: any RuntimeBridge

    public init(bridge: any RuntimeBridge = AppleRuntimeBridge()) {
        self.bridge = bridge
    }

    public func open(containerID: String) async throws -> any ProcessSession {
        try await bridge.containers.exec(ProcessRequest(
            resourceID: containerID,
            arguments: ["/bin/sh"],
            environment: [],
            workingDirectory: nil,
            user: nil,
            tty: true,
            interactive: true
        ))
    }
}

public struct ProductionMachineTerminalOpener: MachineTerminalOpening, Sendable {
    private let backend: any MachineBackend
    private let makeProcessID: @Sendable () -> String

    public init(
        backend: any MachineBackend = AppleMachineBackend(),
        makeProcessID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.backend = backend
        self.makeProcessID = makeProcessID
    }

    public func open(machineID: String) async throws -> any ProcessSession {
        let machine = try await backend.inspect(id: machineID)
        if machine.summary.state != .running {
            _ = try await backend.boot(id: machineID)
        }
        let transport = try await backend.createProcess(MachineProcessPlan(
            machineID: machineID,
            processID: makeProcessID(),
            arguments: [],
            environment: [],
            workingDirectory: nil,
            user: nil,
            terminal: true,
            interactive: true
        ))
        return try await MachineProcessAdapter.start(transport)
    }
}

public struct SimulatedMachineTerminalOpener: MachineTerminalOpening, Sendable {
    public init() {}

    public func open(machineID: String) async throws -> any ProcessSession {
        SimulatedMachineTerminalSession(machineID: machineID)
    }
}

public struct SimulatedContainerTerminalOpener: ContainerTerminalOpening, Sendable {
    public init() {}

    public func open(containerID: String) async throws -> any ProcessSession {
        SimulatedMachineTerminalSession(machineID: containerID)
    }
}

private actor SimulatedMachineTerminalSession: ProcessSession {
    nonisolated let id: String
    nonisolated let output: AsyncThrowingStream<ProcessOutputChunk, any Error>

    init(machineID: String) {
        id = "simulated-\(machineID)"
        output = AsyncThrowingStream { continuation in
            continuation.yield(.terminal(Data("Connected to \(machineID)\r\n".utf8)))
        }
    }

    func send(_: Data) async throws {}
    func resize(columns _: Int, rows _: Int) async throws {}
    func wait() async throws -> ProcessExit {
        .init(code: 0)
    }

    func detach() async throws {}
    func terminate(signal _: String) async throws {}
}
