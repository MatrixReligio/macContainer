import Foundation
import MCModel

public protocol RuntimeBridge: Sendable {
    var containers: any ContainerOperations { get }
    var images: any ImageOperations { get }
    var builds: any BuildOperations { get }
    var builders: any BuilderOperations { get }
    var networks: any NetworkOperations { get }
    var volumes: any VolumeOperations { get }
    var registries: any RegistryOperations { get }
    var machines: any MachineOperations { get }
    var system: any SystemOperations { get }
    var dns: any DNSOperations { get }
    var kernel: any KernelOperations { get }
    var configuration: any ConfigurationOperations { get }
}

public protocol ContainerOperations: Sendable {
    func run(_ request: ContainerRunRequest) async throws -> ContainerRunResult
    func create(_ request: ContainerCreateRequest) async throws -> ContainerSummary
    func start(ids: [String]) async throws -> [BatchItemResult]
    func stop(ids: [String], timeout: Duration?) async throws -> [BatchItemResult]
    func kill(ids: [String], signal: String) async throws -> [BatchItemResult]
    func delete(ids: [String], force: Bool) async throws -> [BatchItemResult]
    func list() async throws -> [ContainerSummary]
    func exec(_ request: ProcessRequest) async throws -> any ProcessSession
    func export(id: String, destination: URL) async throws
    func logs(id: String, options: LogOptions) async throws -> AsyncThrowingStream<LogRecord, any Error>
    func inspect(id: String) async throws -> ContainerDetail
    func stats(id: String) async throws -> AsyncThrowingStream<ContainerStats, any Error>
    func copy(_ request: CopyRequest) async throws
    func prune() async throws -> PruneResult
}

public protocol ImageOperations: Sendable {
    func list() async throws -> [ImageSummary]
    func pull(_ request: ImageTransferRequest) async throws -> AsyncThrowingStream<TransferProgress, any Error>
    func push(_ request: ImageTransferRequest) async throws -> AsyncThrowingStream<TransferProgress, any Error>
    func save(references: [String], destination: URL) async throws
    func load(source: URL) async throws -> [ImageSummary]
    func tag(source: String, target: String) async throws
    func delete(references: [String]) async throws -> [BatchItemResult]
    func prune() async throws -> PruneResult
    func inspect(reference: String) async throws -> ImageDetail
}

public protocol NetworkOperations: Sendable {
    func create(_ request: NetworkCreateRequest) async throws -> NetworkSummary
    func delete(ids: [String]) async throws -> [BatchItemResult]
    func prune() async throws -> PruneResult
    func list() async throws -> [NetworkSummary]
    func inspect(id: String) async throws -> NetworkDetail
}

public protocol VolumeOperations: Sendable {
    func create(_ request: VolumeCreateRequest) async throws -> VolumeSummary
    func delete(names: [String]) async throws -> [BatchItemResult]
    func prune() async throws -> PruneResult
    func list() async throws -> [VolumeSummary]
    func inspect(name: String) async throws -> VolumeDetail
}

public protocol BuildOperations: Sendable {
    func build(_ request: BuildRequest) async throws -> AsyncThrowingStream<BuildProgress, any Error>
}

public protocol BuilderOperations: Sendable {
    func start(_ request: BuilderStartRequest) async throws -> BuilderSummary
    func status() async throws -> BuilderSummary
    func stop() async throws
    func delete() async throws
}

public protocol RegistryOperations: Sendable {
    func login(_ request: RegistryLoginRequest) async throws -> RegistrySummary
    func logout(server: String) async throws
    func list() async throws -> [RegistrySummary]
}

public protocol MachineOperations: Sendable {
    func create(_ request: MachineCreateRequest) async throws -> MachineSummary
    func start(ids: [String]) async throws -> [BatchItemResult]
    func run(_ request: MachineRunRequest) async throws -> any ProcessSession
    func list() async throws -> [MachineSummary]
    func inspect(id: String) async throws -> MachineDetail
    func set(id: String, request: MachineSetRequest) async throws -> MachineSummary
    func setDefault(id: String) async throws
    func logs(id: String, options: LogOptions) async throws -> AsyncThrowingStream<LogRecord, any Error>
    func stop(ids: [String], force: Bool) async throws -> [BatchItemResult]
    func delete(ids: [String], force: Bool) async throws -> [BatchItemResult]
}

public protocol SystemOperations: Sendable {
    func start(_ request: SystemStartRequest) async throws -> SystemSummary
    func stop(_ request: SystemStopRequest) async throws -> SystemSummary
    func status() async throws -> SystemSummary
    func version() async throws -> RuntimeVersionSummary
    func logs(_ options: LogOptions) async throws -> AsyncThrowingStream<LogRecord, any Error>
    func diskUsage() async throws -> DiskUsageSummary
}

public protocol DNSOperations: Sendable {
    func create(_ request: DNSCreateRequest) async throws -> DNSEntry
    func delete(names: [String]) async throws -> [BatchItemResult]
    func list() async throws -> [DNSEntry]
}

public protocol KernelOperations: Sendable {
    func setRecommended(platform: String, force: Bool) async throws -> KernelSummary
    func setLocalBinary(_ url: URL, platform: String, force: Bool) async throws -> KernelSummary
    func setLocalArchive(_ url: URL, platform: String, force: Bool) async throws -> KernelSummary
    func setVerifiedRemoteArchive(_ request: VerifiedKernelArchiveRequest) async throws -> KernelSummary
}

public protocol ConfigurationOperations: Sendable {
    func load() async throws -> SystemConfiguration
    func validate(_ configuration: SystemConfiguration) async -> [ValidationIssue]
    func preview(_ configuration: SystemConfiguration) async throws -> String
    func save(_ configuration: SystemConfiguration) async throws -> ConfigurationSaveReport
    func apply(_ request: ConfigurationApplyRequest) async throws -> ConfigurationApplyReport
    func export(_ configuration: SystemConfiguration, destination: URL) async throws
}
