import Foundation
import MCModel
import Virtualization

public struct MachineCreatePlan: Equatable, Sendable {
    public let name: String
    public let imageReference: String
    public let resources: RuntimeResources
    public let homeMount: String
    public let networks: [String]
    public let kernelURL: URL?
    public let nestedVirtualization: Bool

    public init(
        name: String,
        imageReference: String,
        resources: RuntimeResources,
        homeMount: String,
        networks: [String],
        kernelURL: URL?,
        nestedVirtualization: Bool
    ) {
        self.name = name
        self.imageReference = imageReference
        self.resources = resources
        self.homeMount = homeMount
        self.networks = networks
        self.kernelURL = kernelURL
        self.nestedVirtualization = nestedVirtualization
    }
}

public struct MachineSetPlan: Equatable, Sendable {
    public let resources: RuntimeResources?
    public let homeMount: String?
    public let nestedVirtualization: Bool?

    public init(
        resources: RuntimeResources?,
        homeMount: String?,
        nestedVirtualization: Bool?
    ) {
        self.resources = resources
        self.homeMount = homeMount
        self.nestedVirtualization = nestedVirtualization
    }
}

public struct MachineProcessPlan: Equatable, Sendable {
    public let machineID: String
    public let processID: String
    public let arguments: [String]
    public let environment: [KeyValue]
    public let workingDirectory: String?
    public let user: String?
    public let terminal: Bool
    public let interactive: Bool

    public init(
        machineID: String,
        processID: String,
        arguments: [String],
        environment: [KeyValue],
        workingDirectory: String?,
        user: String?,
        terminal: Bool,
        interactive: Bool
    ) {
        self.machineID = machineID
        self.processID = processID
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.user = user
        self.terminal = terminal
        self.interactive = interactive
    }
}

public protocol MachineBackend: Sendable {
    func create(_ plan: MachineCreatePlan) async throws -> MachineDetail
    func boot(id: String) async throws -> MachineDetail
    func list() async throws -> [MachineDetail]
    func inspect(id: String) async throws -> MachineDetail
    func set(id: String, plan: MachineSetPlan) async throws -> MachineDetail
    func setDefault(id: String) async throws
    func logs(id: String, options: LogOptions) async throws -> AsyncThrowingStream<LogRecord, any Error>
    func stop(id: String, force: Bool) async throws
    func delete(id: String, force: Bool) async throws
    func createProcess(_ plan: MachineProcessPlan) async throws -> any ContainerProcessTransport
}

public protocol MachineCapabilityChecking: Sendable {
    var nestedVirtualizationSupported: Bool { get }
}

public protocol MachineKernelResolving: Sendable {
    func resolve(identifier: String) async throws -> URL
}

public enum MachineAdapterError: Error, Equatable, Sendable {
    case imageRequired
    case invalidResources
    case invalidHomeMount(String)
    case homeSharingConsentRequired
    case homeSharingConsentAlreadyUsed
    case nestedVirtualizationUnsupported
    case customNetworksUnsupported
    case customDiskUnsupported
    case identifierNotFound(String)
    case ambiguousIdentifier(String)
}

public struct AppleMachineCapabilities: MachineCapabilityChecking {
    public var nestedVirtualizationSupported: Bool {
        VZGenericPlatformConfiguration.isNestedVirtualizationSupported
    }

    public init() {}
}

public enum AppleMachineKernelResolverError: Error, Equatable, Sendable {
    case invalidIdentifier
    case missingFile
    case unreadableFile
}

public struct AppleMachineKernelResolver: MachineKernelResolving {
    public init() {}

    public func resolve(identifier: String) async throws -> URL {
        guard identifier.hasPrefix("/"), !identifier.contains("\0") else {
            throw AppleMachineKernelResolverError.invalidIdentifier
        }
        let url = URL(fileURLWithPath: identifier).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            throw AppleMachineKernelResolverError.missingFile
        }
        guard FileManager.default.isReadableFile(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize,
              size > 0
        else {
            throw AppleMachineKernelResolverError.unreadableFile
        }
        return url
    }
}

public struct MachineAdapter: MachineOperations, Sendable {
    private let client: any MachineBackend
    private let capabilities: any MachineCapabilityChecking
    private let kernels: any MachineKernelResolving
    private let coordinator: OperationCoordinator
    private let consentLedger: MachineConsentLedger
    private let processID: @Sendable () -> String

    public init(
        client: any MachineBackend = AppleMachineBackend(),
        capabilities: any MachineCapabilityChecking = AppleMachineCapabilities(),
        kernels: any MachineKernelResolving = AppleMachineKernelResolver(),
        coordinator: OperationCoordinator = OperationCoordinator(),
        processID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.client = client
        self.capabilities = capabilities
        self.kernels = kernels
        self.coordinator = coordinator
        consentLedger = MachineConsentLedger()
        self.processID = processID
    }

    public func create(_ request: MachineCreateRequest) async throws -> MachineSummary {
        try await coordinator.withLock(.machine(request.name)) {
            let plan = try await createPlan(request)
            return try await client.create(plan).summary
        }
    }

    public func run(_ request: MachineRunRequest) async throws -> any ProcessSession {
        try await coordinator.withLock(.machine(request.create.name)) {
            let plan = try await createPlan(request.create)
            var created = false
            do {
                _ = try await client.create(plan)
                created = true
                _ = try await client.boot(id: plan.name)
                let transport = try await client.createProcess(
                    MachineProcessPlan(
                        machineID: plan.name,
                        processID: processID(),
                        arguments: request.process.arguments,
                        environment: request.process.environment,
                        workingDirectory: request.process.workingDirectory,
                        user: request.process.user,
                        terminal: request.process.tty,
                        interactive: request.process.interactive
                    )
                )
                return try await MachineProcessAdapter.start(transport)
            } catch {
                if created {
                    try? await client.stop(id: plan.name, force: true)
                    try? await client.delete(id: plan.name, force: true)
                }
                throw error
            }
        }
    }

    public func list() async throws -> [MachineSummary] {
        try await client.list().map(\.summary)
    }

    public func inspect(id: String) async throws -> MachineDetail {
        let resolved = try await resolve(id)
        return try await client.inspect(id: resolved)
    }

    public func set(id: String, request: MachineSetRequest) async throws -> MachineSummary {
        let resolved = try await resolve(id)
        return try await coordinator.withLock(.machine(resolved)) {
            let plan = try await setPlan(request)
            return try await client.set(id: resolved, plan: plan).summary
        }
    }

    public func setDefault(id: String) async throws {
        let resolved = try await resolve(id)
        try await coordinator.withLock(.machine(resolved)) {
            try await client.setDefault(id: resolved)
        }
    }

    public func logs(
        id: String,
        options: LogOptions
    ) async throws -> AsyncThrowingStream<LogRecord, any Error> {
        let resolved = try await resolve(id)
        return try await client.logs(id: resolved, options: options)
    }

    public func stop(ids: [String], force: Bool) async throws -> [BatchItemResult] {
        try await mutate(ids: ids, force: force, failureCode: "machine.stop.failed") { id, force in
            try await client.stop(id: id, force: force)
        }
    }

    public func delete(ids: [String], force: Bool) async throws -> [BatchItemResult] {
        try await mutate(ids: ids, force: force, failureCode: "machine.delete.failed") { id, force in
            try await client.delete(id: id, force: force)
        }
    }

    private func createPlan(_ request: MachineCreateRequest) async throws -> MachineCreatePlan {
        guard let imageReference = request.imageReference?.trimmingCharacters(in: .whitespacesAndNewlines),
              !imageReference.isEmpty
        else {
            throw MachineAdapterError.imageRequired
        }
        try validate(resources: request.resources)
        guard request.resources.diskBytes == nil else {
            throw MachineAdapterError.customDiskUnsupported
        }
        guard request.networks.isEmpty else {
            throw MachineAdapterError.customNetworksUnsupported
        }
        try validateNestedVirtualization(request.nestedVirtualization)
        try await consumeConsentIfNeeded(
            homeMount: request.homeMount,
            consent: request.homeSharingConsent
        )
        let kernelURL: URL? = if let identifier = request.kernelIdentifier {
            try await kernels.resolve(identifier: identifier)
        } else {
            nil
        }
        return MachineCreatePlan(
            name: request.name,
            imageReference: imageReference,
            resources: request.resources,
            homeMount: request.homeMount,
            networks: request.networks,
            kernelURL: kernelURL,
            nestedVirtualization: request.nestedVirtualization
        )
    }

    private func setPlan(_ request: MachineSetRequest) async throws -> MachineSetPlan {
        if let resources = request.resources {
            try validate(resources: resources)
            guard resources.diskBytes == nil else {
                throw MachineAdapterError.customDiskUnsupported
            }
        }
        if let nestedVirtualization = request.nestedVirtualization {
            try validateNestedVirtualization(nestedVirtualization)
        }
        if let homeMount = request.homeMount {
            try await consumeConsentIfNeeded(
                homeMount: homeMount,
                consent: request.homeSharingConsent
            )
        }
        return MachineSetPlan(
            resources: request.resources,
            homeMount: request.homeMount,
            nestedVirtualization: request.nestedVirtualization
        )
    }

    private func validate(resources: RuntimeResources) throws {
        guard resources.cpuCount > 0,
              resources.memoryBytes >= 1024 * 1024 * 1024,
              resources.diskBytes.map({ $0 > 0 }) ?? true
        else {
            throw MachineAdapterError.invalidResources
        }
    }

    private func validateNestedVirtualization(_ requested: Bool) throws {
        guard !requested || capabilities.nestedVirtualizationSupported else {
            throw MachineAdapterError.nestedVirtualizationUnsupported
        }
    }

    private func consumeConsentIfNeeded(
        homeMount: String,
        consent: HomeSharingConsent?
    ) async throws {
        guard ["none", "ro", "rw"].contains(homeMount) else {
            throw MachineAdapterError.invalidHomeMount(homeMount)
        }
        guard homeMount != "none" else {
            return
        }
        guard let consent else {
            throw MachineAdapterError.homeSharingConsentRequired
        }
        guard await consentLedger.consume(consent.token) else {
            throw MachineAdapterError.homeSharingConsentAlreadyUsed
        }
    }

    private func resolve(_ requestedID: String) async throws -> String {
        let inventory = try await client.list().map(\.summary)
        if let exact = inventory.first(where: {
            $0.id == requestedID || $0.name == requestedID
        }) {
            return exact.id
        }
        let matches = inventory.filter { $0.id.hasPrefix(requestedID) }
        switch matches.count {
        case 0: throw MachineAdapterError.identifierNotFound(requestedID)
        case 1: return matches[0].id
        default: throw MachineAdapterError.ambiguousIdentifier(requestedID)
        }
    }

    private func mutate(
        ids: [String],
        force: Bool,
        failureCode: String,
        operation: @escaping @Sendable (String, Bool) async throws -> Void
    ) async throws -> [BatchItemResult] {
        let inventory = try await client.list().map(\.summary)
        var results: [BatchItemResult] = []
        results.reserveCapacity(ids.count)
        for requestedID in ids {
            try Task.checkCancellation()
            let resolved: String
            do {
                resolved = try Self.resolve(requestedID, inventory: inventory)
            } catch {
                results.append(Self.failure(id: requestedID, code: Self.identifierCode(error), error: error))
                continue
            }
            do {
                try await coordinator.withLock(.machine(resolved)) {
                    try await operation(resolved, force)
                }
                results.append(BatchItemResult(id: requestedID, succeeded: true))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                results.append(Self.failure(id: requestedID, code: failureCode, error: error))
            }
        }
        return results
    }

    private static func resolve(
        _ requestedID: String,
        inventory: [MachineSummary]
    ) throws -> String {
        if let exact = inventory.first(where: {
            $0.id == requestedID || $0.name == requestedID
        }) {
            return exact.id
        }
        let matches = inventory.filter { $0.id.hasPrefix(requestedID) }
        switch matches.count {
        case 0: throw MachineAdapterError.identifierNotFound(requestedID)
        case 1: return matches[0].id
        default: throw MachineAdapterError.ambiguousIdentifier(requestedID)
        }
    }

    private static func identifierCode(_ error: any Error) -> String {
        switch error {
        case MachineAdapterError.identifierNotFound: "machine.identifier.not-found"
        case MachineAdapterError.ambiguousIdentifier: "machine.identifier.ambiguous"
        default: "machine.identifier.invalid"
        }
    }

    private static func failure(id: String, code: String, error: any Error) -> BatchItemResult {
        BatchItemResult(
            id: id,
            succeeded: false,
            error: UserFacingError(
                code: code,
                messageKey: "error.\(code)",
                redactedDetails: String(describing: type(of: error))
            )
        )
    }
}

private actor MachineConsentLedger {
    private var consumedTokens: Set<UUID> = []

    func consume(_ token: UUID) -> Bool {
        consumedTokens.insert(token).inserted
    }
}
