import ContainerAPIClient
import ContainerPersistence
import ContainerPlugin
import ContainerResource
import Foundation
import MachineAPIClient
import MCModel

public struct ServiceDefinition: Equatable, Sendable {
    public let label: String
    public let program: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let plistURL: URL
    public let limitLoadToSessionType: [ServiceSessionType]
    public let runAtLoad: Bool
    public let machServices: [String]

    public init(
        label: String,
        program: URL,
        arguments: [String],
        environment: [String: String],
        plistURL: URL,
        limitLoadToSessionType: [ServiceSessionType],
        runAtLoad: Bool,
        machServices: [String]
    ) {
        self.label = label
        self.program = program
        self.arguments = arguments
        self.environment = environment
        self.plistURL = plistURL
        self.limitLoadToSessionType = limitLoadToSessionType
        self.runAtLoad = runAtLoad
        self.machServices = machServices
    }
}

public enum ServiceSessionType: String, Equatable, Sendable {
    case aqua
    case background
    case system
}

public protocol ServiceManaging: Sendable {
    func register(_ definition: ServiceDefinition) async throws
    func deregister(label: String) async throws
    func isRegistered(label: String) async throws -> Bool
    func labels(prefix: String) async throws -> [String]
}

public protocol HealthChecking: Sendable {
    func ping(timeout: Duration) async throws -> RuntimeHealth
}

public protocol MachineAPIProbing: Sendable {
    func verifyList() async throws
}

public protocol SystemConfigurationLoading: Sendable {
    func prepareAndLoad() async throws
}

public protocol WorkloadManaging: Sendable {
    func inventory() async throws -> WorkloadInventory
    func stopAll(_ inventory: WorkloadInventory, timeout: Duration) async throws
}

public struct WorkloadInventory: Equatable, Sendable {
    public static let empty = Self(activeContainerIDs: [], activeMachineIDs: [])

    public let activeContainerIDs: [String]
    public let activeMachineIDs: [String]

    public var isEmpty: Bool {
        activeContainerIDs.isEmpty && activeMachineIDs.isEmpty
    }

    public init(activeContainerIDs: [String], activeMachineIDs: [String]) {
        self.activeContainerIDs = activeContainerIDs
        self.activeMachineIDs = activeMachineIDs
    }
}

public struct SystemServiceConfiguration: Equatable, Sendable {
    public static var productionDefault: Self {
        Self(
            applicationRoot: URL(fileURLWithPath: ApplicationRoot.path.string),
            installRoot: URL(
                fileURLWithPath: SystemServiceController.installRootPath,
                isDirectory: true
            ),
            logRoot: LogRoot.path.map { URL(fileURLWithPath: $0.string) },
            inheritedEnvironment: ProcessInfo.processInfo.environment
        )
    }

    public let applicationRoot: URL
    public let installRoot: URL
    public let logRoot: URL?
    public let inheritedEnvironment: [String: String]
    public let debug: Bool

    public init(
        applicationRoot: URL,
        installRoot: URL,
        logRoot: URL?,
        inheritedEnvironment: [String: String],
        debug: Bool = false
    ) {
        self.applicationRoot = applicationRoot
        self.installRoot = installRoot
        self.logRoot = logRoot
        self.inheritedEnvironment = inheritedEnvironment
        self.debug = debug
    }
}

public struct SystemServiceRetryPolicy: Equatable, Sendable {
    public static let `default` = Self(
        initialDelay: .milliseconds(50),
        maximumDelay: .seconds(1),
        pingTimeout: .seconds(2)
    )

    public let initialDelay: Duration
    public let maximumDelay: Duration
    public let pingTimeout: Duration

    public init(initialDelay: Duration, maximumDelay: Duration, pingTimeout: Duration) {
        self.initialDelay = initialDelay
        self.maximumDelay = maximumDelay
        self.pingTimeout = pingTimeout
    }
}

public enum SystemServiceError: Error, Equatable, Sendable {
    case invalidAPIServerPath
    case invalidServiceLabel
    case invalidTimeout
    case healthTimeout
    case machineAPIUnavailable
    case activeWorkloads(containers: Int, machines: Int)
    case workloadShutdownTimeout
    case partialStartCleanupFailed
    case serviceRegistrationFailed
    case serviceDeregistrationFailed
}

public struct SystemServiceController: Sendable {
    public static let installRootPath = "/usr/local"
    public static let apiServerPath = "/usr/local/bin/container-apiserver"
    public static let apiServerLabel = "com.apple.container.apiserver"
    public static let servicePrefix = "com.apple.container."

    private let apiServerURL: URL
    private let services: any ServiceManaging
    private let health: any HealthChecking
    private let machineAPI: any MachineAPIProbing
    private let workloads: any WorkloadManaging
    private let configurationLoader: any SystemConfigurationLoading
    private let configuration: SystemServiceConfiguration
    private let retryPolicy: SystemServiceRetryPolicy

    public init(
        apiServerURL: URL,
        services: any ServiceManaging,
        health: any HealthChecking,
        machineAPI: any MachineAPIProbing,
        workloads: any WorkloadManaging,
        configurationLoader: any SystemConfigurationLoading,
        configuration: SystemServiceConfiguration,
        retryPolicy: SystemServiceRetryPolicy = .default
    ) {
        self.apiServerURL = apiServerURL
        self.services = services
        self.health = health
        self.machineAPI = machineAPI
        self.workloads = workloads
        self.configurationLoader = configurationLoader
        self.configuration = configuration
        self.retryPolicy = retryPolicy
    }

    public static func production() -> Self {
        let configuration = SystemServiceConfiguration.productionDefault
        return Self(
            apiServerURL: URL(fileURLWithPath: apiServerPath),
            services: AppleServiceManager(
                managedPlistURLs: [apiServerLabel: apiServerPlistURL(for: configuration)]
            ),
            health: AppleHealthChecker(),
            machineAPI: AppleMachineAPIProbe(),
            workloads: AppleWorkloadManager(),
            configurationLoader: AppleSystemConfigurationLoader(),
            configuration: configuration
        )
    }

    @discardableResult
    public func start(timeout: Duration) async throws -> RuntimeHealth {
        try validateStart(timeout: timeout)
        try await configurationLoader.prepareAndLoad()

        let alreadyRegistered = try await services.isRegistered(label: Self.apiServerLabel)
        var registeredHere = false
        do {
            if !alreadyRegistered {
                try await services.register(serviceDefinition())
                registeredHere = true
            }

            let result = try await waitForHealth(timeout: timeout)
            do {
                try await machineAPI.verifyList()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw SystemServiceError.machineAPIUnavailable
            }
            return result
        } catch {
            if registeredHere {
                do {
                    try await services.deregister(label: Self.apiServerLabel)
                } catch {
                    throw SystemServiceError.partialStartCleanupFailed
                }
            }
            throw error
        }
    }

    public func stop(stopActiveWorkloads: Bool, timeout: Duration) async throws {
        guard timeout > .zero else {
            throw SystemServiceError.invalidTimeout
        }

        let apiServerRegistered = try await services.isRegistered(label: Self.apiServerLabel)
        if apiServerRegistered {
            let inventory = try await workloads.inventory()
            if !inventory.isEmpty, !stopActiveWorkloads {
                throw SystemServiceError.activeWorkloads(
                    containers: inventory.activeContainerIDs.count,
                    machines: inventory.activeMachineIDs.count
                )
            }
            if !inventory.isEmpty {
                try await workloads.stopAll(inventory, timeout: timeout)
                try await waitForWorkloadsToStop(timeout: timeout)
            }
        }

        let registeredLabels = try await services.labels(prefix: Self.servicePrefix)
        for label in registeredLabels.sorted() where label != Self.apiServerLabel {
            try Task.checkCancellation()
            try await services.deregister(label: label)
        }
        if apiServerRegistered || registeredLabels.contains(Self.apiServerLabel) {
            try Task.checkCancellation()
            try await services.deregister(label: Self.apiServerLabel)
        }
    }

    private func validateStart(timeout: Duration) throws {
        guard apiServerURL.standardizedFileURL.path == Self.apiServerPath else {
            throw SystemServiceError.invalidAPIServerPath
        }
        guard timeout > .zero,
              retryPolicy.initialDelay > .zero,
              retryPolicy.maximumDelay >= retryPolicy.initialDelay,
              retryPolicy.pingTimeout > .zero
        else {
            throw SystemServiceError.invalidTimeout
        }
    }

    private func serviceDefinition() -> ServiceDefinition {
        var environment = PluginLoader.filterEnvironment(env: configuration.inheritedEnvironment)
        environment[ApplicationRoot.environmentName] = configuration.applicationRoot.path
        environment[InstallRoot.environmentName] = configuration.installRoot.path
        if let logRoot = configuration.logRoot {
            environment[LogRoot.environmentName] = logRoot.path
        }

        var arguments = [Self.apiServerPath, "start"]
        if configuration.debug {
            arguments.append("--debug")
        }
        return ServiceDefinition(
            label: Self.apiServerLabel,
            program: apiServerURL,
            arguments: arguments,
            environment: environment,
            plistURL: Self.apiServerPlistURL(for: configuration),
            limitLoadToSessionType: [.aqua, .background, .system],
            runAtLoad: true,
            machServices: [Self.apiServerLabel]
        )
    }

    private static func apiServerPlistURL(for configuration: SystemServiceConfiguration) -> URL {
        configuration.applicationRoot
            .appendingPathComponent("apiserver", isDirectory: true)
            .appendingPathComponent("apiserver.plist", isDirectory: false)
    }

    private func waitForHealth(timeout: Duration) async throws -> RuntimeHealth {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var delay = retryPolicy.initialDelay

        while true {
            try Task.checkCancellation()
            let attemptStart = clock.now
            guard attemptStart < deadline else {
                throw SystemServiceError.healthTimeout
            }
            let remainingBeforePing = attemptStart.duration(to: deadline)
            do {
                let result = try await health.ping(timeout: min(retryPolicy.pingTimeout, remainingBeforePing))
                if result.healthy {
                    return result
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Service activation is asynchronous. Retry only within the caller's deadline.
            }

            let now = clock.now
            guard now < deadline else {
                throw SystemServiceError.healthTimeout
            }
            let remaining = now.duration(to: deadline)
            try await clock.sleep(for: min(delay, remaining))
            delay = min(delay * 2, retryPolicy.maximumDelay)
        }
    }

    private func waitForWorkloadsToStop(timeout: Duration) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var delay = retryPolicy.initialDelay
        while true {
            try Task.checkCancellation()
            if try await workloads.inventory().isEmpty {
                return
            }
            let now = clock.now
            guard now < deadline else {
                throw SystemServiceError.workloadShutdownTimeout
            }
            try await clock.sleep(for: min(delay, now.duration(to: deadline)))
            delay = min(delay * 2, retryPolicy.maximumDelay)
        }
    }
}

protocol LaunchServiceRegistering: Sendable {
    func register(plistPath: String) throws
    func deregister(fullServiceLabel: String) throws
    func isRegistered(label: String) throws -> Bool
    func enumerate() throws -> [String]
    func domainString() throws -> String
}

struct LaunchServiceVisibilityRetryPolicy: Sendable {
    static let production = Self(maximumAttempts: 150, delay: .milliseconds(100))

    let maximumAttempts: Int
    let delay: Duration
}

private struct NativeLaunchServiceBackend: LaunchServiceRegistering {
    func register(plistPath: String) throws {
        try ServiceManager.register(plistPath: plistPath)
    }

    func deregister(fullServiceLabel: String) throws {
        try ServiceManager.deregister(fullServiceLabel: fullServiceLabel)
    }

    func isRegistered(label: String) throws -> Bool {
        try ServiceManager.isRegistered(fullServiceLabel: label)
    }

    func enumerate() throws -> [String] {
        try ServiceManager.enumerate()
    }

    func domainString() throws -> String {
        try ServiceManager.getDomainString()
    }
}

public actor AppleServiceManager: ServiceManaging {
    private let managedPlistURLs: [String: URL]
    private let backend: any LaunchServiceRegistering
    private let visibilityRetryPolicy: LaunchServiceVisibilityRetryPolicy

    public init(managedPlistURLs: [String: URL]) {
        self.managedPlistURLs = managedPlistURLs
        backend = NativeLaunchServiceBackend()
        visibilityRetryPolicy = .production
    }

    init(
        managedPlistURLs: [String: URL],
        backend: any LaunchServiceRegistering,
        visibilityRetryPolicy: LaunchServiceVisibilityRetryPolicy = .production
    ) {
        self.managedPlistURLs = managedPlistURLs
        self.backend = backend
        self.visibilityRetryPolicy = visibilityRetryPolicy
    }

    public func register(_ definition: ServiceDefinition) async throws {
        try validate(definition)
        let fileManager = FileManager.default
        let directory = definition.plistURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let canonicalProgram = definition.program.resolvingSymlinksInPath()
        var arguments = definition.arguments
        arguments[0] = canonicalProgram.path
        let plist = LaunchPlist(
            label: definition.label,
            arguments: arguments,
            environment: definition.environment,
            limitLoadToSessionType: definition.limitLoadToSessionType.map(\.launchPlistDomain),
            runAtLoad: definition.runAtLoad,
            program: canonicalProgram.path,
            machServices: definition.machServices
        )

        var registrationReturned = false
        do {
            try plist.encode().write(to: definition.plistURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: definition.plistURL.path
            )
            try backend.register(plistPath: definition.plistURL.path)
            registrationReturned = true
            guard try await waitForVisibility(label: definition.label, registered: true) else {
                throw SystemServiceError.serviceRegistrationFailed
            }
        } catch {
            if registrationReturned || (try? isRegisteredSynchronously(label: definition.label)) == true {
                do {
                    try backend.deregister(fullServiceLabel: fullServiceLabel(definition.label))
                } catch {
                    try? fileManager.removeItem(at: definition.plistURL)
                    throw SystemServiceError.partialStartCleanupFailed
                }
            }
            try? fileManager.removeItem(at: definition.plistURL)
            throw error
        }
    }

    public func deregister(label: String) async throws {
        try validate(label: label)
        let fullLabel = try fullServiceLabel(label)
        try backend.deregister(fullServiceLabel: fullLabel)
        guard try await waitForVisibility(label: label, registered: false) else {
            throw SystemServiceError.serviceDeregistrationFailed
        }
        if let plistURL = managedPlistURLs[label] {
            try? FileManager.default.removeItem(at: plistURL)
        }
    }

    public func isRegistered(label: String) async throws -> Bool {
        try validate(label: label)
        return try isRegisteredSynchronously(label: label)
    }

    public func labels(prefix: String) async throws -> [String] {
        guard prefix == SystemServiceController.servicePrefix else {
            throw SystemServiceError.invalidServiceLabel
        }
        return try backend.enumerate()
            .filter { $0.hasPrefix(prefix) }
            .sorted()
    }

    private func validate(_ definition: ServiceDefinition) throws {
        try validate(label: definition.label)
        guard definition.label == SystemServiceController.apiServerLabel,
              definition.program.standardizedFileURL.path == SystemServiceController.apiServerPath,
              definition.arguments == [SystemServiceController.apiServerPath, "start"] ||
              definition.arguments == [SystemServiceController.apiServerPath, "start", "--debug"],
              definition.machServices == [SystemServiceController.apiServerLabel],
              definition.limitLoadToSessionType == [.aqua, .background, .system],
              definition.runAtLoad,
              managedPlistURLs[definition.label]?.standardizedFileURL == definition.plistURL.standardizedFileURL,
              PluginLoader.filterEnvironment(env: definition.environment) == definition.environment
        else {
            throw SystemServiceError.invalidAPIServerPath
        }
    }

    private func validate(label: String) throws {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        guard label.hasPrefix(SystemServiceController.servicePrefix),
              !label.contains(".."),
              label.unicodeScalars.allSatisfy(allowed.contains)
        else {
            throw SystemServiceError.invalidServiceLabel
        }
    }

    private func fullServiceLabel(_ label: String) throws -> String {
        try "\(backend.domainString())/\(label)"
    }

    private func isRegisteredSynchronously(label: String) throws -> Bool {
        try backend.isRegistered(label: label)
    }

    private func waitForVisibility(label: String, registered: Bool) async throws -> Bool {
        precondition(visibilityRetryPolicy.maximumAttempts > 0)
        let clock = ContinuousClock()
        for attempt in 0 ..< visibilityRetryPolicy.maximumAttempts {
            if try isRegisteredSynchronously(label: label) == registered {
                return true
            }
            if attempt + 1 < visibilityRetryPolicy.maximumAttempts {
                try await clock.sleep(for: visibilityRetryPolicy.delay)
            }
        }
        return false
    }
}

public struct AppleHealthChecker: HealthChecking {
    public init() {}

    public func ping(timeout: Duration) async throws -> RuntimeHealth {
        let result = try await ClientHealthCheck.ping(timeout: timeout)
        return RuntimeHealth(healthy: true, version: result.apiServerVersion)
    }
}

public struct AppleMachineAPIProbe: MachineAPIProbing {
    public init() {}

    public func verifyList() async throws {
        _ = try await MachineClient().list()
    }
}

public struct AppleSystemConfigurationLoader: SystemConfigurationLoading {
    public init() {}

    public func prepareAndLoad() async throws {
        try ConfigurationLoader.copyConfigurationToReadOnly(to: ApplicationRoot.path)
        let _: ContainerSystemConfig = try await ConfigurationLoader.load(
            configurationFiles: [
                ConfigurationLoader.configurationFile(in: ApplicationRoot.path, of: .appRoot),
                ConfigurationLoader.configurationFile(in: InstallRoot.path, of: .installRoot)
            ]
        )
    }
}

public struct AppleWorkloadManager: WorkloadManaging {
    private let containers: ContainerClient
    private let machines: MachineClient

    public init(containers: ContainerClient = ContainerClient(), machines: MachineClient = MachineClient()) {
        self.containers = containers
        self.machines = machines
    }

    public func inventory() async throws -> WorkloadInventory {
        async let containerSnapshots = containers.list(filters: ContainerListFilters(status: .running))
        async let machineSnapshots = machines.list()
        return try await WorkloadInventory(
            activeContainerIDs: containerSnapshots.map(\.id).sorted(),
            activeMachineIDs: machineSnapshots.filter { $0.status == .running }.map(\.id).sorted()
        )
    }

    public func stopAll(_ inventory: WorkloadInventory, timeout: Duration) async throws {
        for id in inventory.activeMachineIDs.sorted() {
            try Task.checkCancellation()
            try await machines.stop(id: id)
        }

        let runningContainers = try await containers.list(filters: ContainerListFilters(status: .running))
        let options = ContainerStopOptions(timeoutInSeconds: timeoutSeconds(timeout), signal: nil)
        for id in runningContainers.map(\.id).sorted() {
            try Task.checkCancellation()
            try await containers.stop(id: id, opts: options)
        }
    }

    private func timeoutSeconds(_ timeout: Duration) -> Int32 {
        let components = timeout.components
        let rounded = components.seconds + (components.attoseconds > 0 ? 1 : 0)
        return Int32(clamping: max(1, rounded))
    }
}

private extension ServiceSessionType {
    var launchPlistDomain: LaunchPlist.Domain {
        switch self {
        case .aqua: .Aqua
        case .background: .Background
        case .system: .System
        }
    }
}
