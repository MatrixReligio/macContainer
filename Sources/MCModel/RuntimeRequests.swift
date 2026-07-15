import Foundation

public struct ContainerCreateRequest: Codable, Equatable, Sendable {
    public let name: String
    public let imageReference: String
    public let arguments: [String]
    public let environment: [KeyValue]
    public let resources: RuntimeResources
    public let mounts: [Mount]
    public let networks: [String]
    public let publishedPorts: [PortMapping]
    public let platform: String?
    public let workingDirectory: String?
    public let readOnlyRoot: Bool
    public let capabilitiesToAdd: [String]
    public let capabilitiesToDrop: [String]
    public let temporaryFilesystems: [String]
    public let dnsServers: [String]
    public let noDNS: Bool
    public let nestedVirtualization: Bool

    public init(
        name: String,
        imageReference: String,
        arguments: [String] = [],
        environment: [KeyValue] = [],
        resources: RuntimeResources,
        mounts: [Mount] = [],
        networks: [String] = [],
        publishedPorts: [PortMapping] = [],
        platform: String? = nil,
        workingDirectory: String? = nil,
        readOnlyRoot: Bool = false,
        capabilitiesToAdd: [String] = [],
        capabilitiesToDrop: [String] = [],
        temporaryFilesystems: [String] = [],
        dnsServers: [String] = [],
        noDNS: Bool = false,
        nestedVirtualization: Bool = false
    ) {
        self.name = name
        self.imageReference = imageReference
        self.arguments = arguments
        self.environment = environment
        self.resources = resources
        self.mounts = mounts
        self.networks = networks
        self.publishedPorts = publishedPorts
        self.platform = platform
        self.workingDirectory = workingDirectory
        self.readOnlyRoot = readOnlyRoot
        self.capabilitiesToAdd = capabilitiesToAdd
        self.capabilitiesToDrop = capabilitiesToDrop
        self.temporaryFilesystems = temporaryFilesystems
        self.dnsServers = dnsServers
        self.noDNS = noDNS
        self.nestedVirtualization = nestedVirtualization
    }
}

public struct ContainerRunRequest: Codable, Equatable, Sendable {
    public let create: ContainerCreateRequest
    public let attach: Bool
    public let removeAfterExit: Bool

    public init(create: ContainerCreateRequest, attach: Bool, removeAfterExit: Bool) {
        self.create = create
        self.attach = attach
        self.removeAfterExit = removeAfterExit
    }
}

public struct ProcessRequest: Codable, Equatable, Sendable {
    public let resourceID: String
    public let arguments: [String]
    public let environment: [KeyValue]
    public let workingDirectory: String?
    public let user: String?
    public let tty: Bool
    public let interactive: Bool

    public init(
        resourceID: String,
        arguments: [String],
        environment: [KeyValue] = [],
        workingDirectory: String? = nil,
        user: String? = nil,
        tty: Bool = false,
        interactive: Bool = false
    ) {
        self.resourceID = resourceID
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.user = user
        self.tty = tty
        self.interactive = interactive
    }
}

public struct LogOptions: Codable, Equatable, Sendable {
    public let follow: Bool
    public let tail: Int?
    public let since: Date?
    public let timestamps: Bool

    public init(follow: Bool = false, tail: Int? = nil, since: Date? = nil, timestamps: Bool = true) {
        self.follow = follow
        self.tail = tail
        self.since = since
        self.timestamps = timestamps
    }
}

public enum CopyEndpoint: Codable, Equatable, Sendable {
    case local(URL)
    case container(id: String, path: String)
}

public struct CopyRequest: Codable, Equatable, Sendable {
    public let source: CopyEndpoint
    public let destination: CopyEndpoint

    public init(source: CopyEndpoint, destination: CopyEndpoint) {
        self.source = source
        self.destination = destination
    }
}

public struct ImageTransferRequest: Codable, Equatable, Sendable {
    public let reference: String
    public let platform: String?
    public let unpack: Bool

    public init(reference: String, platform: String? = nil, unpack: Bool = true) {
        self.reference = reference
        self.platform = platform
        self.unpack = unpack
    }
}

public struct BuildSecretReference: Codable, Equatable, Sendable {
    public let id: String
    public let environmentVariable: String?
    public let source: URL?

    public init(id: String, environmentVariable: String? = nil, source: URL? = nil) {
        self.id = id
        self.environmentVariable = environmentVariable
        self.source = source
    }
}

public struct BuildRequest: Codable, Equatable, Sendable {
    public let context: URL
    public let dockerfile: URL?
    public let tags: [String]
    public let platforms: [String]
    public let buildArguments: [KeyValue]
    public let secretReferences: [BuildSecretReference]
    public let outputs: [KeyValue]
    public let cacheImports: [String]
    public let cacheExports: [String]

    public init(
        context: URL,
        dockerfile: URL? = nil,
        tags: [String] = [],
        platforms: [String] = [],
        buildArguments: [KeyValue] = [],
        secretReferences: [BuildSecretReference] = [],
        outputs: [KeyValue] = [],
        cacheImports: [String] = [],
        cacheExports: [String] = []
    ) {
        self.context = context
        self.dockerfile = dockerfile
        self.tags = tags
        self.platforms = platforms
        self.buildArguments = buildArguments
        self.secretReferences = secretReferences
        self.outputs = outputs
        self.cacheImports = cacheImports
        self.cacheExports = cacheExports
    }
}

public struct BuilderStartRequest: Codable, Equatable, Sendable {
    public let resources: RuntimeResources

    public init(resources: RuntimeResources) {
        self.resources = resources
    }
}

public struct NetworkCreateRequest: Codable, Equatable, Sendable {
    public let name: String
    public let subnet: String?
    public let gateway: String?
    public let dnsServers: [String]
    public let labels: [String: String]

    public init(
        name: String,
        subnet: String? = nil,
        gateway: String? = nil,
        dnsServers: [String] = [],
        labels: [String: String] = [:]
    ) {
        self.name = name
        self.subnet = subnet
        self.gateway = gateway
        self.dnsServers = dnsServers
        self.labels = labels
    }
}

public struct VolumeCreateRequest: Codable, Equatable, Sendable {
    public let name: String
    public let labels: [String: String]

    public init(name: String, labels: [String: String] = [:]) {
        self.name = name
        self.labels = labels
    }
}

public struct RegistryLoginRequest: Equatable, Sendable {
    public let server: String
    public let username: String
    public let password: Data

    public init(server: String, username: String, password: Data) {
        self.server = server
        self.username = username
        self.password = password
    }
}

public struct HomeSharingConsent: Codable, Equatable, Sendable {
    public let token: UUID

    public init(token: UUID) {
        self.token = token
    }
}

public struct MachineCreateRequest: Codable, Equatable, Sendable {
    public let name: String
    public let imageReference: String?
    public let resources: RuntimeResources
    public let homeMount: String
    public let homeSharingConsent: HomeSharingConsent?
    public let networks: [String]
    public let kernelIdentifier: String?
    public let nestedVirtualization: Bool

    public init(
        name: String,
        imageReference: String? = nil,
        resources: RuntimeResources,
        homeMount: String = "none",
        homeSharingConsent: HomeSharingConsent? = nil,
        networks: [String] = [],
        kernelIdentifier: String? = nil,
        nestedVirtualization: Bool = false
    ) {
        self.name = name
        self.imageReference = imageReference
        self.resources = resources
        self.homeMount = homeMount
        self.homeSharingConsent = homeSharingConsent
        self.networks = networks
        self.kernelIdentifier = kernelIdentifier
        self.nestedVirtualization = nestedVirtualization
    }
}

public struct MachineRunRequest: Codable, Equatable, Sendable {
    public let create: MachineCreateRequest
    public let process: ProcessRequest

    public init(create: MachineCreateRequest, process: ProcessRequest) {
        self.create = create
        self.process = process
    }
}

public struct MachineSetRequest: Codable, Equatable, Sendable {
    public let resources: RuntimeResources?
    public let homeMount: String?
    public let homeSharingConsent: HomeSharingConsent?
    public let nestedVirtualization: Bool?

    public init(
        resources: RuntimeResources? = nil,
        homeMount: String? = nil,
        homeSharingConsent: HomeSharingConsent? = nil,
        nestedVirtualization: Bool? = nil
    ) {
        self.resources = resources
        self.homeMount = homeMount
        self.homeSharingConsent = homeSharingConsent
        self.nestedVirtualization = nestedVirtualization
    }
}

public struct SystemStartRequest: Codable, Equatable, Sendable {
    public let healthTimeoutSeconds: Int

    public init(healthTimeoutSeconds: Int = 30) {
        self.healthTimeoutSeconds = healthTimeoutSeconds
    }
}

public struct SystemStopRequest: Codable, Equatable, Sendable {
    public let stopActiveWorkloads: Bool
    public let timeoutSeconds: Int

    public init(stopActiveWorkloads: Bool = false, timeoutSeconds: Int = 30) {
        self.stopActiveWorkloads = stopActiveWorkloads
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct DNSCreateRequest: Codable, Equatable, Sendable {
    public let name: String
    public let addresses: [String]

    public init(name: String, addresses: [String]) {
        self.name = name
        self.addresses = addresses
    }
}

public struct VerifiedKernelArchiveRequest: Codable, Equatable, Sendable {
    public let url: URL
    public let expectedSHA256: String
    public let allowedHosts: [String]
    public let platform: String
    public let force: Bool

    public init(
        url: URL,
        expectedSHA256: String,
        allowedHosts: [String],
        platform: String,
        force: Bool = false
    ) {
        self.url = url
        self.expectedSHA256 = expectedSHA256
        self.allowedHosts = allowedHosts
        self.platform = platform
        self.force = force
    }
}

public struct ConfigurationApplyRequest: Codable, Equatable, Sendable {
    public let configuration: SystemConfiguration
    public let idleConfirmationToken: UUID

    public init(configuration: SystemConfiguration, idleConfirmationToken: UUID) {
        self.configuration = configuration
        self.idleConfirmationToken = idleConfirmationToken
    }
}
