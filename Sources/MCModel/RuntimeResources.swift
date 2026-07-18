import Foundation

public enum RuntimeResourceState: String, Codable, Equatable, Sendable {
    case stopped
    case starting
    case running
    case stopping
    case failed
    case unknown
}

public struct RuntimeResources: Codable, Equatable, Sendable {
    public let cpuCount: Int
    public let memoryBytes: Int64
    public let diskBytes: Int64?

    public init(cpuCount: Int, memoryBytes: Int64, diskBytes: Int64? = nil) {
        self.cpuCount = cpuCount
        self.memoryBytes = memoryBytes
        self.diskBytes = diskBytes
    }
}

public struct ContainerSummary: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let imageReference: String
    public let state: RuntimeResourceState
    public let createdAt: Date?

    public init(
        id: String,
        name: String,
        imageReference: String,
        state: RuntimeResourceState,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.imageReference = imageReference
        self.state = state
        self.createdAt = createdAt
    }
}

public struct ContainerDetail: Codable, Equatable, Sendable {
    public let summary: ContainerSummary
    public let resources: RuntimeResources
    public let networks: [String]
    public let mounts: [Mount]
    public let redactedMetadata: [String: String]

    public init(
        summary: ContainerSummary,
        resources: RuntimeResources,
        networks: [String] = [],
        mounts: [Mount] = [],
        redactedMetadata: [String: String] = [:]
    ) {
        self.summary = summary
        self.resources = resources
        self.networks = networks
        self.mounts = mounts
        self.redactedMetadata = redactedMetadata
    }
}

public struct ContainerRunResult: Codable, Equatable, Sendable {
    public let container: ContainerSummary
    public let processExit: ProcessExit?
    public let cleanupError: UserFacingError?

    public init(container: ContainerSummary, processExit: ProcessExit? = nil, cleanupError: UserFacingError? = nil) {
        self.container = container
        self.processExit = processExit
        self.cleanupError = cleanupError
    }
}

public struct ImageSummary: Codable, Equatable, Sendable {
    public let reference: String
    public let digest: String?
    public let sizeBytes: Int64?
    public let createdAt: Date?

    public init(reference: String, digest: String? = nil, sizeBytes: Int64? = nil, createdAt: Date? = nil) {
        self.reference = reference
        self.digest = digest
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
    }
}

public struct ImageDetail: Codable, Equatable, Sendable {
    public let summary: ImageSummary
    public let platforms: [String]
    public let exposedPorts: [UInt16]
    public let redactedMetadata: [String: String]

    public init(
        summary: ImageSummary,
        platforms: [String] = [],
        exposedPorts: [UInt16] = [],
        redactedMetadata: [String: String] = [:]
    ) {
        self.summary = summary
        self.platforms = platforms
        self.exposedPorts = exposedPorts
        self.redactedMetadata = redactedMetadata
    }
}

public struct BuilderSummary: Codable, Equatable, Sendable {
    public let state: RuntimeResourceState
    public let resources: RuntimeResources?

    public init(state: RuntimeResourceState, resources: RuntimeResources? = nil) {
        self.state = state
        self.resources = resources
    }
}

public struct NetworkSummary: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let state: RuntimeResourceState
    public let builtIn: Bool

    public init(id: String, name: String, state: RuntimeResourceState, builtIn: Bool = false) {
        self.id = id
        self.name = name
        self.state = state
        self.builtIn = builtIn
    }
}

public struct NetworkDetail: Codable, Equatable, Sendable {
    public let summary: NetworkSummary
    public let subnet: String?
    public let ipv6Subnet: String?
    public let gateway: String?
    public let dnsServers: [String]
    public let plugin: String?
    public let mode: String?
    public let labels: [String: String]
    public let options: [String: String]

    public init(
        summary: NetworkSummary,
        subnet: String? = nil,
        ipv6Subnet: String? = nil,
        gateway: String? = nil,
        dnsServers: [String] = [],
        plugin: String? = nil,
        mode: String? = nil,
        labels: [String: String] = [:],
        options: [String: String] = [:]
    ) {
        self.summary = summary
        self.subnet = subnet
        self.ipv6Subnet = ipv6Subnet
        self.gateway = gateway
        self.dnsServers = dnsServers
        self.plugin = plugin
        self.mode = mode
        self.labels = labels
        self.options = options
    }
}

public struct VolumeSummary: Codable, Equatable, Sendable {
    public let name: String
    public let createdAt: Date?

    public init(name: String, createdAt: Date? = nil) {
        self.name = name
        self.createdAt = createdAt
    }
}

public struct VolumeDetail: Codable, Equatable, Sendable {
    public let summary: VolumeSummary
    public let source: String?
    public let labels: [String: String]
    public let driver: String?
    public let options: [String: String]
    public let sizeBytes: Int64?

    public init(
        summary: VolumeSummary,
        source: String? = nil,
        labels: [String: String] = [:],
        driver: String? = nil,
        options: [String: String] = [:],
        sizeBytes: Int64? = nil
    ) {
        self.summary = summary
        self.source = source
        self.labels = labels
        self.driver = driver
        self.options = options
        self.sizeBytes = sizeBytes
    }
}

public struct RegistrySummary: Codable, Equatable, Sendable {
    public let server: String
    public let username: String?

    public init(server: String, username: String? = nil) {
        self.server = server
        self.username = username
    }
}

public struct MachineSummary: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let state: RuntimeResourceState
    public let resources: RuntimeResources
    public let isDefault: Bool

    public init(
        id: String,
        name: String,
        state: RuntimeResourceState,
        resources: RuntimeResources,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.state = state
        self.resources = resources
        self.isDefault = isDefault
    }
}

public struct MachineDetail: Codable, Equatable, Sendable {
    public let summary: MachineSummary
    public let imageReference: String?
    public let homeMount: String
    public let networks: [String]
    public let kernelIdentifier: String?
    public let nestedVirtualization: Bool

    public init(
        summary: MachineSummary,
        imageReference: String? = nil,
        homeMount: String = "none",
        networks: [String] = [],
        kernelIdentifier: String? = nil,
        nestedVirtualization: Bool = false
    ) {
        self.summary = summary
        self.imageReference = imageReference
        self.homeMount = homeMount
        self.networks = networks
        self.kernelIdentifier = kernelIdentifier
        self.nestedVirtualization = nestedVirtualization
    }
}

public struct SystemSummary: Codable, Equatable, Sendable {
    public let state: RuntimeResourceState
    public let activeContainers: Int
    public let activeMachines: Int

    public init(state: RuntimeResourceState, activeContainers: Int = 0, activeMachines: Int = 0) {
        self.state = state
        self.activeContainers = activeContainers
        self.activeMachines = activeMachines
    }
}

public struct RuntimeVersionSummary: Codable, Equatable, Sendable {
    public let version: String
    public let apiVersion: String?

    public init(version: String, apiVersion: String? = nil) {
        self.version = version
        self.apiVersion = apiVersion
    }
}

public struct DNSEntry: Codable, Equatable, Sendable {
    public let name: String
    public let addresses: [String]

    public init(name: String, addresses: [String]) {
        self.name = name
        self.addresses = addresses
    }
}

public struct KernelSummary: Codable, Equatable, Sendable {
    public let identifier: String
    public let platform: String
    public let digest: String?

    public init(identifier: String, platform: String, digest: String? = nil) {
        self.identifier = identifier
        self.platform = platform
        self.digest = digest
    }
}

public struct BatchItemResult: Codable, Equatable, Sendable {
    public let id: String
    public let succeeded: Bool
    public let error: UserFacingError?

    public init(id: String, succeeded: Bool, error: UserFacingError? = nil) {
        self.id = id
        self.succeeded = succeeded
        self.error = error
    }
}

public struct PruneResult: Codable, Equatable, Sendable {
    public let deletedIDs: [String]
    public let reclaimedBytes: Int64

    public init(deletedIDs: [String] = [], reclaimedBytes: Int64 = 0) {
        self.deletedIDs = deletedIDs
        self.reclaimedBytes = reclaimedBytes
    }
}

public struct LogRecord: Codable, Equatable, Sendable {
    public let timestamp: Date?
    public let stream: String
    public let bytes: Data

    public init(timestamp: Date? = nil, stream: String, bytes: Data) {
        self.timestamp = timestamp
        self.stream = stream
        self.bytes = bytes
    }
}

public struct ContainerStats: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let cpuFraction: Double
    public let memoryBytes: Int64
    public let networkReceiveBytes: Int64
    public let networkTransmitBytes: Int64

    public init(
        timestamp: Date,
        cpuFraction: Double,
        memoryBytes: Int64,
        networkReceiveBytes: Int64 = 0,
        networkTransmitBytes: Int64 = 0
    ) {
        self.timestamp = timestamp
        self.cpuFraction = cpuFraction
        self.memoryBytes = memoryBytes
        self.networkReceiveBytes = networkReceiveBytes
        self.networkTransmitBytes = networkTransmitBytes
    }
}

public struct TransferProgress: Codable, Equatable, Sendable {
    public let phase: String
    public let completedBytes: Int64
    public let totalBytes: Int64?
    public let completedLayers: Int
    public let totalLayers: Int?

    public init(
        phase: String,
        completedBytes: Int64,
        totalBytes: Int64? = nil,
        completedLayers: Int = 0,
        totalLayers: Int? = nil
    ) {
        self.phase = phase
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.completedLayers = completedLayers
        self.totalLayers = totalLayers
    }
}

public struct BuildProgress: Codable, Equatable, Sendable {
    public let phase: String
    public let message: String
    public let fractionCompleted: Double?

    public init(phase: String, message: String, fractionCompleted: Double? = nil) {
        self.phase = phase
        self.message = message
        self.fractionCompleted = fractionCompleted
    }
}

public struct DiskUsageSummary: Codable, Equatable, Sendable {
    public let containersBytes: Int64
    public let imagesBytes: Int64
    public let volumesBytes: Int64
    public let reclaimableBytes: Int64

    public init(
        containersBytes: Int64 = 0,
        imagesBytes: Int64 = 0,
        volumesBytes: Int64 = 0,
        reclaimableBytes: Int64 = 0
    ) {
        self.containersBytes = containersBytes
        self.imagesBytes = imagesBytes
        self.volumesBytes = volumesBytes
        self.reclaimableBytes = reclaimableBytes
    }
}

public struct SystemConfiguration: Codable, Equatable, Sendable {
    public static let empty = Self(values: [:])

    public var values: [String: String]

    public init(values: [String: String]) {
        self.values = values
    }
}

public struct ConfigurationSaveReport: Codable, Equatable, Sendable {
    public let destination: URL
    public let lastKnownGoodPreserved: Bool

    public init(destination: URL, lastKnownGoodPreserved: Bool) {
        self.destination = destination
        self.lastKnownGoodPreserved = lastKnownGoodPreserved
    }
}

public struct ConfigurationApplyReport: Codable, Equatable, Sendable {
    public let restarted: Bool
    public let restoredLastKnownGood: Bool

    public init(restarted: Bool, restoredLastKnownGood: Bool = false) {
        self.restarted = restarted
        self.restoredLastKnownGood = restoredLastKnownGood
    }
}

public struct RuntimeHealth: Codable, Equatable, Sendable {
    public let healthy: Bool
    public let version: String?

    public init(healthy: Bool, version: String? = nil) {
        self.healthy = healthy
        self.version = version
    }
}
