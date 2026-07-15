import ContainerAPIClient
import ContainerizationExtras
import ContainerPersistence
import Darwin
import Foundation
import MCModel
import SystemPackage
import TOML

public protocol ConfigurationStoring: Sendable {
    var destination: URL { get }
    func read() async throws -> String?
    func write(_ value: String, preserveLastKnownGood: Bool) async throws -> Bool
    func restore(_ value: String?) async throws
    func export(_ value: String, to destination: URL) async throws
}

public protocol ConfigurationRuntimeManaging: Sendable {
    func inventory() async throws -> WorkloadInventory
    func stop() async throws
    func start() async throws
}

public protocol ConfigurationCoding: Sendable {
    func decode(_ value: String?) throws -> SystemConfiguration
    func encode(_ configuration: SystemConfiguration) throws -> String
    func validate(_ configuration: SystemConfiguration) -> [ValidationIssue]
}

public enum ConfigurationAdapterError: Error, Equatable, Sendable {
    case confirmationTokenAlreadyUsed
    case activeWorkloads(containers: Int, machines: Int)
    case invalidConfiguration([ValidationIssue])
    case recoveryFailed
    case unsafeDestination
    case configurationTooLarge
}

public struct ConfigurationAdapter: ConfigurationOperations, Sendable {
    private let storage: any ConfigurationStoring
    private let runtime: any ConfigurationRuntimeManaging
    private let codec: any ConfigurationCoding
    private let coordinator: OperationCoordinator
    private let confirmations: ConfigurationConfirmationLedger

    public init(
        storage: any ConfigurationStoring = AtomicConfigurationStorage.production(),
        runtime: any ConfigurationRuntimeManaging = AppleConfigurationRuntime(),
        codec: any ConfigurationCoding = AppleContainerConfigurationCodec(),
        coordinator: OperationCoordinator = OperationCoordinator()
    ) {
        self.storage = storage
        self.runtime = runtime
        self.codec = codec
        self.coordinator = coordinator
        confirmations = ConfigurationConfirmationLedger()
    }

    public func load() async throws -> SystemConfiguration {
        let value = try await storage.read()
        return try codec.decode(value)
    }

    public func validate(_ configuration: SystemConfiguration) async -> [ValidationIssue] {
        codec.validate(configuration)
    }

    public func preview(_ configuration: SystemConfiguration) async throws -> String {
        let issues = codec.validate(configuration)
        guard issues.isEmpty else {
            throw ConfigurationAdapterError.invalidConfiguration(issues)
        }
        return try codec.encode(configuration)
    }

    public func save(_ configuration: SystemConfiguration) async throws -> ConfigurationSaveReport {
        try await coordinator.withLock(.lifecycle) {
            try await saveUnlocked(configuration)
        }
    }

    public func apply(_ request: ConfigurationApplyRequest) async throws -> ConfigurationApplyReport {
        guard await confirmations.consume(request.idleConfirmationToken) else {
            throw ConfigurationAdapterError.confirmationTokenAlreadyUsed
        }
        return try await coordinator.withLock(.lifecycle) {
            let issues = codec.validate(request.configuration)
            guard issues.isEmpty else {
                throw ConfigurationAdapterError.invalidConfiguration(issues)
            }
            let inventory = try await runtime.inventory()
            guard inventory.isEmpty else {
                throw ConfigurationAdapterError.activeWorkloads(
                    containers: inventory.activeContainerIDs.count,
                    machines: inventory.activeMachineIDs.count
                )
            }

            let previous = try await storage.read()
            let encoded = try codec.encode(request.configuration)
            _ = try await storage.write(encoded, preserveLastKnownGood: true)
            do {
                try await runtime.stop()
                try await runtime.start()
                return ConfigurationApplyReport(restarted: true)
            } catch is CancellationError {
                try await restoreAndRestart(previous)
                throw CancellationError()
            } catch {
                try await restoreAndRestart(previous)
                return ConfigurationApplyReport(restarted: true, restoredLastKnownGood: true)
            }
        }
    }

    public func export(_ configuration: SystemConfiguration, destination: URL) async throws {
        let encoded = try await preview(configuration)
        try await storage.export(encoded, to: destination)
    }

    private func saveUnlocked(_ configuration: SystemConfiguration) async throws -> ConfigurationSaveReport {
        let issues = codec.validate(configuration)
        guard issues.isEmpty else {
            throw ConfigurationAdapterError.invalidConfiguration(issues)
        }
        let encoded = try codec.encode(configuration)
        let preserved = try await storage.write(encoded, preserveLastKnownGood: true)
        return ConfigurationSaveReport(
            destination: storage.destination,
            lastKnownGoodPreserved: preserved
        )
    }

    private func restoreAndRestart(_ previous: String?) async throws {
        do {
            try await Task.detached {
                try await storage.restore(previous)
                try await runtime.start()
            }.value
        } catch {
            throw ConfigurationAdapterError.recoveryFailed
        }
    }
}

private actor ConfigurationConfirmationLedger {
    private var consumed = Set<UUID>()

    func consume(_ token: UUID) -> Bool {
        consumed.insert(token).inserted
    }
}

public struct AppleConfigurationRuntime: ConfigurationRuntimeManaging, Sendable {
    private let controller: SystemServiceController
    private let workloads: any WorkloadManaging

    public init(
        controller: SystemServiceController = .production(),
        workloads: any WorkloadManaging = AppleWorkloadManager()
    ) {
        self.controller = controller
        self.workloads = workloads
    }

    public func inventory() async throws -> WorkloadInventory {
        do {
            _ = try await ClientHealthCheck.ping(timeout: .seconds(2))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .empty
        }
        return try await workloads.inventory()
    }

    public func stop() async throws {
        try await controller.stop(stopActiveWorkloads: false, timeout: .seconds(30))
    }

    public func start() async throws {
        _ = try await controller.start(timeout: .seconds(30))
    }
}

public struct AtomicConfigurationStorage: ConfigurationStoring, Sendable {
    public let destination: URL
    private let maximumBytes: Int

    public init(destination: URL, maximumBytes: Int = 1024 * 1024) {
        self.destination = destination
        self.maximumBytes = maximumBytes
    }

    public static func production() -> Self {
        Self(destination: URL(fileURLWithPath: ConfigurationLoader.configurationFile(.home).string))
    }

    public func read() async throws -> String? {
        try Self.read(at: destination, maximumBytes: maximumBytes)
    }

    public func write(_ value: String, preserveLastKnownGood: Bool) async throws -> Bool {
        let data = Data(value.utf8)
        guard data.count <= maximumBytes else {
            throw ConfigurationAdapterError.configurationTooLarge
        }
        let previous = try Self.readData(at: destination, maximumBytes: maximumBytes)
        if preserveLastKnownGood, let previous {
            try Self.atomicWrite(previous, to: lastKnownGoodURL)
        }
        try Self.atomicWrite(data, to: destination)
        return previous != nil
    }

    public func restore(_ value: String?) async throws {
        if let value {
            let data = Data(value.utf8)
            guard data.count <= maximumBytes else {
                throw ConfigurationAdapterError.configurationTooLarge
            }
            try Self.atomicWrite(data, to: destination)
        } else if Darwin.unlink(destination.path) != 0, errno != ENOENT {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }

    public func export(_ value: String, to destination: URL) async throws {
        guard destination.isFileURL else {
            throw ConfigurationAdapterError.unsafeDestination
        }
        let data = Data(value.utf8)
        guard data.count <= maximumBytes else {
            throw ConfigurationAdapterError.configurationTooLarge
        }
        try Self.atomicWrite(data, to: destination)
    }

    private var lastKnownGoodURL: URL {
        destination.appendingPathExtension("last-known-good")
    }

    private static func read(at url: URL, maximumBytes: Int) throws -> String? {
        guard let data = try readData(at: url, maximumBytes: maximumBytes) else { return nil }
        guard let value = String(data: data, encoding: .utf8) else {
            throw ConfigurationAdapterError.unsafeDestination
        }
        return value
    }

    private static func readData(at url: URL, maximumBytes: Int) throws -> Data? {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        if descriptor < 0, errno == ENOENT {
            return nil
        }
        guard descriptor >= 0 else {
            throw ConfigurationAdapterError.unsafeDestination
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG
        else {
            try? handle.close()
            throw ConfigurationAdapterError.unsafeDestination
        }
        guard status.st_size >= 0, status.st_size <= Int64(maximumBytes) else {
            try? handle.close()
            throw ConfigurationAdapterError.configurationTooLarge
        }
        let data = try handle.readToEnd() ?? Data()
        try handle.close()
        guard data.count <= maximumBytes else {
            throw ConfigurationAdapterError.configurationTooLarge
        }
        return data
    }

    private static func rejectSymbolicLink(_ url: URL) throws {
        var status = stat()
        guard Darwin.lstat(url.path, &status) == 0 else {
            if errno == ENOENT {
                return
            }
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        guard status.st_mode & S_IFMT != S_IFLNK else {
            throw ConfigurationAdapterError.unsafeDestination
        }
    }

    private static func atomicWrite(_ data: Data, to destination: URL) throws {
        guard destination.isFileURL, !destination.path.contains("\0") else {
            throw ConfigurationAdapterError.unsafeDestination
        }
        try rejectSymbolicLink(destination)
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let temporary = directory.appending(path: ".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        let descriptor = Darwin.open(
            temporary.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var shouldRemove = true
        defer {
            Darwin.close(descriptor)
            if shouldRemove {
                try? FileManager.default.removeItem(at: temporary)
            }
        }
        try data.withUnsafeBytes { rawBuffer in
            guard var cursor = rawBuffer.baseAddress else { return }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let count = Darwin.write(descriptor, cursor, remaining)
                guard count >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
                remaining -= count
                cursor = cursor.advanced(by: count)
            }
        }
        guard Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR) == 0,
              Darwin.fsync(descriptor) == 0
        else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        guard Darwin.rename(temporary.path, destination.path) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        shouldRemove = false
        let directoryDescriptor = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY)
        if directoryDescriptor >= 0 {
            _ = Darwin.fsync(directoryDescriptor)
            Darwin.close(directoryDescriptor)
        }
    }
}

public struct AppleContainerConfigurationCodec: ConfigurationCoding, Sendable {
    private enum ValueKind {
        case positiveInteger
        case boolean
        case memory
        case string
        case optionalString
        case httpsURL
        case domain
        case ipv4Subnet
        case ipv6Subnet
        case homeMount
        case archivePath
        case localPath
    }

    private static let schema: [String: ValueKind] = [
        "build.rosetta": .boolean,
        "build.cpus": .positiveInteger,
        "build.memory": .memory,
        "build.image": .string,
        "container.cpus": .positiveInteger,
        "container.memory": .memory,
        "dns.domain": .domain,
        "kernel.binaryPath": .archivePath,
        "kernel.url": .httpsURL,
        "machine.cpus": .positiveInteger,
        "machine.memory": .memory,
        "machine.homeMount": .homeMount,
        "machine.virtualization": .boolean,
        "machine.kernelPath": .localPath,
        "network.subnet": .ipv4Subnet,
        "network.subnetv6": .ipv6Subnet,
        "registry.domain": .domain,
        "vminit.image": .string
    ]

    public init() {}

    public func decode(_ value: String?) throws -> SystemConfiguration {
        let decoded = try decodeContainer(value)
        var values: [String: String] = [
            "build.rosetta": String(decoded.build.rosetta),
            "build.cpus": String(decoded.build.cpus),
            "build.memory": decoded.build.memory.description,
            "build.image": decoded.build.image,
            "container.cpus": String(decoded.container.cpus),
            "container.memory": decoded.container.memory.description,
            "kernel.binaryPath": decoded.kernel.binaryPath,
            "kernel.url": decoded.kernel.url.absoluteString,
            "machine.cpus": String(decoded.machine.cpus),
            "machine.memory": decoded.machine.memory.description,
            "machine.homeMount": decoded.machine.homeMount.rawValue,
            "machine.virtualization": String(decoded.machine.virtualization),
            "registry.domain": decoded.registry.domain,
            "vminit.image": decoded.vminit.image
        ]
        if let domain = decoded.dns.domain {
            values["dns.domain"] = domain
        }
        if let path = decoded.machine.kernelPath {
            values["machine.kernelPath"] = path.string
        }
        if let subnet = decoded.network.subnet {
            values["network.subnet"] = subnet.description
        }
        if let subnet = decoded.network.subnetv6 {
            values["network.subnetv6"] = subnet.description
        }
        return SystemConfiguration(values: values)
    }

    private func decodeContainer(_ value: String?) throws -> ContainerSystemConfig {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return ContainerSystemConfig()
        }
        do {
            let decoder = TOMLDecoder()
            let audit = try decoder.decode(TOMLKeyAudit.self, from: value)
            let unknownLeaves = audit.leafPaths.filter { Self.schema[$0] == nil }
            let allowedTables = Set(Self.schema.keys.compactMap { $0.split(separator: ".").first.map(String.init) })
            let unknownTables = audit.tablePaths.filter { !allowedTables.contains($0) }
            let issues = (unknownLeaves + unknownTables).map { issue($0, "unknown") }.sorted()
            guard issues.isEmpty else {
                throw ConfigurationAdapterError.invalidConfiguration(issues)
            }
            return try decoder.decode(ContainerSystemConfig.self, from: value)
        } catch let error as ConfigurationAdapterError {
            throw error
        } catch {
            throw ConfigurationAdapterError.invalidConfiguration([issue("configuration", "typed")])
        }
    }

    public func encode(_ configuration: SystemConfiguration) throws -> String {
        let issues = validate(configuration)
        guard issues.isEmpty else {
            throw ConfigurationAdapterError.invalidConfiguration(issues)
        }
        var sections: [String: [(String, String)]] = [:]
        for (path, value) in configuration.values {
            let components = path.split(separator: ".", maxSplits: 1).map(String.init)
            guard components.count == 2, let kind = Self.schema[path] else { continue }
            sections[components[0], default: []].append((components[1], Self.render(value, kind: kind)))
        }
        return sections.keys.sorted().map { section in
            let body = sections[section, default: []].sorted { $0.0 < $1.0 }
                .map { "\($0.0) = \($0.1)" }
                .joined(separator: "\n")
            return "[\(section)]\n\(body)"
        }.joined(separator: "\n\n") + "\n"
    }

    public func validate(_ configuration: SystemConfiguration) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        for (path, value) in configuration.values {
            guard let kind = Self.schema[path] else {
                issues.append(issue(path, "unknown"))
                continue
            }
            guard Self.isValid(value, kind: kind) else {
                issues.append(issue(path, "invalid"))
                continue
            }
        }
        if issues.isEmpty {
            do {
                let preview = try encodeWithoutValidation(configuration)
                _ = try TOMLDecoder().decode(ContainerSystemConfig.self, from: preview)
            } catch {
                issues.append(issue("configuration", "typed"))
            }
        }
        return issues.sorted()
    }

    private func encodeWithoutValidation(_ configuration: SystemConfiguration) throws -> String {
        var sections: [String: [(String, String)]] = [:]
        for (path, value) in configuration.values {
            guard let kind = Self.schema[path] else { continue }
            let components = path.split(separator: ".", maxSplits: 1).map(String.init)
            sections[components[0], default: []].append((components[1], Self.render(value, kind: kind)))
        }
        return sections.keys.sorted().map { section in
            let values = sections[section, default: []].sorted { $0.0 < $1.0 }
                .map { "\($0.0) = \($0.1)" }.joined(separator: "\n")
            return "[\(section)]\n\(values)"
        }.joined(separator: "\n\n") + "\n"
    }

    private func issue(_ parameter: String, _ reason: String) -> ValidationIssue {
        ValidationIssue(
            parameterID: parameter,
            severity: .error,
            messageKey: "validation.configuration.\(reason)",
            recoveryKey: "validation.configuration.\(reason).recovery"
        )
    }

    private static func isValid(_ value: String, kind: ValueKind) -> Bool {
        switch kind {
        case .positiveInteger, .boolean, .memory, .string, .optionalString:
            isValidScalar(value, kind: kind)
        case .httpsURL, .domain, .ipv4Subnet, .ipv6Subnet:
            isValidNetworkValue(value, kind: kind)
        case .homeMount, .archivePath, .localPath:
            isValidRuntimeValue(value, kind: kind)
        }
    }

    private static func isValidScalar(_ value: String, kind: ValueKind) -> Bool {
        switch kind {
        case .positiveInteger: Int(value).map { $0 > 0 } ?? false
        case .boolean: value == "true" || value == "false"
        case .memory: (try? MemorySize(value)) != nil
        case .string: !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .optionalString: !value.contains("\0")
        default: false
        }
    }

    private static func isValidNetworkValue(_ value: String, kind: ValueKind) -> Bool {
        switch kind {
        case .httpsURL:
            guard let url = URL(string: value) else { return false }
            return url.scheme?.lowercased() == "https" && url.host != nil
        case .domain: return (try? DNSAdapter.normalizedName(value)) != nil
        case .ipv4Subnet: return (try? CIDRv4(value)) != nil
        case .ipv6Subnet: return (try? CIDRv6(value)) != nil
        default: return false
        }
    }

    private static func isValidRuntimeValue(_ value: String, kind: ValueKind) -> Bool {
        switch kind {
        case .homeMount: ["none", "ro", "rw"].contains(value)
        case .archivePath: (try? KernelAdapter.validateArchiveMemberPath(value)) != nil
        case .localPath: value.isEmpty || (value.hasPrefix("/") && !value.contains("\0"))
        default: false
        }
    }

    private static func render(_ value: String, kind: ValueKind) -> String {
        switch kind {
        case .positiveInteger, .boolean:
            value
        default:
            "\"\(escape(value))\""
        }
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

private struct TOMLKeyAudit: Decodable {
    let isTable: Bool
    let leafPaths: [String]
    let tablePaths: [String]

    init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: ArbitraryCodingKey.self) else {
            _ = try decoder.singleValueContainer()
            isTable = false
            leafPaths = [""]
            tablePaths = []
            return
        }

        isTable = true
        var leaves: [String] = []
        var tables: [String] = []
        for key in container.allKeys {
            let child = try container.decode(Self.self, forKey: key)
            if child.isTable {
                tables.append(key.stringValue)
                tables.append(contentsOf: child.tablePaths.map { "\(key.stringValue).\($0)" })
            }
            leaves.append(contentsOf: child.leafPaths.map { path in
                path.isEmpty ? key.stringValue : "\(key.stringValue).\(path)"
            })
        }
        leafPaths = leaves
        tablePaths = tables
    }
}

private struct ArbitraryCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
