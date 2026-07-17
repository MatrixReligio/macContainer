import CryptoKit
import Darwin
import Foundation

public struct HostHardwareIdentity: Codable, Equatable, Sendable {
    public let model: String
    public let architecture: String
    public let hardwareUUIDSHA256: String

    public init(model: String, architecture: String, hardwareUUIDSHA256: String) {
        self.model = model
        self.architecture = architecture
        self.hardwareUUIDSHA256 = hardwareUUIDSHA256
    }
}

public struct ReceiptSnapshot: Codable, Equatable, Sendable {
    public let identifier: String
    public let version: String
    public let installLocation: String

    public init(identifier: String, version: String, installLocation: String) {
        self.identifier = identifier
        self.version = version
        self.installLocation = installLocation
    }
}

public enum FileSnapshotKind: String, Codable, Equatable, Sendable {
    case file
    case directory
    case symbolicLink
    case other
}

public struct FileSnapshot: Codable, Equatable, Sendable {
    public let path: String
    public let kind: FileSnapshotKind
    public let mode: UInt16
    public let ownerID: UInt32
    public let groupID: UInt32
    public let size: UInt64
    public let sha256: String?
    public let linkTarget: String?

    public init(
        path: String,
        kind: FileSnapshotKind,
        mode: UInt16,
        ownerID: UInt32,
        groupID: UInt32,
        size: UInt64,
        sha256: String? = nil,
        linkTarget: String? = nil
    ) {
        self.path = path
        self.kind = kind
        self.mode = mode
        self.ownerID = ownerID
        self.groupID = groupID
        self.size = size
        self.sha256 = sha256
        self.linkTarget = linkTarget
    }
}

public struct LaunchServiceSnapshot: Codable, Equatable, Sendable {
    public let label: String
    public let state: String
    public let executablePath: String?
    public let executableSHA256: String?
    public let teamID: String?
    public let processID: Int32?

    public init(
        label: String,
        state: String,
        executablePath: String? = nil,
        executableSHA256: String? = nil,
        teamID: String? = nil,
        processID: Int32? = nil
    ) {
        self.label = label
        self.state = state
        self.executablePath = executablePath
        self.executableSHA256 = executableSHA256
        self.teamID = teamID
        self.processID = processID
    }
}

public struct ProcessSnapshot: Codable, Equatable, Sendable {
    public let executablePath: String
    public let executableSHA256: String?
    public let teamID: String?
    public let processID: Int32

    public init(executablePath: String, executableSHA256: String?, teamID: String?, processID: Int32) {
        self.executablePath = executablePath
        self.executableSHA256 = executableSHA256
        self.teamID = teamID
        self.processID = processID
    }
}

public struct PathSnapshot: Codable, Equatable, Sendable {
    public let root: String
    public let entries: [FileSnapshot]

    public init(root: String, entries: [FileSnapshot]) {
        self.root = root
        self.entries = entries.sorted { $0.path < $1.path }
    }
}

public struct DefaultsSnapshot: Codable, Equatable, Sendable {
    public let domain: String
    public let byteCount: Int
    public let sha256: String

    public init(domain: String, byteCount: Int, sha256: String) {
        self.domain = domain
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    public static func exported(domain: String, data: Data) throws -> Self? {
        guard let values = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw MachineBaselineCaptureError.invalidCommandOutput(path: "/usr/bin/defaults")
        }
        guard !values.isEmpty else { return nil }
        return Self(
            domain: domain,
            byteCount: data.count,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }
}

public struct KeychainMetadataSnapshot: Codable, Equatable, Sendable {
    public let service: String
    public let metadataSHA256: String

    public init(service: String, metadataSHA256: String) {
        self.service = service
        self.metadataSHA256 = metadataSHA256
    }
}

public struct PacketFilterSnapshot: Codable, Equatable, Sendable {
    public let anchor: String
    public let normalizedRules: [String]
    public let verified: Bool

    public init(anchor: String, normalizedRules: [String], verified: Bool) {
        self.anchor = anchor
        self.normalizedRules = normalizedRules.sorted()
        self.verified = verified
    }
}

public struct CanonicalMachineBaseline: Equatable, Sendable {
    public let schemaVersion: Int
    public let hostHardware: HostHardwareIdentity
    public let macOSVersion: String
    public let packageReceipt: ReceiptSnapshot?
    public let usrLocalPayload: [FileSnapshot]
    public let launchServices: [LaunchServiceSnapshot]
    public let runtimeProcesses: [ProcessSnapshot]
    public let runtimePaths: [PathSnapshot]
    public let defaults: DefaultsSnapshot?
    public let keychainItems: [KeychainMetadataSnapshot]
    public let resolvers: [FileSnapshot]
    public let packetFilter: PacketFilterSnapshot
    public let testCaches: [PathSnapshot]
    public let verificationErrors: [String]
}

public struct MachineBaseline: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let hostHardware: HostHardwareIdentity
    public let macOSVersion: String
    public let packageReceipt: ReceiptSnapshot?
    public let usrLocalPayload: [FileSnapshot]
    public let launchServices: [LaunchServiceSnapshot]
    public let runtimeProcesses: [ProcessSnapshot]
    public let runtimePaths: [PathSnapshot]
    public let defaults: DefaultsSnapshot?
    public let keychainItems: [KeychainMetadataSnapshot]
    public let resolvers: [FileSnapshot]
    public let packetFilter: PacketFilterSnapshot
    public let testCaches: [PathSnapshot]
    public let verificationErrors: [String]
    public let capturedAt: Date

    public init(
        schemaVersion: Int = 1,
        hostHardware: HostHardwareIdentity,
        macOSVersion: String,
        packageReceipt: ReceiptSnapshot?,
        usrLocalPayload: [FileSnapshot],
        launchServices: [LaunchServiceSnapshot],
        runtimeProcesses: [ProcessSnapshot],
        runtimePaths: [PathSnapshot],
        defaults: DefaultsSnapshot?,
        keychainItems: [KeychainMetadataSnapshot],
        resolvers: [FileSnapshot],
        packetFilter: PacketFilterSnapshot,
        testCaches: [PathSnapshot],
        verificationErrors: [String] = [],
        capturedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.hostHardware = hostHardware
        self.macOSVersion = macOSVersion
        self.packageReceipt = packageReceipt
        self.usrLocalPayload = usrLocalPayload.sorted { $0.path < $1.path }
        self.launchServices = launchServices.sorted { $0.label < $1.label }
        self.runtimeProcesses = runtimeProcesses.sorted {
            ($0.executablePath, $0.processID) < ($1.executablePath, $1.processID)
        }
        self.runtimePaths = runtimePaths.sorted { $0.root < $1.root }
        self.defaults = defaults
        self.keychainItems = keychainItems.sorted { $0.service < $1.service }
        self.resolvers = resolvers.sorted { $0.path < $1.path }
        self.packetFilter = packetFilter
        self.testCaches = testCaches.sorted { $0.root < $1.root }
        self.verificationErrors = verificationErrors.sorted()
        self.capturedAt = capturedAt
    }

    public var canonicalForComparison: CanonicalMachineBaseline {
        CanonicalMachineBaseline(
            schemaVersion: schemaVersion,
            hostHardware: hostHardware,
            macOSVersion: macOSVersion,
            packageReceipt: packageReceipt,
            usrLocalPayload: usrLocalPayload,
            launchServices: launchServices.map {
                LaunchServiceSnapshot(
                    label: $0.label,
                    state: $0.state,
                    executablePath: $0.executablePath,
                    executableSHA256: $0.executableSHA256,
                    teamID: $0.teamID
                )
            },
            runtimeProcesses: runtimeProcesses.map {
                ProcessSnapshot(
                    executablePath: $0.executablePath,
                    executableSHA256: $0.executableSHA256,
                    teamID: $0.teamID,
                    processID: 0
                )
            },
            runtimePaths: runtimePaths,
            defaults: defaults,
            keychainItems: keychainItems,
            resolvers: resolvers,
            packetFilter: packetFilter,
            testCaches: testCaches,
            verificationErrors: verificationErrors
        )
    }

    public var existingStateReasons: [String] {
        var reasons: [String] = []
        if packageReceipt != nil {
            reasons.append("package-receipt")
        }
        if !usrLocalPayload.isEmpty {
            reasons.append("usr-local-payload")
        }
        if !launchServices.isEmpty {
            reasons.append("launch-services")
        }
        if !runtimeProcesses.isEmpty {
            reasons.append("runtime-processes")
        }
        if !runtimePaths.isEmpty {
            reasons.append("runtime-paths")
        }
        if defaults != nil {
            reasons.append("defaults-domain")
        }
        if !keychainItems.isEmpty {
            reasons.append("keychain-items")
        }
        if !resolvers.isEmpty {
            reasons.append("resolver-files")
        }
        if !packetFilter.verified {
            reasons.append("packet-filter-unverified")
        }
        if !packetFilter.normalizedRules.isEmpty {
            reasons.append("packet-filter-rules")
        }
        if !testCaches.isEmpty {
            reasons.append("physical-test-caches")
        }
        reasons.append(contentsOf: verificationErrors.map { "verification-error:\($0)" })
        return reasons
    }

    public func applyingTrustedPacketFilterAudit(residuePresent: Bool) -> Self {
        let rules = residuePresent ? ["helper-audited-residue-present"] : []
        return Self(
            schemaVersion: schemaVersion,
            hostHardware: hostHardware,
            macOSVersion: macOSVersion,
            packageReceipt: packageReceipt,
            usrLocalPayload: usrLocalPayload,
            launchServices: launchServices,
            runtimeProcesses: runtimeProcesses,
            runtimePaths: runtimePaths,
            defaults: defaults,
            keychainItems: keychainItems,
            resolvers: resolvers,
            packetFilter: .init(
                anchor: packetFilter.anchor,
                normalizedRules: rules,
                verified: true
            ),
            testCaches: testCaches,
            verificationErrors: verificationErrors.filter {
                $0 != "packet-filter-command" && $0 != "packet-filter-read"
            },
            capturedAt: capturedAt
        )
    }
}

public enum PhysicalPreflightPermission: String, Codable, Equatable, Sendable {
    case safeToTest
    case refusedExistingState
}

public struct PhysicalPreflightResult: Codable, Equatable, Sendable {
    public let permission: PhysicalPreflightPermission
    public let refusalReasons: [String]
    public let baseline: MachineBaseline

    public init(permission: PhysicalPreflightPermission, refusalReasons: [String], baseline: MachineBaseline) {
        self.permission = permission
        self.refusalReasons = refusalReasons
        self.baseline = baseline
    }
}

public protocol PhysicalPreflightEnvironment: Sendable {
    func captureBaseline() async throws -> MachineBaseline
}

public struct PhysicalPreflight: Sendable {
    private let environment: any PhysicalPreflightEnvironment

    public init(environment: any PhysicalPreflightEnvironment) {
        self.environment = environment
    }

    public func run() async throws -> PhysicalPreflightResult {
        let baseline = try await environment.captureBaseline()
        let reasons = baseline.existingStateReasons
        return PhysicalPreflightResult(
            permission: reasons.isEmpty ? .safeToTest : .refusedExistingState,
            refusalReasons: reasons,
            baseline: baseline
        )
    }
}

public struct SystemPhysicalPreflightEnvironment: PhysicalPreflightEnvironment {
    public init() {}

    public func captureBaseline() async throws -> MachineBaseline {
        try SystemMachineBaselineCollector().capture()
    }
}

public enum MachineBaselineCaptureError: Error, Equatable {
    case commandFailed(path: String, status: Int32)
    case invalidCommandOutput(path: String)
    case inventoryTooLarge(path: String)
}

private struct CommandResult {
    let status: Int32
    let standardOutput: Data
    let standardError: Data
}

private final class CommandOutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedData = Data()

    var data: Data {
        lock.withLock { storedData }
    }

    func store(_ data: Data) {
        lock.withLock { storedData = data }
    }
}

private struct SystemMachineBaselineCollector {
    private let fileManager = FileManager.default
    private let receiptIdentifier = "com.apple.container-installer"
    private let runtimeServicePrefix = "com.apple.container."
    private let packetFilterAnchor = "com.apple.container"

    func capture() throws -> MachineBaseline {
        let home = fileManager.homeDirectoryForCurrentUser.path
        let host = try HostHardwareIdentity(
            model: commandText("/usr/sbin/sysctl", ["-n", "hw.model"]),
            architecture: commandText("/usr/bin/uname", ["-m"]),
            hardwareUUIDSHA256: Self.sha256(
                Data(commandText("/usr/sbin/sysctl", ["-n", "kern.uuid"]).utf8)
            )
        )
        let receipt = try captureReceipt()
        var errors: [String] = []
        let packetFilter = capturePacketFilter(errors: &errors)

        return try MachineBaseline(
            hostHardware: host,
            macOSVersion: commandText("/usr/bin/sw_vers", ["-productVersion"]),
            packageReceipt: receipt,
            usrLocalPayload: captureReceiptPayload(receipt: receipt, errors: &errors),
            launchServices: captureLaunchServices(errors: &errors),
            runtimeProcesses: captureRuntimeProcesses(errors: &errors),
            runtimePaths: captureExistingTrees([
                "\(home)/Library/Application Support/com.apple.container",
                "\(home)/.config/container",
                "\(home)/.container",
                "/Library/Application Support/com.apple.container",
                "/var/run/com.apple.container"
            ], errors: &errors),
            defaults: captureDefaults(errors: &errors),
            keychainItems: captureKeychainMetadata(errors: &errors),
            resolvers: captureResolverFiles(errors: &errors),
            packetFilter: packetFilter,
            testCaches: captureExistingTrees([
                "\(home)/Library/Caches/container.matrixreligio.com/PhysicalTests",
                "\(home)/Library/Application Support/container.matrixreligio.com/PhysicalTests"
            ], errors: &errors),
            verificationErrors: errors,
            capturedAt: Date()
        )
    }

    private func captureReceipt() throws -> ReceiptSnapshot? {
        let result = try run("/usr/sbin/pkgutil", ["--pkg-info-plist", receiptIdentifier])
        if result.status != 0 {
            return nil
        }
        guard
            let plist = try PropertyListSerialization.propertyList(
                from: result.standardOutput,
                options: [],
                format: nil
            ) as? [String: Any],
            let version = plist["pkg-version"] as? String
        else {
            throw MachineBaselineCaptureError.invalidCommandOutput(path: "/usr/sbin/pkgutil")
        }
        let location = plist["install-location"] as? String ?? "/usr/local"
        return ReceiptSnapshot(identifier: receiptIdentifier, version: version, installLocation: location)
    }

    private func captureReceiptPayload(receipt: ReceiptSnapshot?, errors: inout [String]) -> [FileSnapshot] {
        guard let receipt else { return [] }
        do {
            let result = try run("/usr/sbin/pkgutil", ["--files", receipt.identifier])
            guard result.status == 0 else {
                errors.append("receipt-payload-command")
                return []
            }
            return try text(result.standardOutput).split(separator: "\n").compactMap { relativePath in
                let path = URL(fileURLWithPath: receipt.installLocation, isDirectory: true)
                    .appendingPathComponent(String(relativePath))
                    .standardizedFileURL.path
                return try snapshot(path: path)
            }.sorted { $0.path < $1.path }
        } catch {
            errors.append("receipt-payload-read")
            return []
        }
    }

    private func captureLaunchServices(errors: inout [String]) -> [LaunchServiceSnapshot] {
        do {
            let result = try run("/bin/launchctl", ["list"])
            guard result.status == 0 else {
                errors.append("launch-services-command")
                return []
            }
            return text(result.standardOutput).split(separator: "\n").compactMap { line in
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count >= 3 else { return nil }
                let label = String(fields[2])
                guard label.hasPrefix(runtimeServicePrefix) else { return nil }
                let processID = Int32(fields[0])
                return LaunchServiceSnapshot(
                    label: label,
                    state: fields[1] == "0" ? "loaded" : "failed",
                    processID: processID
                )
            }
        } catch {
            errors.append("launch-services-read")
            return []
        }
    }

    private func captureRuntimeProcesses(errors: inout [String]) -> [ProcessSnapshot] {
        do {
            let result = try run("/bin/ps", ["-axo", "pid=,comm="])
            guard result.status == 0 else {
                errors.append("process-command")
                return []
            }
            let reviewedExecutables = Set(
                ReviewedRuntime110Manifest.package.payload.compactMap { entry -> String? in
                    guard entry.kind == .file else { return nil }
                    return URL(
                        fileURLWithPath: ReviewedRuntime110Manifest.package.installLocation,
                        isDirectory: true
                    ).appendingPathComponent(entry.relativePath).standardizedFileURL.path
                }
            )
            return text(result.standardOutput).split(separator: "\n").compactMap { line in
                let fields = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
                guard fields.count == 2, let processID = Int32(fields[0]) else { return nil }
                let executable = String(fields[1]).trimmingCharacters(in: .whitespaces)
                guard reviewedExecutables.contains(executable) else { return nil }
                return ProcessSnapshot(
                    executablePath: executable,
                    executableSHA256: try? fileSHA256(path: executable),
                    teamID: try? teamID(path: executable),
                    processID: processID
                )
            }
        } catch {
            errors.append("process-read")
            return []
        }
    }

    private func captureDefaults(errors: inout [String]) -> DefaultsSnapshot? {
        let domain = "com.apple.container.defaults"
        do {
            let result = try run("/usr/bin/defaults", ["export", domain, "-"])
            guard result.status == 0 else { return nil }
            return try DefaultsSnapshot.exported(domain: domain, data: result.standardOutput)
        } catch {
            errors.append("defaults-read")
            return nil
        }
    }

    private func captureKeychainMetadata(errors: inout [String]) -> [KeychainMetadataSnapshot] {
        let service = "com.apple.container.registry"
        do {
            let result = try run("/usr/bin/security", ["find-generic-password", "-s", service])
            guard result.status == 0 else { return [] }
            var metadata = result.standardOutput
            metadata.append(result.standardError)
            return [.init(service: service, metadataSHA256: Self.sha256(metadata))]
        } catch {
            errors.append("keychain-metadata-read")
            return []
        }
    }

    private func captureResolverFiles(errors: inout [String]) -> [FileSnapshot] {
        let directory = "/etc/resolver"
        guard fileManager.fileExists(atPath: directory) else { return [] }
        do {
            return try fileManager.contentsOfDirectory(atPath: directory)
                .filter { $0.hasPrefix("containerization.") }
                .compactMap { try snapshot(path: "\(directory)/\($0)") }
                .sorted { $0.path < $1.path }
        } catch {
            errors.append("resolver-read")
            return []
        }
    }

    private func capturePacketFilter(errors: inout [String]) -> PacketFilterSnapshot {
        do {
            let result = try run("/sbin/pfctl", ["-a", packetFilterAnchor, "-sr"])
            guard result.status == 0 else {
                errors.append("packet-filter-command")
                return .init(anchor: packetFilterAnchor, normalizedRules: [], verified: false)
            }
            let rules = text(result.standardOutput).split(separator: "\n")
                .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
                .filter { !$0.isEmpty }
            return .init(anchor: packetFilterAnchor, normalizedRules: rules, verified: true)
        } catch {
            errors.append("packet-filter-read")
            return .init(anchor: packetFilterAnchor, normalizedRules: [], verified: false)
        }
    }

    private func captureExistingTrees(_ paths: [String], errors: inout [String]) -> [PathSnapshot] {
        paths.compactMap { path in
            guard fileManager.fileExists(atPath: path) else { return nil }
            do {
                return try PathSnapshot(root: path, entries: snapshotTree(root: path))
            } catch {
                errors.append("path-read:\(path)")
                return PathSnapshot(root: path, entries: [])
            }
        }
    }

    private func snapshotTree(root: String) throws -> [FileSnapshot] {
        var paths = [root]
        if let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: root, isDirectory: true),
            includingPropertiesForKeys: nil,
            options: [.skipsPackageDescendants]
        ) {
            while let url = enumerator.nextObject() as? URL {
                guard paths.count < 50000 else {
                    throw MachineBaselineCaptureError.inventoryTooLarge(path: root)
                }
                paths.append(url.path)
            }
        }
        return try paths.compactMap { try snapshot(path: $0) }.sorted { $0.path < $1.path }
    }

    private func snapshot(path: String) throws -> FileSnapshot? {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            if errno == ENOENT {
                return nil
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let kind: FileSnapshotKind = switch info.st_mode & S_IFMT {
        case S_IFREG: .file
        case S_IFDIR: .directory
        case S_IFLNK: .symbolicLink
        default: .other
        }
        return try FileSnapshot(
            path: path,
            kind: kind,
            mode: UInt16(info.st_mode & 0o7777),
            ownerID: info.st_uid,
            groupID: info.st_gid,
            size: UInt64(max(info.st_size, 0)),
            sha256: kind == .file ? fileSHA256(path: path) : nil,
            linkTarget: kind == .symbolicLink ? fileManager.destinationOfSymbolicLink(atPath: path) : nil
        )
    }

    private func teamID(path: String) throws -> String? {
        let result = try run("/usr/bin/codesign", ["-dvv", path])
        let output = text(result.standardError)
        return output.split(separator: "\n").first { $0.hasPrefix("TeamIdentifier=") }
            .map { String($0.dropFirst("TeamIdentifier=".count)) }
    }

    private func fileSHA256(path: String) throws -> String {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func commandText(_ path: String, _ arguments: [String]) throws -> String {
        let result = try run(path, arguments)
        guard result.status == 0 else {
            throw MachineBaselineCaptureError.commandFailed(path: path, status: result.status)
        }
        return text(result.standardOutput).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func run(_ path: String, _ arguments: [String]) throws -> CommandResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        let outputBox = CommandOutputBox()
        let errorBox = CommandOutputBox()
        let readers = DispatchGroup()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()

        readers.enter()
        DispatchQueue.global().async {
            outputBox.store(standardOutput.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global().async {
            errorBox.store(standardError.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        process.waitUntilExit()
        readers.wait()
        return CommandResult(
            status: process.terminationStatus,
            standardOutput: outputBox.data,
            standardError: errorBox.data
        )
    }

    private func text(_ data: Data) -> String {
        String(bytes: data, encoding: .utf8) ?? ""
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
