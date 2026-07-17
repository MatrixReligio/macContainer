import ContainerAPIClient
import ContainerizationOCI
import ContainerPersistence
import ContainerResource
import Foundation
import MachineAPIClient
import MCModel

public enum AppleMachineBackendError: Error, Equatable, Sendable {
    case machineNotRunning(String)
    case missingContainerIdentity(String)
    case unsupportedLogSinceFilter
}

public struct AppleMachineBackend: MachineBackend, Sendable {
    private let makeMachineClient: @Sendable () -> MachineClient
    private let makeContainerClient: @Sendable () -> ContainerClient

    public init() {
        makeMachineClient = { MachineClient() }
        makeContainerClient = { ContainerClient() }
    }

    public init(machineClient: MachineClient, containerClient: ContainerClient) {
        makeMachineClient = { machineClient }
        makeContainerClient = { containerClient }
    }

    init(
        makeMachineClient: @escaping @Sendable () -> MachineClient,
        makeContainerClient: @escaping @Sendable () -> ContainerClient
    ) {
        self.makeMachineClient = makeMachineClient
        self.makeContainerClient = makeContainerClient
    }

    public func create(_ plan: MachineCreatePlan) async throws -> MachineDetail {
        let machineClient = makeMachineClient()
        let configuration: ContainerSystemConfig = try await ConfigurationLoader.load()
        var management = Flags.MachineManagement()
        management.arch = Arch.hostArchitecture().rawValue
        management.os = "linux"
        let (machineConfiguration, machineResources) = try await MachineClient.machineConfigFromFlags(
            id: plan.name,
            image: plan.imageReference,
            management: management,
            registry: Flags.Registry(scheme: "auto"),
            imageFetch: Flags.ImageFetch(maxConcurrentDownloads: 3),
            containerSystemConfig: configuration,
            progressUpdate: { _ in }
        )
        let bootConfig = try Self.applying(plan, to: configuration.machine)
        try await machineClient.create(
            configuration: machineConfiguration,
            resources: machineResources,
            bootConfig: bootConfig
        )
        return await detail(
            MachineSnapshot(
                configuration: machineConfiguration,
                status: .stopped,
                bootConfig: bootConfig
            )
        )
    }

    public func boot(id: String) async throws -> MachineDetail {
        let machineClient = makeMachineClient()
        return try await detail(machineClient.boot(id: id))
    }

    public func list() async throws -> [MachineDetail] {
        let machineClient = makeMachineClient()
        let snapshots = try await machineClient.list()
        let defaultID = try await machineClient.getDefault()
        return snapshots.map {
            Self.detail($0, defaultID: defaultID)
        }
    }

    public func inspect(id: String) async throws -> MachineDetail {
        let machineClient = makeMachineClient()
        return try await detail(machineClient.inspect(id: id))
    }

    public func set(id: String, plan: MachineSetPlan) async throws -> MachineDetail {
        let machineClient = makeMachineClient()
        let snapshot = try await machineClient.inspect(id: id)
        var updates: [String: String] = [:]
        if let resources = plan.resources {
            updates["cpus"] = String(resources.cpuCount)
            updates["memory"] = "\(resources.memoryBytes)b"
        }
        if let homeMount = plan.homeMount {
            updates["home-mount"] = homeMount
        }
        if let nestedVirtualization = plan.nestedVirtualization {
            updates["virtualization"] = String(nestedVirtualization)
        }
        let bootConfig = try snapshot.bootConfig.with(updates)
        try await machineClient.setConfig(id: id, bootConfig: bootConfig)
        var updatedSnapshot = snapshot
        updatedSnapshot.bootConfig = bootConfig
        return await detail(updatedSnapshot)
    }

    public func setDefault(id: String) async throws {
        let machineClient = makeMachineClient()
        try await machineClient.setDefault(id: id)
    }

    public func logs(
        id: String,
        options: LogOptions
    ) async throws -> AsyncThrowingStream<LogRecord, any Error> {
        let machineClient = makeMachineClient()
        guard options.since == nil else {
            throw AppleMachineBackendError.unsupportedLogSinceFilter
        }
        let handles = try await machineClient.logs(id: id)
        guard let handle = handles.first else {
            return AsyncThrowingStream { $0.finish() }
        }
        for unused in handles.dropFirst() {
            try? unused.close()
        }
        return try Self.logStream(handle: handle, options: options)
    }

    public func stop(id: String, force _: Bool) async throws {
        let machineClient = makeMachineClient()
        try await machineClient.stop(id: id)
    }

    public func delete(id: String, force: Bool) async throws {
        let machineClient = makeMachineClient()
        if force {
            let snapshot = try await machineClient.inspect(id: id)
            if snapshot.status != .stopped {
                try await machineClient.stop(id: id)
            }
        }
        try await machineClient.delete(id: id)
    }

    public func createProcess(_ plan: MachineProcessPlan) async throws -> any ContainerProcessTransport {
        let machineClient = makeMachineClient()
        let containerClient = makeContainerClient()
        let snapshot = try await machineClient.inspect(id: plan.machineID)
        guard snapshot.status == .running else {
            throw AppleMachineBackendError.machineNotRunning(plan.machineID)
        }
        guard let containerID = snapshot.containerId else {
            throw AppleMachineBackendError.missingContainerIdentity(plan.machineID)
        }

        let usesDefaultShell = plan.arguments.isEmpty
        let terminal = usesDefaultShell ? true : plan.terminal
        let interactive = usesDefaultShell ? true : plan.interactive
        let processArguments: [String] = if let executable = plan.arguments.first {
            ["-s", executable] + plan.arguments.dropFirst()
        } else {
            ["-s"]
        }
        let processConfiguration = ProcessConfiguration(
            executable: "/\(MachineBundle.sbinDirectory)/\(MachineBundle.initFile)",
            arguments: processArguments,
            environment: Self.mergingEnvironment(
                snapshot.configuration.processEnvironment,
                overrides: plan.environment
            ),
            workingDirectory: plan.workingDirectory ?? snapshot.configuration.home,
            terminal: terminal,
            user: plan.user.map(ProcessConfiguration.User.raw) ?? snapshot.configuration.user
        )
        let io = DirectProcessIO(
            terminal: terminal,
            interactive: interactive,
            attach: true
        )
        do {
            let process = try await containerClient.createProcess(
                containerId: containerID,
                processId: plan.processID,
                configuration: processConfiguration,
                stdio: io.childHandles
            )
            io.closeChildHandles()
            return AppleContainerProcessTransport(process: process, io: io)
        } catch {
            io.closeAll()
            throw error
        }
    }

    private func detail(_ snapshot: MachineSnapshot) async -> MachineDetail {
        let machineClient = makeMachineClient()
        let defaultID = try? await machineClient.getDefault()
        return Self.detail(snapshot, defaultID: defaultID)
    }

    private static func detail(
        _ snapshot: MachineSnapshot,
        defaultID: String?
    ) -> MachineDetail {
        MachineDetail(
            summary: MachineSummary(
                id: snapshot.id,
                name: snapshot.id,
                state: state(snapshot.status),
                resources: RuntimeResources(
                    cpuCount: snapshot.bootConfig.cpus,
                    memoryBytes: Int64(clamping: snapshot.bootConfig.memory.toUInt64(unit: .bytes)),
                    diskBytes: snapshot.diskSize.map(Int64.init(clamping:))
                ),
                isDefault: snapshot.id == defaultID
            ),
            imageReference: snapshot.configuration.image.reference,
            homeMount: snapshot.bootConfig.homeMount.rawValue,
            networks: [NetworkClient.defaultNetworkName],
            kernelIdentifier: snapshot.bootConfig.kernelPath?.string,
            nestedVirtualization: snapshot.bootConfig.virtualization
        )
    }

    private static func applying(
        _ plan: MachineCreatePlan,
        to defaults: MachineConfig
    ) throws -> MachineConfig {
        var updates: [String: String] = [
            "cpus": String(plan.resources.cpuCount),
            "memory": "\(plan.resources.memoryBytes)b",
            "home-mount": plan.homeMount,
            "virtualization": String(plan.nestedVirtualization)
        ]
        if let kernelURL = plan.kernelURL {
            updates["kernel"] = try MachineConfig.validateKernelPath(kernelURL.path).string
        }
        return try defaults.with(updates)
    }

    private static func state(_ status: RuntimeStatus) -> RuntimeResourceState {
        switch status {
        case .unknown: .unknown
        case .stopped: .stopped
        case .running: .running
        case .stopping: .stopping
        }
    }

    private static func mergingEnvironment(
        _ base: [String],
        overrides: [KeyValue]
    ) -> [String] {
        var order: [String] = []
        var values: [String: String] = [:]
        for entry in base {
            let key = String(entry.split(separator: "=", maxSplits: 1).first ?? Substring(entry))
            if values[key] == nil {
                order.append(key)
            }
            values[key] = entry
        }
        for override in overrides {
            if values[override.key] == nil {
                order.append(override.key)
            }
            values[override.key] = "\(override.key)=\(override.value)"
        }
        return order.compactMap { values[$0] }
    }

    private static func logStream(
        handle: FileHandle,
        options: LogOptions
    ) throws -> AsyncThrowingStream<LogRecord, any Error> {
        let initialData = try handle.readToEnd() ?? Data()
        let selectedData = options.tail.map {
            AppleContainerBackend.tailData(initialData, lines: $0)
        } ?? initialData
        let (stream, continuation) = AsyncThrowingStream<LogRecord, any Error>.makeStream()
        if !selectedData.isEmpty {
            continuation.yield(
                AppleContainerBackend.logRecord(
                    selectedData,
                    timestamps: options.timestamps,
                    now: Date()
                )
            )
        }
        guard options.follow else {
            try? handle.close()
            continuation.finish()
            return stream
        }
        handle.readabilityHandler = { readable in
            let data = readable.availableData
            if !data.isEmpty {
                continuation.yield(
                    AppleContainerBackend.logRecord(
                        data,
                        timestamps: options.timestamps,
                        now: Date()
                    )
                )
            }
        }
        continuation.onTermination = { _ in
            handle.readabilityHandler = nil
            try? handle.close()
        }
        return stream
    }
}
