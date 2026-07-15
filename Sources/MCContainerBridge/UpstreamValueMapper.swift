import Foundation
import MCModel

public struct ContainerCreatePlan: Equatable, Sendable {
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
    public let autoRemove: Bool
}

public struct ContainerProcessPlan: Equatable, Sendable {
    public let containerID: String
    public let processID: String
    public let arguments: [String]
    public let environment: [KeyValue]
    public let workingDirectory: String?
    public let user: String?
    public let terminal: Bool
    public let interactive: Bool
}

public struct BackendContainerStats: Equatable, Sendable {
    public let id: String
    public let timestamp: Date
    public let cpuUsageMicroseconds: UInt64
    public let memoryBytes: UInt64
    public let networkReceiveBytes: UInt64
    public let networkTransmitBytes: UInt64

    public init(
        id: String,
        timestamp: Date,
        cpuUsageMicroseconds: UInt64,
        memoryBytes: UInt64,
        networkReceiveBytes: UInt64,
        networkTransmitBytes: UInt64
    ) {
        self.id = id
        self.timestamp = timestamp
        self.cpuUsageMicroseconds = cpuUsageMicroseconds
        self.memoryBytes = memoryBytes
        self.networkReceiveBytes = networkReceiveBytes
        self.networkTransmitBytes = networkTransmitBytes
    }
}

public enum UpstreamValueMapper {
    public static func containerCreatePlan(
        from request: ContainerCreateRequest,
        autoRemove: Bool = false
    ) -> ContainerCreatePlan {
        ContainerCreatePlan(
            name: request.name,
            imageReference: request.imageReference,
            arguments: request.arguments,
            environment: request.environment,
            resources: request.resources,
            mounts: request.mounts,
            networks: request.networks,
            publishedPorts: request.publishedPorts,
            platform: request.platform,
            workingDirectory: request.workingDirectory,
            readOnlyRoot: request.readOnlyRoot,
            capabilitiesToAdd: request.capabilitiesToAdd,
            capabilitiesToDrop: request.capabilitiesToDrop,
            temporaryFilesystems: request.temporaryFilesystems,
            dnsServers: request.dnsServers,
            noDNS: request.noDNS,
            nestedVirtualization: request.nestedVirtualization,
            autoRemove: autoRemove
        )
    }

    public static func containerProcessPlan(
        from request: ProcessRequest,
        resolvedContainerID: String,
        processID: String
    ) -> ContainerProcessPlan {
        ContainerProcessPlan(
            containerID: resolvedContainerID,
            processID: processID,
            arguments: request.arguments,
            environment: request.environment,
            workingDirectory: request.workingDirectory,
            user: request.user,
            terminal: request.tty,
            interactive: request.interactive
        )
    }
}
