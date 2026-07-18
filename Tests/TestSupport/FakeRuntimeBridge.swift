import Foundation
import MCContainerBridge
import MCModel

public final class FakeRuntimeBridge: RuntimeBridge, @unchecked Sendable {
    private let recorder: InvocationRecorder

    public let containers: any ContainerOperations
    public let images: any ImageOperations
    public let builds: any BuildOperations
    public let builders: any BuilderOperations
    public let networks: any NetworkOperations
    public let volumes: any VolumeOperations
    public let registries: any RegistryOperations
    public let machines: any MachineOperations
    public let system: any SystemOperations
    public let dns: any DNSOperations
    public let kernel: any KernelOperations
    public let configuration: any ConfigurationOperations

    public init(
        runtimeVersion: String = "1.1.0",
        apiVersion: String? = nil,
        systemState: RuntimeResourceState = .stopped
    ) {
        let recorder = InvocationRecorder()
        let support = FakeRuntimeSupport(recorder: recorder)
        self.recorder = recorder
        containers = FakeContainerOperations(support: support)
        images = FakeImageOperations(support: support)
        builds = FakeBuildOperations(support: support)
        builders = FakeBuilderOperations(support: support)
        networks = FakeNetworkOperations(support: support)
        volumes = FakeVolumeOperations(support: support)
        registries = FakeRegistryOperations(support: support)
        machines = FakeMachineOperations(support: support)
        system = FakeSystemOperations(
            support: support,
            runtimeVersion: runtimeVersion,
            apiVersion: apiVersion,
            systemState: systemState
        )
        dns = FakeDNSOperations(support: support)
        kernel = FakeKernelOperations(support: support)
        configuration = FakeConfigurationOperations(support: support)
    }

    public func recordedInvocations() async -> [RecordedInvocation] {
        await recorder.snapshot()
    }
}

private struct FakeRuntimeSupport: Sendable {
    let recorder: InvocationRecorder

    func record(
        _ operationID: String,
        resources: [String] = [],
        arguments: [String: String] = [:]
    ) async throws {
        let invocation = try RecordedInvocation(
            operationID: operationID,
            resourceIDs: resources,
            redactedArguments: arguments
        )
        await recorder.record(invocation)
    }

    func recordKnownSafe(_ operationID: String, arguments: [String: String] = [:]) async {
        guard let invocation = try? RecordedInvocation(
            operationID: operationID,
            resourceIDs: [],
            redactedArguments: arguments
        ) else {
            return
        }
        await recorder.record(invocation)
    }
}

private struct FakeContainerOperations: ContainerOperations {
    let support: FakeRuntimeSupport

    func run(_ request: ContainerRunRequest) async throws -> ContainerRunResult {
        try await support.record("core.run", resources: [request.create.name])
        return ContainerRunResult(container: summary(request.create))
    }

    func create(_ request: ContainerCreateRequest) async throws -> ContainerSummary {
        try await support.record("containers.create", resources: [request.name])
        return summary(request)
    }

    func start(ids: [String]) async throws -> [BatchItemResult] {
        try await support.record("containers.start", resources: ids)
        return successfulResults(ids)
    }

    func stop(ids: [String], timeout _: Duration?) async throws -> [BatchItemResult] {
        try await support.record("containers.stop", resources: ids)
        return successfulResults(ids)
    }

    func kill(ids: [String], signal: String) async throws -> [BatchItemResult] {
        try await support.record("containers.kill", resources: ids, arguments: ["signal": signal])
        return successfulResults(ids)
    }

    func delete(ids: [String], force: Bool) async throws -> [BatchItemResult] {
        try await support.record("containers.delete", resources: ids, arguments: ["force": String(force)])
        return successfulResults(ids)
    }

    func list() async throws -> [ContainerSummary] {
        try await support.record("containers.list")
        return []
    }

    func exec(_ request: ProcessRequest) async throws -> any ProcessSession {
        try await support.record("containers.exec", resources: [request.resourceID])
        return FakeProcessSession(id: request.resourceID)
    }

    func export(id: String, destination: URL) async throws {
        try await support.record("containers.export", resources: [id], arguments: ["destination": destination.path])
    }

    func logs(id: String, options _: LogOptions) async throws -> AsyncThrowingStream<LogRecord, any Error> {
        try await support.record("containers.logs", resources: [id])
        return emptyStream()
    }

    func inspect(id: String) async throws -> ContainerDetail {
        try await support.record("containers.inspect", resources: [id])
        return ContainerDetail(
            summary: ContainerSummary(id: id, name: id, imageReference: "", state: .stopped),
            resources: RuntimeResources(cpuCount: 0, memoryBytes: 0)
        )
    }

    func stats(id: String) async throws -> AsyncThrowingStream<ContainerStats, any Error> {
        try await support.record("containers.stats", resources: [id])
        return emptyStream()
    }

    func copy(_ request: CopyRequest) async throws {
        try await support.record("containers.copy", arguments: ["request": String(describing: request)])
    }

    func prune() async throws -> PruneResult {
        try await support.record("containers.prune")
        return PruneResult()
    }

    private func summary(_ request: ContainerCreateRequest) -> ContainerSummary {
        ContainerSummary(
            id: request.name,
            name: request.name,
            imageReference: request.imageReference,
            state: .stopped
        )
    }
}

private struct FakeImageOperations: ImageOperations {
    let support: FakeRuntimeSupport

    func list() async throws -> [ImageSummary] {
        try await support.record("images.list")
        return []
    }

    func pull(_ request: ImageTransferRequest) async throws -> AsyncThrowingStream<TransferProgress, any Error> {
        try await support.record("images.pull", resources: [request.reference])
        return emptyStream()
    }

    func push(_ request: ImageTransferRequest) async throws -> AsyncThrowingStream<TransferProgress, any Error> {
        try await support.record("images.push", resources: [request.reference])
        return emptyStream()
    }

    func save(references: [String], destination: URL) async throws {
        try await support.record("images.save", resources: references, arguments: ["destination": destination.path])
    }

    func load(source: URL) async throws -> [ImageSummary] {
        try await support.record("images.load", arguments: ["source": source.path])
        return []
    }

    func tag(source: String, target: String) async throws {
        try await support.record("images.tag", resources: [source, target])
    }

    func delete(references: [String]) async throws -> [BatchItemResult] {
        try await support.record("images.delete", resources: references)
        return successfulResults(references)
    }

    func prune() async throws -> PruneResult {
        try await support.record("images.prune")
        return PruneResult()
    }

    func inspect(reference: String) async throws -> ImageDetail {
        try await support.record("images.inspect", resources: [reference])
        return ImageDetail(summary: ImageSummary(reference: reference))
    }
}

private struct FakeBuildOperations: BuildOperations {
    let support: FakeRuntimeSupport

    func build(_ request: BuildRequest) async throws -> AsyncThrowingStream<BuildProgress, any Error> {
        try await support.record("core.build", arguments: ["context": request.context.path])
        return emptyStream()
    }
}

private struct FakeBuilderOperations: BuilderOperations {
    let support: FakeRuntimeSupport

    func start(_ request: BuilderStartRequest) async throws -> BuilderSummary {
        try await support.record("builder.start")
        return BuilderSummary(state: .running, resources: request.resources)
    }

    func status() async throws -> BuilderSummary {
        try await support.record("builder.status")
        return BuilderSummary(state: .stopped)
    }

    func stop() async throws {
        try await support.record("builder.stop")
    }

    func delete() async throws {
        try await support.record("builder.delete")
    }
}

private struct FakeNetworkOperations: NetworkOperations {
    let support: FakeRuntimeSupport

    func create(_ request: NetworkCreateRequest) async throws -> NetworkSummary {
        try await support.record("networks.create", resources: [request.name], arguments: [
            "subnet": request.subnet ?? "",
            "ipv6Subnet": request.ipv6Subnet ?? "",
            "hostOnly": String(request.hostOnly),
            "plugin": request.plugin,
            "options": request.options.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        ])
        return NetworkSummary(id: request.name, name: request.name, state: .stopped)
    }

    func delete(ids: [String]) async throws -> [BatchItemResult] {
        try await support.record("networks.delete", resources: ids)
        return successfulResults(ids)
    }

    func prune() async throws -> PruneResult {
        try await support.record("networks.prune")
        return PruneResult()
    }

    func list() async throws -> [NetworkSummary] {
        try await support.record("networks.list")
        return []
    }

    func inspect(id: String) async throws -> NetworkDetail {
        try await support.record("networks.inspect", resources: [id])
        return NetworkDetail(summary: NetworkSummary(id: id, name: id, state: .stopped))
    }
}

private struct FakeVolumeOperations: VolumeOperations {
    let support: FakeRuntimeSupport

    func create(_ request: VolumeCreateRequest) async throws -> VolumeSummary {
        let driverOptions = request.driverOptions
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        try await support.record("volumes.create", resources: [request.name], arguments: [
            "sizeBytes": request.sizeBytes.map(String.init) ?? "",
            "driverOptions": driverOptions
        ])
        return VolumeSummary(name: request.name)
    }

    func delete(names: [String]) async throws -> [BatchItemResult] {
        try await support.record("volumes.delete", resources: names)
        return successfulResults(names)
    }

    func prune() async throws -> PruneResult {
        try await support.record("volumes.prune")
        return PruneResult()
    }

    func list() async throws -> [VolumeSummary] {
        try await support.record("volumes.list")
        return []
    }

    func inspect(name: String) async throws -> VolumeDetail {
        try await support.record("volumes.inspect", resources: [name])
        return VolumeDetail(summary: VolumeSummary(name: name))
    }
}

private struct FakeRegistryOperations: RegistryOperations {
    let support: FakeRuntimeSupport

    func login(_ request: RegistryLoginRequest) async throws -> RegistrySummary {
        try await support.record(
            "registries.login",
            resources: [request.server],
            arguments: ["username": request.username, "password": "<redacted>"]
        )
        return RegistrySummary(server: request.server, username: request.username)
    }

    func logout(server: String) async throws {
        try await support.record("registries.logout", resources: [server])
    }

    func list() async throws -> [RegistrySummary] {
        try await support.record("registries.list")
        return []
    }
}

private struct FakeMachineOperations: MachineOperations {
    let support: FakeRuntimeSupport

    func create(_ request: MachineCreateRequest) async throws -> MachineSummary {
        try await support.record("machines.create", resources: [request.name])
        return summary(request)
    }

    func start(ids: [String]) async throws -> [BatchItemResult] {
        try await support.record("machines.start", resources: ids)
        return successfulResults(ids)
    }

    func run(_ request: MachineRunRequest) async throws -> any ProcessSession {
        try await support.record("machines.run", resources: [request.create.name])
        return FakeProcessSession(id: request.create.name)
    }

    func list() async throws -> [MachineSummary] {
        try await support.record("machines.list")
        return []
    }

    func inspect(id: String) async throws -> MachineDetail {
        try await support.record("machines.inspect", resources: [id])
        return MachineDetail(
            summary: MachineSummary(
                id: id,
                name: id,
                state: .stopped,
                resources: RuntimeResources(cpuCount: 0, memoryBytes: 0)
            )
        )
    }

    func set(id: String, request: MachineSetRequest) async throws -> MachineSummary {
        try await support.record("machines.set", resources: [id])
        return MachineSummary(
            id: id,
            name: id,
            state: .stopped,
            resources: request.resources ?? RuntimeResources(cpuCount: 0, memoryBytes: 0)
        )
    }

    func setDefault(id: String) async throws {
        try await support.record("machines.set-default", resources: [id])
    }

    func logs(id: String, options _: LogOptions) async throws -> AsyncThrowingStream<LogRecord, any Error> {
        try await support.record("machines.logs", resources: [id])
        return emptyStream()
    }

    func stop(ids: [String], force: Bool) async throws -> [BatchItemResult] {
        try await support.record("machines.stop", resources: ids, arguments: ["force": String(force)])
        return successfulResults(ids)
    }

    func delete(ids: [String], force: Bool) async throws -> [BatchItemResult] {
        try await support.record("machines.delete", resources: ids, arguments: ["force": String(force)])
        return successfulResults(ids)
    }

    private func summary(_ request: MachineCreateRequest) -> MachineSummary {
        MachineSummary(
            id: request.name,
            name: request.name,
            state: .stopped,
            resources: request.resources
        )
    }
}

private struct FakeSystemOperations: SystemOperations {
    let support: FakeRuntimeSupport
    let runtimeVersion: String
    let apiVersion: String?
    let systemState: RuntimeResourceState

    func start(_ request: SystemStartRequest) async throws -> SystemSummary {
        try await support.record("system.start", arguments: ["timeout": String(request.healthTimeoutSeconds)])
        return SystemSummary(state: .running)
    }

    func stop(_ request: SystemStopRequest) async throws -> SystemSummary {
        try await support.record("system.stop", arguments: ["timeout": String(request.timeoutSeconds)])
        return SystemSummary(state: .stopped)
    }

    func status() async throws -> SystemSummary {
        try await support.record("system.status")
        return SystemSummary(state: systemState)
    }

    func version() async throws -> RuntimeVersionSummary {
        try await support.record("system.version")
        return RuntimeVersionSummary(version: runtimeVersion, apiVersion: apiVersion)
    }

    func logs(_: LogOptions) async throws -> AsyncThrowingStream<LogRecord, any Error> {
        try await support.record("system.logs")
        return emptyStream()
    }

    func diskUsage() async throws -> DiskUsageSummary {
        try await support.record("system.disk-usage")
        return DiskUsageSummary()
    }
}

private struct FakeDNSOperations: DNSOperations {
    let support: FakeRuntimeSupport

    func create(_ request: DNSCreateRequest) async throws -> DNSEntry {
        try await support.record("dns.create", resources: [request.name])
        return DNSEntry(name: request.name, addresses: request.addresses)
    }

    func delete(names: [String]) async throws -> [BatchItemResult] {
        try await support.record("dns.delete", resources: names)
        return successfulResults(names)
    }

    func list() async throws -> [DNSEntry] {
        try await support.record("dns.list")
        return []
    }
}

private struct FakeKernelOperations: KernelOperations {
    let support: FakeRuntimeSupport

    func setRecommended(platform: String, force: Bool) async throws -> KernelSummary {
        try await support.record("kernel.set", arguments: ["platform": platform, "force": String(force)])
        return KernelSummary(identifier: "recommended", platform: platform)
    }

    func setLocalBinary(_ url: URL, platform: String, force: Bool) async throws -> KernelSummary {
        try await support.record(
            "kernel.set",
            arguments: ["source": url.path, "platform": platform, "force": String(force)]
        )
        return KernelSummary(identifier: url.lastPathComponent, platform: platform)
    }

    func setLocalArchive(_ url: URL, platform: String, force: Bool) async throws -> KernelSummary {
        try await support.record(
            "kernel.set",
            arguments: ["source": url.path, "platform": platform, "force": String(force)]
        )
        return KernelSummary(identifier: url.lastPathComponent, platform: platform)
    }

    func setVerifiedRemoteArchive(_ request: VerifiedKernelArchiveRequest) async throws -> KernelSummary {
        try await support.record(
            "kernel.set",
            arguments: ["source": request.url.absoluteString, "platform": request.platform]
        )
        return KernelSummary(identifier: request.url.lastPathComponent, platform: request.platform)
    }
}

private struct FakeConfigurationOperations: ConfigurationOperations {
    let support: FakeRuntimeSupport

    func load() async throws -> SystemConfiguration {
        try await support.record("configuration.load")
        return .empty
    }

    func validate(_ configuration: SystemConfiguration) async -> [ValidationIssue] {
        await support.recordKnownSafe(
            "configuration.validate",
            arguments: ["fieldCount": String(configuration.values.count)]
        )
        return []
    }

    func preview(_ configuration: SystemConfiguration) async throws -> String {
        try await support.record("configuration.preview", arguments: ["fieldCount": String(configuration.values.count)])
        return ""
    }

    func save(_ configuration: SystemConfiguration) async throws -> ConfigurationSaveReport {
        try await support.record("configuration.save", arguments: ["fieldCount": String(configuration.values.count)])
        return ConfigurationSaveReport(
            destination: URL(fileURLWithPath: "/tmp/config.toml"),
            lastKnownGoodPreserved: true
        )
    }

    func apply(_ request: ConfigurationApplyRequest) async throws -> ConfigurationApplyReport {
        try await support.record(
            "configuration.apply",
            arguments: ["fieldCount": String(request.configuration.values.count)]
        )
        return ConfigurationApplyReport(restarted: true)
    }

    func export(_ configuration: SystemConfiguration, destination: URL) async throws {
        try await support.record(
            "configuration.export",
            arguments: ["fieldCount": String(configuration.values.count), "destination": destination.path]
        )
    }
}

private func successfulResults(_ ids: [String]) -> [BatchItemResult] {
    ids.map { BatchItemResult(id: $0, succeeded: true) }
}

private func emptyStream<Element: Sendable>() -> AsyncThrowingStream<Element, any Error> {
    AsyncThrowingStream { continuation in
        continuation.finish()
    }
}

private final class FakeProcessSession: ProcessSession, @unchecked Sendable {
    let id: String
    let output: AsyncThrowingStream<ProcessOutputChunk, any Error>

    init(id: String) {
        self.id = id
        output = emptyStream()
    }

    func send(_: Data) async throws {}
    func resize(columns _: Int, rows _: Int) async throws {}
    func wait() async throws -> ProcessExit {
        ProcessExit(code: 0)
    }

    func terminate(signal _: String) async throws {}
    func detach() async throws {}
}
