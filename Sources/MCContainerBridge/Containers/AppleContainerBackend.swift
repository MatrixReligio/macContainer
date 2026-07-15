import ContainerAPIClient
import ContainerPersistence
import ContainerResource
import Darwin
import Foundation
import MCModel

public enum AppleContainerBackendError: Error, Equatable, Sendable {
    case invalidResourceValue
    case invalidMountSource(String)
    case invalidMountDestination(String)
    case invalidTemporaryFilesystem(String)
    case missingProcessArguments
    case containerNotRunning(String)
    case standardInputUnavailable
    case unsupportedLogSinceFilter
}

public struct AppleContainerBackend: ContainerBackend, Sendable {
    private let client: ContainerClient

    public init(client: ContainerClient = ContainerClient()) {
        self.client = client
    }

    public func create(_ plan: ContainerCreatePlan) async throws -> ContainerDetail {
        guard plan.resources.cpuCount > 0,
              plan.resources.memoryBytes > 0,
              plan.resources.diskBytes.map({ $0 > 0 }) ?? true
        else {
            throw AppleContainerBackendError.invalidResourceValue
        }

        let systemConfiguration: ContainerSystemConfig = try await ConfigurationLoader.load()
        let processFlags = Flags.Process(
            cwd: plan.workingDirectory,
            env: plan.environment.map { "\($0.key)=\($0.value)" },
            envFile: [],
            gid: nil,
            interactive: false,
            tty: false,
            uid: nil,
            ulimits: [],
            user: nil
        )
        let managementFlags = Flags.Management(
            arch: Arch.hostArchitecture().rawValue,
            capAdd: plan.capabilitiesToAdd,
            capDrop: plan.capabilitiesToDrop,
            cidfile: "",
            detach: false,
            dns: Flags.DNS(domain: nil, nameservers: plan.dnsServers, options: [], searchDomains: []),
            dnsDisabled: plan.noDNS,
            entrypoint: nil,
            initImage: nil,
            kernel: nil,
            labels: [],
            mounts: [],
            name: plan.name,
            networks: plan.networks,
            os: "linux",
            platform: plan.platform,
            publishPorts: plan.publishedPorts.map(\.description),
            publishSockets: [],
            readOnly: plan.readOnlyRoot,
            remove: plan.autoRemove,
            rosetta: false,
            runtime: nil,
            ssh: false,
            shmSize: nil,
            tmpFs: [],
            useInit: false,
            virtualization: plan.nestedVirtualization,
            volumes: []
        )
        try managementFlags.validate()

        var prepared = try await Utility.containerConfigFromFlags(
            id: plan.name,
            image: plan.imageReference,
            arguments: plan.arguments,
            process: processFlags,
            management: managementFlags,
            resource: Flags.Resource(
                cpus: Int64(plan.resources.cpuCount),
                memory: "\(plan.resources.memoryBytes)b"
            ),
            registry: Flags.Registry(scheme: "auto"),
            imageFetch: Flags.ImageFetch(maxConcurrentDownloads: 3),
            containerSystemConfig: systemConfiguration,
            progressUpdate: { _ in },
            log: .init(label: "container.matrixreligio.com.runtime")
        )
        prepared.0.mounts = try directMounts(plan)
        prepared.0.resources.storage = try plan.resources.diskBytes.map(validatedUnsigned)

        try await client.create(
            configuration: prepared.0,
            options: ContainerCreateOptions(autoRemove: plan.autoRemove),
            kernel: prepared.1,
            initImage: prepared.2
        )
        return try await detail(client.get(id: plan.name))
    }

    public func list() async throws -> [ContainerDetail] {
        try await client.list(filters: ContainerListFilters.all.withoutMachines()).map(detail)
    }

    public func get(id: String) async throws -> ContainerDetail {
        try await detail(client.get(id: id))
    }

    public func bootstrap(id: String, attach: Bool) async throws -> any ContainerProcessTransport {
        let snapshot = try await client.get(id: id)
        let io = DirectProcessIO(
            terminal: snapshot.configuration.initProcess.terminal,
            interactive: false,
            attach: attach
        )
        do {
            let process = try await client.bootstrap(id: id, stdio: io.childHandles)
            io.closeChildHandles()
            return AppleContainerProcessTransport(process: process, io: io)
        } catch {
            io.closeAll()
            throw error
        }
    }

    public func stop(id: String, timeout: Duration?) async throws {
        let seconds = timeout.map(timeoutSeconds) ?? ContainerStopOptions.default.timeoutInSeconds
        try await client.stop(
            id: id,
            opts: ContainerStopOptions(timeoutInSeconds: seconds, signal: nil)
        )
    }

    public func kill(id: String, signal: String) async throws {
        try await client.kill(id: id, signal: signal)
    }

    public func delete(id: String, force: Bool) async throws {
        try await client.delete(id: id, force: force)
    }

    public func createProcess(_ plan: ContainerProcessPlan) async throws -> any ContainerProcessTransport {
        guard let executable = plan.arguments.first else {
            throw AppleContainerBackendError.missingProcessArguments
        }
        let snapshot = try await client.get(id: plan.containerID)
        guard snapshot.status == .running else {
            throw AppleContainerBackendError.containerNotRunning(plan.containerID)
        }

        var configuration = snapshot.configuration.initProcess
        configuration.executable = executable
        configuration.arguments = Array(plan.arguments.dropFirst())
        configuration.environment = mergingEnvironment(
            configuration.environment,
            overrides: plan.environment
        )
        if let workingDirectory = plan.workingDirectory {
            configuration.workingDirectory = workingDirectory
        }
        if let user = plan.user {
            configuration.user = .raw(userString: user)
        }
        configuration.terminal = plan.terminal

        let io = DirectProcessIO(
            terminal: plan.terminal,
            interactive: plan.interactive,
            attach: true
        )
        do {
            let process = try await client.createProcess(
                containerId: plan.containerID,
                processId: plan.processID,
                configuration: configuration,
                stdio: io.childHandles
            )
            io.closeChildHandles()
            return AppleContainerProcessTransport(process: process, io: io)
        } catch {
            io.closeAll()
            throw error
        }
    }

    public func logs(
        id: String,
        options: LogOptions
    ) async throws -> AsyncThrowingStream<LogRecord, any Error> {
        guard options.since == nil else {
            throw AppleContainerBackendError.unsupportedLogSinceFilter
        }
        let handles = try await client.logs(id: id)
        guard let handle = handles.first else {
            return AsyncThrowingStream { $0.finish() }
        }
        for unused in handles.dropFirst() {
            try? unused.close()
        }
        return try makeLogStream(handle: handle, options: options)
    }

    public func stats(id: String) async throws -> BackendContainerStats {
        let stats = try await client.stats(id: id)
        return BackendContainerStats(
            id: id,
            timestamp: Date(),
            cpuUsageMicroseconds: stats.cpuUsageUsec ?? 0,
            memoryBytes: stats.memoryUsageBytes ?? 0,
            networkReceiveBytes: stats.networkRxBytes ?? 0,
            networkTransmitBytes: stats.networkTxBytes ?? 0
        )
    }

    public func copyIn(id: String, source: URL, destination: String) async throws {
        try await client.copyIn(
            id: id,
            source: source.path,
            destination: destination,
            createParents: true
        )
    }

    public func copyOut(id: String, source: String, destination: URL) async throws {
        try await client.copyOut(
            id: id,
            source: source,
            destination: destination.path,
            createParents: true
        )
    }

    public func export(id: String, destination: URL) async throws {
        try await client.export(id: id, archive: destination)
    }

    public func diskUsage(id: String) async throws -> Int64 {
        try await Int64(clamping: client.diskUsage(id: id))
    }

    private func directMounts(_ plan: ContainerCreatePlan) throws -> [Filesystem] {
        var result: [Filesystem] = []
        result.reserveCapacity(plan.mounts.count + plan.temporaryFilesystems.count)
        for mount in plan.mounts {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: mount.source, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                throw AppleContainerBackendError.invalidMountSource(mount.source)
            }
            guard Self.validContainerPath(mount.destination) else {
                throw AppleContainerBackendError.invalidMountDestination(mount.destination)
            }
            result.append(
                Filesystem.virtiofs(
                    source: mount.source,
                    destination: mount.destination,
                    options: mount.readOnly ? ["ro"] : []
                )
            )
        }
        for destination in plan.temporaryFilesystems {
            guard Self.validContainerPath(destination) else {
                throw AppleContainerBackendError.invalidTemporaryFilesystem(destination)
            }
            result.append(Filesystem.tmpfs(destination: destination, options: []))
        }
        return result
    }

    private func detail(_ snapshot: ContainerSnapshot) -> ContainerDetail {
        let configuration = snapshot.configuration
        return ContainerDetail(
            summary: ContainerSummary(
                id: snapshot.id,
                name: snapshot.id,
                imageReference: configuration.image.reference,
                state: Self.state(snapshot.status),
                createdAt: configuration.creationDate
            ),
            resources: RuntimeResources(
                cpuCount: configuration.resources.cpus,
                memoryBytes: Int64(clamping: configuration.resources.memoryInBytes),
                diskBytes: configuration.resources.storage.map(Int64.init(clamping:))
            ),
            networks: configuration.networks.map(\.network),
            mounts: configuration.mounts.map {
                Mount(
                    source: $0.source,
                    destination: $0.destination,
                    readOnly: $0.options.contains("ro")
                )
            }
        )
    }

    private static func state(_ status: RuntimeStatus) -> RuntimeResourceState {
        switch status {
        case .unknown: .unknown
        case .stopped: .stopped
        case .running: .running
        case .stopping: .stopping
        }
    }

    private static func validContainerPath(_ path: String) -> Bool {
        path.hasPrefix("/")
            && !path.split(separator: "/", omittingEmptySubsequences: true).contains("..")
            && !path.contains("\0")
    }

    private func validatedUnsigned(_ value: Int64) throws -> UInt64 {
        guard value > 0 else {
            throw AppleContainerBackendError.invalidResourceValue
        }
        return UInt64(value)
    }

    private func timeoutSeconds(_ duration: Duration) -> Int32 {
        let components = duration.components
        let rounded = components.seconds + (components.attoseconds > 0 ? 1 : 0)
        return Int32(clamping: max(0, rounded))
    }

    private func mergingEnvironment(_ base: [String], overrides: [KeyValue]) -> [String] {
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

    private func makeLogStream(
        handle: FileHandle,
        options: LogOptions
    ) throws -> AsyncThrowingStream<LogRecord, any Error> {
        let initialData = try handle.readToEnd() ?? Data()
        let selectedData = options.tail.map { Self.tailData(initialData, lines: $0) } ?? initialData
        let (stream, continuation) = AsyncThrowingStream<LogRecord, any Error>.makeStream()
        if !selectedData.isEmpty {
            continuation.yield(
                Self.logRecord(
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
                    Self.logRecord(
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

    static func logRecord(_ bytes: Data, timestamps: Bool, now: Date) -> LogRecord {
        LogRecord(
            timestamp: timestamps ? now : nil,
            stream: "stdio",
            bytes: bytes
        )
    }

    static func tailData(_ data: Data, lines: Int) -> Data {
        guard lines > 0 else {
            return Data()
        }
        var remainingLines = lines
        var start = data.startIndex
        var isTerminalNewline = data.last == 0x0A
        for index in data.indices.reversed() where data[index] == 0x0A {
            if isTerminalNewline {
                isTerminalNewline = false
                continue
            }
            remainingLines -= 1
            if remainingLines == 0 {
                start = data.index(after: index)
                break
            }
        }
        return data[start...]
    }
}

public actor AppleContainerProcessTransport: ContainerProcessTransport {
    public let id: String
    public let terminal: Bool
    public let standardInput: FileHandle?
    public let standardOutput: FileHandle?
    public let standardError: FileHandle?

    private static let signalNumbers: [String: Int32] = [
        "SIGHUP": SIGHUP,
        "SIGINT": SIGINT,
        "SIGQUIT": SIGQUIT,
        "SIGKILL": SIGKILL,
        "SIGTERM": SIGTERM,
        "SIGUSR1": SIGUSR1,
        "SIGUSR2": SIGUSR2,
        "SIGSTOP": SIGSTOP,
        "SIGCONT": SIGCONT,
        "SIGWINCH": SIGWINCH
    ]

    private let process: any ClientProcess
    private var detached = false

    init(process: any ClientProcess, io: DirectProcessIO) {
        id = process.id
        self.process = process
        terminal = io.terminal
        standardInput = io.inputWriter
        standardOutput = io.outputReader
        standardError = io.errorReader
    }

    public func start() async throws {
        try await process.start()
    }

    public func resize(columns: Int, rows: Int) async throws {
        try await process.resize(
            .init(
                width: UInt16(clamping: columns),
                height: UInt16(clamping: rows)
            )
        )
    }

    public func send(_ data: Data) async throws {
        guard !detached, let standardInput else {
            throw AppleContainerBackendError.standardInputUnavailable
        }
        try standardInput.write(contentsOf: data)
    }

    public func wait() async throws -> Int32 {
        try await process.wait()
    }

    public func terminate(signal: String) async throws {
        try await process.kill(Self.signalNumber(signal))
    }

    public func detach() async throws {
        guard !detached else {
            return
        }
        detached = true
        try? standardInput?.close()
    }

    private static func signalNumber(_ signal: String) throws -> Int32 {
        guard let number = signalNumbers[signal.uppercased()] else {
            throw ContainerProcessError.invalidSignal(signal)
        }
        return number
    }
}

final class DirectProcessIO: Sendable {
    let terminal: Bool
    let childHandles: [FileHandle?]
    let inputWriter: FileHandle?
    let outputReader: FileHandle?
    let errorReader: FileHandle?

    private let childInput: FileHandle?
    private let childOutput: FileHandle?
    private let childError: FileHandle?

    init(terminal: Bool, interactive: Bool, attach: Bool) {
        self.terminal = terminal
        let inputPipe = interactive ? Pipe() : nil
        let outputPipe = attach ? Pipe() : nil
        let errorPipe = attach && !terminal ? Pipe() : nil

        childInput = inputPipe?.fileHandleForReading
        childOutput = outputPipe?.fileHandleForWriting
        childError = errorPipe?.fileHandleForWriting
        inputWriter = inputPipe?.fileHandleForWriting
        outputReader = outputPipe?.fileHandleForReading
        errorReader = errorPipe?.fileHandleForReading
        childHandles = [childInput, childOutput, childError]
    }

    func closeChildHandles() {
        try? childInput?.close()
        try? childOutput?.close()
        try? childError?.close()
    }

    func closeAll() {
        closeChildHandles()
        try? inputWriter?.close()
        try? outputReader?.close()
        try? errorReader?.close()
    }
}
