import Darwin
import Foundation
import MCModel

public struct BuildPlan: Equatable, Sendable {
    public let id: String
    public let context: URL
    public let dockerfile: Data
    public let dockerignore: Data?
    public let tags: [String]
    public let platforms: [String]
    public let buildArguments: [KeyValue]
    public let secrets: [String: Data]
    public let outputs: [KeyValue]
    public let cacheImports: [String]
    public let cacheExports: [String]

    public init(
        id: String,
        context: URL,
        dockerfile: Data,
        dockerignore: Data?,
        tags: [String],
        platforms: [String],
        buildArguments: [KeyValue],
        secrets: [String: Data],
        outputs: [KeyValue],
        cacheImports: [String],
        cacheExports: [String]
    ) {
        self.id = id
        self.context = context
        self.dockerfile = dockerfile
        self.dockerignore = dockerignore
        self.tags = tags
        self.platforms = platforms
        self.buildArguments = buildArguments
        self.secrets = secrets
        self.outputs = outputs
        self.cacheImports = cacheImports
        self.cacheExports = cacheExports
    }
}

public protocol BuildBackend: Sendable {
    func build(
        _ plan: BuildPlan,
        progress: @escaping @Sendable (BuildProgress) async -> Void
    ) async throws
}

public enum BuildAdapterError: Error, Equatable, Sendable {
    case contextIsNotDirectory
    case dockerfileNotFound
    case dockerfileOutsideContext
    case dockerfileTooLarge
    case invalidSecretReference(String)
    case secretNotFound(String)
}

public struct BuildAdapter: BuildOperations, Sendable {
    private static let maximumDockerfileBytes = 16 * 1024 - 1

    private let client: any BuildBackend
    private let coordinator: OperationCoordinator
    private let buildID: @Sendable () -> String

    public init(
        client: any BuildBackend = AppleBuildBackend(),
        coordinator: OperationCoordinator = OperationCoordinator(),
        buildID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.client = client
        self.coordinator = coordinator
        self.buildID = buildID
    }

    public func build(
        _ request: BuildRequest
    ) async throws -> AsyncThrowingStream<BuildProgress, any Error> {
        let access = SecurityScopedAccess(
            [request.context]
                + request.secretReferences.compactMap(\.source)
                + request.outputs.filter { $0.key == "dest" }.map {
                    URL(fileURLWithPath: $0.value)
                }
        )
        let plan: BuildPlan
        do {
            plan = try Self.plan(request, id: buildID())
        } catch {
            access.close()
            throw error
        }
        let redactor = BuildProgressRedactor(secretValues: Array(plan.secrets.values))
        let (stream, continuation) = AsyncThrowingStream<BuildProgress, any Error>.makeStream()
        let task = Task {
            defer { access.close() }
            do {
                try await coordinator.withLock(.builder) {
                    try await client.build(plan) { update in
                        await continuation.yield(redactor.map(update))
                    }
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private static func plan(_ request: BuildRequest, id: String) throws -> BuildPlan {
        let context = request.context.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard request.context.isFileURL,
              FileManager.default.fileExists(atPath: context.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw BuildAdapterError.contextIsNotDirectory
        }

        let dockerfile = try resolveDockerfile(request.dockerfile, context: context)
        let dockerfileData = try Data(contentsOf: dockerfile, options: .mappedIfSafe)
        guard dockerfileData.count <= maximumDockerfileBytes else {
            throw BuildAdapterError.dockerfileTooLarge
        }
        let dockerignore = try? Data(
            contentsOf: URL(fileURLWithPath: dockerfile.path + ".dockerignore"),
            options: .mappedIfSafe
        )
        return try BuildPlan(
            id: id,
            context: context,
            dockerfile: dockerfileData,
            dockerignore: dockerignore,
            tags: request.tags,
            platforms: request.platforms,
            buildArguments: request.buildArguments,
            secrets: loadSecrets(request.secretReferences),
            outputs: request.outputs,
            cacheImports: request.cacheImports,
            cacheExports: request.cacheExports
        )
    }

    private static func resolveDockerfile(_ requested: URL?, context: URL) throws -> URL {
        let candidate: URL
        if let requested {
            guard requested.isFileURL else {
                throw BuildAdapterError.dockerfileNotFound
            }
            candidate = requested.standardizedFileURL.resolvingSymlinksInPath()
        } else {
            let defaults = ["Dockerfile", "Containerfile"].map(context.appendingPathComponent)
            guard let found = defaults.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
                throw BuildAdapterError.dockerfileNotFound
            }
            candidate = found.resolvingSymlinksInPath()
        }
        guard isDescendant(candidate, of: context) else {
            throw BuildAdapterError.dockerfileOutsideContext
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            throw BuildAdapterError.dockerfileNotFound
        }
        return candidate
    }

    private static func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        return candidateComponents.count > rootComponents.count
            && Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }

    private static func loadSecrets(
        _ references: [BuildSecretReference]
    ) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for reference in references {
            guard !reference.id.isEmpty,
                  (reference.environmentVariable == nil) != (reference.source == nil)
            else {
                throw BuildAdapterError.invalidSecretReference(reference.id)
            }
            let value: Data
            if let name = reference.environmentVariable {
                guard let pointer = getenv(name) else {
                    throw BuildAdapterError.secretNotFound(reference.id)
                }
                value = Data(bytes: pointer, count: strlen(pointer))
            } else if let source = reference.source, source.isFileURL {
                guard let data = try? Data(contentsOf: source, options: .mappedIfSafe) else {
                    throw BuildAdapterError.secretNotFound(reference.id)
                }
                value = data
            } else {
                throw BuildAdapterError.secretNotFound(reference.id)
            }
            result[reference.id] = value
        }
        return result
    }
}

private actor BuildProgressRedactor {
    private let secretStrings: [String]
    private var fractionCompleted: Double?

    init(secretValues: [Data]) {
        secretStrings = secretValues.compactMap { String(data: $0, encoding: .utf8) }
            .filter { !$0.isEmpty }
    }

    func map(_ update: BuildProgress) -> BuildProgress {
        let proposed = update.fractionCompleted.map { min(max($0, 0), 1) }
        if let proposed {
            fractionCompleted = max(fractionCompleted ?? 0, proposed)
        }
        return BuildProgress(
            phase: redact(update.phase),
            message: redact(update.message),
            fractionCompleted: fractionCompleted
        )
    }

    private func redact(_ value: String) -> String {
        secretStrings.reduce(value) { result, secret in
            result.replacingOccurrences(of: secret, with: "<redacted>")
        }
    }
}
