import ContainerAPIClient
import ContainerBuild
import ContainerizationError
import ContainerizationOCI
import ContainerPersistence
import ContainerResource
import Foundation
import MCModel

public enum AppleBuilderBackendError: Error, Equatable, Sendable {
    case invalidResources
    case missingBuiltInNetwork
    case stopping
}

public struct AppleBuilderBackend: BuilderBackend, Sendable {
    public static let identifier = Builder.builderContainerId

    private let makeClient: @Sendable () -> ContainerClient

    public init() {
        makeClient = { ContainerClient() }
    }

    public init(client: ContainerClient) {
        makeClient = { client }
    }

    init(makeClient: @escaping @Sendable () -> ContainerClient) {
        self.makeClient = makeClient
    }

    public func start(resources: RuntimeResources) async throws -> BuilderSummary {
        let client = makeClient()
        guard resources.cpuCount > 0,
              resources.memoryBytes > 0,
              resources.diskBytes.map({ $0 > 0 }) ?? true
        else {
            throw AppleBuilderBackendError.invalidResources
        }
        let systemConfiguration: ContainerSystemConfig = try await ConfigurationLoader.load()
        let existing: ContainerSnapshot?
        do {
            existing = try await client.get(id: Self.identifier)
        } catch let error as ContainerizationError where error.code == .notFound {
            existing = nil
        }
        if let existing {
            switch existing.status {
            case .running where Self.matches(
                existing,
                resources: resources,
                systemConfiguration: systemConfiguration
            ):
                return Self.summary(existing)
            case .stopped where Self.matches(
                existing,
                resources: resources,
                systemConfiguration: systemConfiguration
            ):
                try await bootstrap(client: client)
                return try await status(client: client)
            case .running:
                try await client.stop(id: Self.identifier)
                try await client.delete(id: Self.identifier)
            case .stopped, .unknown:
                try await client.delete(id: Self.identifier)
            case .stopping:
                throw AppleBuilderBackendError.stopping
            }
        }

        try await create(
            resources: resources,
            systemConfiguration: systemConfiguration,
            client: client
        )
        do {
            try await bootstrap(client: client)
            return try await status(client: client)
        } catch {
            try? await client.stop(id: Self.identifier)
            try? await client.delete(id: Self.identifier, force: true)
            throw error
        }
    }

    public func status() async throws -> BuilderSummary {
        try await status(client: makeClient())
    }

    private func status(client: ContainerClient) async throws -> BuilderSummary {
        do {
            return try await Self.summary(client.get(id: Self.identifier))
        } catch let error as ContainerizationError where error.code == .notFound {
            return BuilderSummary(state: .stopped)
        }
    }

    public func stop() async throws {
        let client = makeClient()
        do {
            let existing = try await client.get(id: Self.identifier)
            if existing.status != .stopped {
                try await client.stop(id: Self.identifier)
            }
        } catch let error as ContainerizationError where error.code == .notFound {
            return
        }
    }

    public func delete() async throws {
        let client = makeClient()
        do {
            let existing = try await client.get(id: Self.identifier)
            if existing.status != .stopped {
                try await client.stop(id: Self.identifier)
            }
            try await client.delete(id: Self.identifier)
        } catch let error as ContainerizationError where error.code == .notFound {
            return
        }
    }

    private func create(
        resources: RuntimeResources,
        systemConfiguration: ContainerSystemConfig,
        client: ContainerClient
    ) async throws {
        let platform = Platform(arch: "arm64", os: "linux", variant: "v8")
        let image = try await ClientImage.fetch(
            reference: systemConfiguration.build.image,
            platform: platform,
            containerSystemConfig: systemConfiguration
        )
        _ = try await image.getCreateSnapshot(platform: platform)

        let imageConfiguration = try await image.config(for: platform).config
        let process = ProcessConfiguration(
            executable: "/usr/local/bin/container-builder-shim",
            arguments: [
                "--debug",
                "--vsock",
                systemConfiguration.build.rosetta ? nil : "--enable-qemu"
            ].compactMap(\.self),
            environment: imageConfiguration?.env ?? [],
            workingDirectory: "/",
            terminal: false,
            user: .id(uid: 0, gid: 0)
        )
        var configuration = ContainerConfiguration(
            id: Self.identifier,
            image: ImageDescription(
                reference: systemConfiguration.build.image,
                descriptor: image.descriptor
            ),
            process: process
        )
        configuration.platform = platform
        configuration.resources.cpus = resources.cpuCount
        configuration.resources.memoryInBytes = UInt64(resources.memoryBytes)
        configuration.resources.storage = resources.diskBytes.map(UInt64.init)
        configuration.labels = [
            ResourceLabelKeys.plugin: "builder",
            ResourceLabelKeys.role: ResourceRoleValues.builder
        ]
        configuration.capAdd = ["ALL"]
        configuration.rosetta = systemConfiguration.build.rosetta

        let health = try await ClientHealthCheck.ping(timeout: .seconds(10))
        let exports = health.appRoot.appendingPathComponent("builder")
        try FileManager.default.createDirectory(
            at: exports,
            withIntermediateDirectories: true
        )
        configuration.mounts = [
            .tmpfs(destination: "/run", options: []),
            .virtiofs(
                source: exports.path,
                destination: "/var/lib/container-builder-shim/exports",
                options: []
            )
        ]

        let networkClient = NetworkClient()
        guard let network = try await networkClient.builtin else {
            throw AppleBuilderBackendError.missingBuiltInNetwork
        }
        configuration.networks = [
            AttachmentConfiguration(
                network: network.id,
                options: AttachmentOptions(hostname: Self.identifier)
            )
        ]
        configuration.dns = ContainerConfiguration.DNSConfiguration()
        let kernel = try await ClientKernel.getDefaultKernel(for: .current)
        try await client.create(
            configuration: configuration,
            options: .default,
            kernel: kernel
        )
    }

    private func bootstrap(client: ContainerClient) async throws {
        let process = try await client.bootstrap(
            id: Self.identifier,
            stdio: [nil, nil, nil],
            dynamicEnv: [:]
        )
        try await process.start()
    }

    private static func matches(
        _ snapshot: ContainerSnapshot,
        resources: RuntimeResources,
        systemConfiguration: ContainerSystemConfig
    ) -> Bool {
        snapshot.configuration.resources.cpus == resources.cpuCount
            && snapshot.configuration.resources.memoryInBytes == UInt64(resources.memoryBytes)
            && snapshot.configuration.resources.storage == resources.diskBytes.map(UInt64.init)
            && snapshot.configuration.image.reference == systemConfiguration.build.image
            && snapshot.configuration.rosetta == systemConfiguration.build.rosetta
    }

    private static func summary(_ snapshot: ContainerSnapshot) -> BuilderSummary {
        BuilderSummary(
            state: state(snapshot.status),
            resources: RuntimeResources(
                cpuCount: snapshot.configuration.resources.cpus,
                memoryBytes: Int64(clamping: snapshot.configuration.resources.memoryInBytes),
                diskBytes: snapshot.configuration.resources.storage.map(Int64.init(clamping:))
            )
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
}
