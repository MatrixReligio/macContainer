import ContainerAPIClient
import ContainerBuild
import ContainerImagesServiceClient
import ContainerizationError
import ContainerizationOCI
import ContainerPersistence
import Foundation
import Logging
import MCModel
import NIOCore
import NIOPosix

public enum AppleBuildBackendError: Error, Equatable, Sendable {
    case invalidBuildIdentifier
    case invalidOutput
    case rejectedArchiveMembers
    case missingBuildOutput
    case builderUnavailable
}

public struct AppleBuildBackend: BuildBackend, Sendable {
    private let makeClient: @Sendable () -> ContainerClient
    private let builder: any BuilderBackend
    private let port: UInt32

    public init() {
        makeClient = { ContainerClient() }
        builder = AppleBuilderBackend()
        port = 8088
    }

    public init(
        client: ContainerClient,
        builder: any BuilderBackend = AppleBuilderBackend(),
        port: UInt32 = 8088
    ) {
        makeClient = { client }
        self.builder = builder
        self.port = port
    }

    init(
        makeClient: @escaping @Sendable () -> ContainerClient,
        builder: any BuilderBackend,
        port: UInt32 = 8088
    ) {
        self.makeClient = makeClient
        self.builder = builder
        self.port = port
    }

    public func build(
        _ plan: BuildPlan,
        progress: @escaping @Sendable (BuildProgress) async -> Void
    ) async throws {
        guard UUID(uuidString: plan.id) != nil else {
            throw AppleBuildBackendError.invalidBuildIdentifier
        }
        let systemConfiguration: ContainerSystemConfig = try await ConfigurationLoader.load()
        try await ensureBuilder(systemConfiguration: systemConfiguration, progress: progress)
        try Task.checkCancellation()

        let health = try await ClientHealthCheck.ping(timeout: .seconds(10))
        let temporaryDirectory = health.appRoot
            .appendingPathComponent("builder")
            .appendingPathComponent(plan.id)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let output = try Self.output(from: plan.outputs, temporaryDirectory: temporaryDirectory)
        let tags = try Self.normalizedTags(plan.tags.isEmpty ? [plan.id] : plan.tags)
        let configuration = try Builder.BuildConfig(
            buildID: plan.id,
            contentStore: RemoteContentStoreClient(),
            buildArgs: plan.buildArguments.map { "\($0.key)=\($0.value)" },
            secrets: plan.secrets,
            contextDir: plan.context.path,
            dockerfile: plan.dockerfile,
            dockerignore: plan.dockerignore,
            labels: [],
            noCache: false,
            platforms: plan.platforms.map { try Platform(from: $0) },
            terminal: nil,
            tags: tags,
            target: "",
            quiet: true,
            exports: [output.export],
            cacheIn: plan.cacheImports,
            cacheOut: plan.cacheExports,
            pull: false,
            containerSystemConfig: systemConfiguration
        )

        await progress(BuildProgress(phase: "connect", message: "Connecting to builder", fractionCompleted: 0.1))
        let connection = try await connect()
        await progress(BuildProgress(phase: "build", message: "Building image", fractionCompleted: 0.2))
        try await withAsyncCleanup(
            connection,
            cleanup: { connection in await connection.shutdown() },
            operation: { connection in try await connection.builder.build(configuration) }
        )
        try Task.checkCancellation()
        await progress(BuildProgress(phase: "export", message: "Finalizing build output", fractionCompleted: 0.9))
        try await finalize(output, tags: tags)
        await progress(BuildProgress(phase: "complete", message: "Build complete", fractionCompleted: 1))
    }

    private func ensureBuilder(
        systemConfiguration: ContainerSystemConfig,
        progress: @escaping @Sendable (BuildProgress) async -> Void
    ) async throws {
        let current = try await builder.status()
        guard current.state != .running else {
            return
        }
        await progress(BuildProgress(phase: "builder", message: "Starting builder", fractionCompleted: 0))
        _ = try await builder.start(
            resources: RuntimeResources(
                cpuCount: systemConfiguration.build.cpus,
                memoryBytes: Int64(
                    clamping: systemConfiguration.build.memory.toUInt64(unit: .bytes)
                )
            )
        )
    }

    private func connect() async throws -> BuilderConnection {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(300))
        repeat {
            try Task.checkCancellation()
            do {
                let client = makeClient()
                let socket = try await client.dial(id: AppleBuilderBackend.identifier, port: port)
                let group = MultiThreadedEventLoopGroup(numberOfThreads: max(1, System.coreCount))
                do {
                    let builder = try Builder(
                        socket: socket,
                        group: group,
                        logger: Logger(label: "container.matrixreligio.com.builder")
                    )
                    _ = try await builder.info()
                    return BuilderConnection(builder: builder, group: group, socket: socket)
                } catch {
                    try? await group.shutdownGracefully()
                    try? socket.close()
                    throw error
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try await Task.sleep(for: .seconds(1))
            }
        } while clock.now < deadline
        throw AppleBuildBackendError.builderUnavailable
    }

    private func finalize(_ output: PreparedBuildOutput, tags: [String]) async throws {
        switch output.type {
        case "oci":
            let result = try await ClientImage.load(from: output.temporary.path, force: false)
            guard result.rejectedMembers.isEmpty else {
                throw AppleBuildBackendError.rejectedArchiveMembers
            }
            for image in result.images {
                try Task.checkCancellation()
                try await image.unpack(platform: nil)
                for tag in tags {
                    try await image.tag(new: tag)
                }
            }
        case "tar":
            guard let destination = output.destination else {
                throw AppleBuildBackendError.invalidOutput
            }
            try FileManager.default.moveItem(at: output.temporary, to: destination)
        case "local":
            guard let destination = output.destination,
                  FileManager.default.fileExists(atPath: output.temporary.path)
            else {
                throw AppleBuildBackendError.missingBuildOutput
            }
            try FileManager.default.copyItem(at: output.temporary, to: destination)
        default:
            throw AppleBuildBackendError.invalidOutput
        }
    }

    private static func normalizedTags(_ tags: [String]) throws -> [String] {
        try tags.map { tag in
            let reference = try Reference.parse(tag)
            reference.normalize()
            return reference.description
        }
    }

    private static func output(
        from fields: [KeyValue],
        temporaryDirectory: URL
    ) throws -> PreparedBuildOutput {
        var values: [String: String] = [:]
        for field in fields {
            guard values.updateValue(field.value, forKey: field.key) == nil else {
                throw AppleBuildBackendError.invalidOutput
            }
        }
        let type = values.removeValue(forKey: "type") ?? "oci"
        let destination = values.removeValue(forKey: "dest").map(URL.init(fileURLWithPath:))
        guard ["oci", "tar", "local"].contains(type),
              type == "oci" || destination != nil
        else {
            throw AppleBuildBackendError.invalidOutput
        }
        let temporary = temporaryDirectory.appendingPathComponent(type == "local" ? "local" : "out.tar")
        var rawFields = ["type=\(type)"]
        rawFields.append(contentsOf: values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })
        let export = Builder.BuildExport(
            type: type,
            destination: temporary,
            additionalFields: values,
            rawValue: rawFields.joined(separator: ",")
        )
        return PreparedBuildOutput(
            type: type,
            destination: destination,
            temporary: temporary,
            export: export
        )
    }
}

private struct BuilderConnection: Sendable {
    let builder: Builder
    let group: MultiThreadedEventLoopGroup
    let socket: FileHandle

    func shutdown() async {
        try? await group.shutdownGracefully()
        try? socket.close()
    }
}

func withAsyncCleanup<Resource: Sendable, Result: Sendable>(
    _ resource: Resource,
    cleanup: @escaping @Sendable (Resource) async -> Void,
    operation: @escaping @Sendable (Resource) async throws -> Result
) async throws -> Result {
    do {
        let result = try await operation(resource)
        await Task.detached { await cleanup(resource) }.value
        return result
    } catch {
        await Task.detached { await cleanup(resource) }.value
        throw error
    }
}

private struct PreparedBuildOutput: Sendable {
    let type: String
    let destination: URL?
    let temporary: URL
    let export: Builder.BuildExport
}
