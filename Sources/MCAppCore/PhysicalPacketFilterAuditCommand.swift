import Darwin
import Foundation
import MCModel
import MCSystemLifecycle

public protocol PacketFilterAuditing: Sendable {
    func hasRules(anchor: String) async throws -> Bool
}

extension HelperClient: PacketFilterAuditing {}

public struct PhysicalPacketFilterAuditResult: Codable, Equatable, Sendable {
    public let verified: Bool
    public let residuePresent: Bool
    public let errorDomain: String?
    public let errorCode: Int?

    public init(
        verified: Bool,
        residuePresent: Bool,
        errorDomain: String? = nil,
        errorCode: Int? = nil
    ) {
        self.verified = verified
        self.residuePresent = residuePresent
        self.errorDomain = errorDomain
        self.errorCode = errorCode
    }
}

public struct PhysicalHelperBootstrapResult: Codable, Equatable, Sendable {
    public let status: String
    public let errorDomain: String?
    public let errorCode: Int?

    public init(status: String, errorDomain: String? = nil, errorCode: Int? = nil) {
        self.status = status
        self.errorDomain = errorDomain
        self.errorCode = errorCode
    }
}

public struct PhysicalHelperBootstrapCommand: Sendable {
    private enum Operation: Sendable {
        case register
        case unregister
    }

    private struct Specification {
        let operation: Operation
        let argumentPrefix: String
        let filenamePrefix: String
    }

    private let outputURL: URL
    private let operation: Operation
    private let registrar: any PrivilegedHelperRegistering

    public init?(
        arguments: [String],
        environment: [String: String],
        registrar: any PrivilegedHelperRegistering = PrivilegedHelperRegistrar()
    ) {
        let specifications = [
            Specification(
                operation: .register,
                argumentPrefix: "--physical-helper-bootstrap-output=",
                filenamePrefix: "helper-bootstrap-"
            ),
            Specification(
                operation: .unregister,
                argumentPrefix: "--physical-helper-cleanup-output=",
                filenamePrefix: "helper-cleanup-"
            )
        ]
        let matches = specifications.compactMap { specification in
            authorizedOutputURL(
                arguments: arguments,
                environment: environment,
                argumentPrefix: specification.argumentPrefix,
                filenamePrefix: specification.filenamePrefix
            ).map { (specification.operation, $0) }
        }
        guard matches.count == 1, let match = matches.first else {
            return nil
        }
        operation = match.0
        outputURL = match.1
        self.registrar = registrar
    }

    public func execute() async throws {
        let result: PhysicalHelperBootstrapResult
        do {
            switch operation {
            case .register:
                let status = try await registrar.ensureAvailable()
                result = PhysicalHelperBootstrapResult(status: Self.label(for: status))
            case .unregister:
                try await registrar.unregister()
                result = PhysicalHelperBootstrapResult(status: "unregistered")
            }
        } catch {
            let status = await registrar.status()
            if status == .enabled || status == .requiresApproval {
                result = PhysicalHelperBootstrapResult(status: Self.label(for: status))
            } else {
                let error = error as NSError
                result = PhysicalHelperBootstrapResult(
                    status: "failed",
                    errorDomain: error.domain,
                    errorCode: error.code
                )
            }
        }
        try writeExclusiveJSON(result, to: outputURL)
    }

    private static func label(for status: PrivilegedHelperRegistrationStatus) -> String {
        switch status {
        case .enabled:
            "enabled"
        case .requiresApproval:
            "requires-approval"
        case .notRegistered:
            "not-registered"
        case .notFound:
            "not-found"
        case .unknown:
            "unknown"
        }
    }
}

public struct PhysicalPacketFilterAuditCommand: Sendable {
    private let outputURL: URL
    private let helper: any PacketFilterAuditing

    public init?(
        arguments: [String],
        environment: [String: String],
        helper: any PacketFilterAuditing = HelperClient()
    ) {
        guard let outputURL = authorizedOutputURL(
            arguments: arguments,
            environment: environment,
            argumentPrefix: "--physical-pf-audit-output=",
            filenamePrefix: "packet-filter-"
        ) else {
            return nil
        }
        self.outputURL = outputURL
        self.helper = helper
    }

    public func execute() async throws {
        let result: PhysicalPacketFilterAuditResult
        do {
            let residuePresent = try await helper.hasRules(anchor: "com.apple.container")
            result = .init(verified: true, residuePresent: residuePresent)
        } catch {
            let error = error as NSError
            result = .init(
                verified: false,
                residuePresent: false,
                errorDomain: error.domain,
                errorCode: error.code
            )
        }
        try writeExclusiveJSON(result, to: outputURL)
    }
}

public struct PhysicalCompleteUninstallResult: Equatable, Sendable {
    public let completion: String
    public let auditEmpty: Bool
    public let auditComplete: Bool
    public let preservedCount: Int

    public init(
        completion: String,
        auditEmpty: Bool,
        auditComplete: Bool,
        preservedCount: Int
    ) {
        self.completion = completion
        self.auditEmpty = auditEmpty
        self.auditComplete = auditComplete
        self.preservedCount = preservedCount
    }
}

public protocol PhysicalPrivilegedOperationExecuting: Sendable {
    func install(version: String, packageURL: URL) async throws
    func roundTripDNS(domain: String) async throws
    func completeUninstall() async throws -> PhysicalCompleteUninstallResult
}

public enum PhysicalPrivilegedOperationStage: String, Codable, Sendable {
    case inventoryPreparation = "inventory-preparation"
    case uninstallTransaction = "uninstall-transaction"
}

public struct PhysicalPrivilegedOperationStageFailure: Error {
    public let stage: PhysicalPrivilegedOperationStage
    public let underlying: any Error

    public init(stage: PhysicalPrivilegedOperationStage, underlying: any Error) {
        self.stage = stage
        self.underlying = underlying
    }
}

public struct PhysicalOperationExecutor: PhysicalPrivilegedOperationExecuting {
    public init() {}

    public func install(version: String, packageURL: URL) async throws {
        let manifest = switch version {
        case "1.0.0": ReviewedRuntime100Manifest.package
        case "1.1.0": ReviewedRuntime110Manifest.package
        default: throw PhysicalPrivilegedOperationError.unreviewedRuntime
        }
        let package = try await RuntimePackageVerifier.system.verify(
            packageAt: packageURL,
            against: manifest
        )
        try await HelperClient().install(package)
    }

    public func roundTripDNS(domain: String) async throws {
        let backend = PrivilegedDNSBackend()
        var created = false
        do {
            let expected = DNSEntry(name: domain, addresses: ["192.0.2.10"])
            let result = try await backend.create(name: domain, redirectIPv4: "192.0.2.10")
            created = true
            guard result == expected, try await backend.list().contains(expected) else {
                throw PhysicalPrivilegedOperationError.dnsRoundTripMismatch
            }
            try await backend.delete(name: domain)
            created = false
            guard try await !backend.list().contains(where: { $0.name == domain }) else {
                throw PhysicalPrivilegedOperationError.dnsRoundTripMismatch
            }
        } catch {
            if created {
                try? await backend.delete(name: domain)
            }
            throw error
        }
    }

    public func completeUninstall() async throws -> PhysicalCompleteUninstallResult {
        let lifecycle = ProductionRuntimeLifecycle()
        let inventory: UninstallInventory
        do {
            inventory = try await lifecycle.prepareUninstall(mode: .complete)
        } catch {
            throw PhysicalPrivilegedOperationStageFailure(
                stage: .inventoryPreparation,
                underlying: error
            )
        }
        let result: UninstallResult
        do {
            result = try await lifecycle.uninstall(
                mode: .complete,
                inventoryFingerprint: inventory.fingerprint,
                acknowledgesIrreversibleDeletion: true
            )
        } catch {
            throw PhysicalPrivilegedOperationStageFailure(
                stage: .uninstallTransaction,
                underlying: error
            )
        }
        return PhysicalCompleteUninstallResult(
            completion: result.completion == .complete ? "complete" : "data-preserved",
            auditEmpty: result.audit.isEmpty,
            auditComplete: result.audit.hasCompleteInventory,
            preservedCount: result.preservedKinds.count
        )
    }
}

public struct PhysicalPrivilegedOperationResult: Codable, Equatable, Sendable {
    public let operation: String
    public let succeeded: Bool
    public let completion: String?
    public let auditEmpty: Bool?
    public let auditComplete: Bool?
    public let preservedCount: Int?
    public let errorStage: String?
    public let errorDomain: String?
    public let errorCode: Int?

    public init(
        operation: String,
        succeeded: Bool,
        completion: String? = nil,
        auditEmpty: Bool? = nil,
        auditComplete: Bool? = nil,
        preservedCount: Int? = nil,
        errorStage: String? = nil,
        errorDomain: String? = nil,
        errorCode: Int? = nil
    ) {
        self.operation = operation
        self.succeeded = succeeded
        self.completion = completion
        self.auditEmpty = auditEmpty
        self.auditComplete = auditComplete
        self.preservedCount = preservedCount
        self.errorStage = errorStage
        self.errorDomain = errorDomain
        self.errorCode = errorCode
    }
}

public struct PhysicalPrivilegedOperationCommand: Sendable {
    private enum Operation: String, Sendable {
        case install100 = "install-1.0.0"
        case install110 = "install-1.1.0"
        case dnsRoundTrip = "dns-round-trip"
        case completeUninstall = "complete-uninstall"
    }

    private let operation: Operation
    private let outputURL: URL
    private let runID: UUID
    private let runRoot: URL
    private let packageSourceURL: URL?
    private let executor: any PhysicalPrivilegedOperationExecuting

    public init?(
        arguments: [String],
        environment: [String: String],
        executor: any PhysicalPrivilegedOperationExecuting = PhysicalOperationExecutor()
    ) {
        let operationPrefix = "--physical-helper-operation="
        let operationArguments = arguments.filter { $0.hasPrefix(operationPrefix) }
        guard operationArguments.count == 1,
              let value = operationArguments.first.map({ String($0.dropFirst(operationPrefix.count)) }),
              let operation = Operation(rawValue: value),
              let outputURL = authorizedOutputURL(
                  arguments: arguments,
                  environment: environment,
                  argumentPrefix: "--physical-helper-operation-output=",
                  filenamePrefix: "helper-operation-"
              ),
              let authorizedRun = authorizedPhysicalRun(environment: environment)
        else {
            return nil
        }
        self.operation = operation
        self.outputURL = outputURL
        runID = authorizedRun.id
        runRoot = authorizedRun.root
        let packageSourcePrefix = "--physical-helper-package-source="
        let packageSourceArguments = arguments.filter { $0.hasPrefix(packageSourcePrefix) }
        guard packageSourceArguments.count <= 1 else { return nil }
        if let packageSourceArgument = packageSourceArguments.first {
            guard operation == .install100,
                  let packageSourceURL = Self.authorizedRollbackPackageURL(
                      String(packageSourceArgument.dropFirst(packageSourcePrefix.count)),
                      runRoot: authorizedRun.root
                  )
            else {
                return nil
            }
            self.packageSourceURL = packageSourceURL
        } else {
            packageSourceURL = nil
        }
        self.executor = executor
    }

    public func execute() async throws {
        let result: PhysicalPrivilegedOperationResult
        do {
            switch operation {
            case .install100:
                try await executor.install(
                    version: "1.0.0",
                    packageURL: packageURL(version: "1.0.0")
                )
                result = .init(operation: operation.rawValue, succeeded: true)
            case .install110:
                try await executor.install(
                    version: "1.1.0",
                    packageURL: packageURL(version: "1.1.0")
                )
                result = .init(operation: operation.rawValue, succeeded: true)
            case .dnsRoundTrip:
                try await executor.roundTripDNS(
                    domain: "mct-e2e-\(runID.uuidString.lowercased()).test"
                )
                result = .init(operation: operation.rawValue, succeeded: true)
            case .completeUninstall:
                let uninstall = try await executor.completeUninstall()
                result = .init(
                    operation: operation.rawValue,
                    succeeded: true,
                    completion: uninstall.completion,
                    auditEmpty: uninstall.auditEmpty,
                    auditComplete: uninstall.auditComplete,
                    preservedCount: uninstall.preservedCount
                )
            }
        } catch {
            let stageFailure = error as? PhysicalPrivilegedOperationStageFailure
            let error = (stageFailure?.underlying ?? error) as NSError
            result = .init(
                operation: operation.rawValue,
                succeeded: false,
                errorStage: stageFailure?.stage.rawValue,
                errorDomain: error.domain,
                errorCode: error.code
            )
        }
        try writeExclusiveJSON(result, to: outputURL)
    }

    private func packageURL(version: String) throws -> URL {
        if let packageSourceURL {
            return packageSourceURL
        }
        let filename = "container-\(version)-installer-signed.pkg"
        let url = runRoot
            .appendingPathComponent("downloads", isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
            .standardizedFileURL
        var status = stat()
        guard Darwin.lstat(url.path, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG,
              status.st_uid == geteuid(),
              status.st_nlink == 1,
              status.st_mode & 0o022 == 0
        else {
            throw PhysicalPrivilegedOperationError.packageUnavailable
        }
        return url
    }

    private static func authorizedRollbackPackageURL(_ path: String, runRoot: URL) -> URL? {
        let url = URL(fileURLWithPath: path, isDirectory: false).standardizedFileURL
        guard path == url.path,
              url.lastPathComponent == "00-container-1.0.0-installer-signed.pkg"
        else {
            return nil
        }
        let pointRoot = url.deletingLastPathComponent()
        guard let pointID = UUID(uuidString: pointRoot.lastPathComponent),
              pointRoot.lastPathComponent == pointID.uuidString
        else {
            return nil
        }
        let rollbackRoot = runRoot
            .appendingPathComponent("upgrade-state", isDirectory: true)
            .appendingPathComponent("rollback", isDirectory: true)
        guard pointRoot.deletingLastPathComponent() == rollbackRoot,
              [runRoot.appendingPathComponent("upgrade-state", isDirectory: true),
               rollbackRoot, pointRoot].allSatisfy(Self.isPrivateOwnedDirectory),
              Self.isPrivateOwnedPackage(url)
        else {
            return nil
        }
        return url
    }

    private static func isPrivateOwnedDirectory(_ url: URL) -> Bool {
        var status = stat()
        return Darwin.lstat(url.path, &status) == 0 &&
            status.st_mode & S_IFMT == S_IFDIR &&
            status.st_uid == geteuid() &&
            status.st_mode & 0o077 == 0
    }

    private static func isPrivateOwnedPackage(_ url: URL) -> Bool {
        var status = stat()
        return Darwin.lstat(url.path, &status) == 0 &&
            status.st_mode & S_IFMT == S_IFREG &&
            status.st_uid == geteuid() &&
            status.st_nlink == 1 &&
            status.st_mode & 0o077 == 0
    }
}

private enum PhysicalPrivilegedOperationError: Error {
    case dnsRoundTripMismatch
    case packageUnavailable
    case unreviewedRuntime
}

private func authorizedPhysicalRun(environment: [String: String]) -> (id: UUID, root: URL)? {
    guard let runIDValue = environment["PHYSICAL_RUN_ID"],
          let runID = UUID(uuidString: runIDValue),
          runIDValue == runID.uuidString.lowercased(),
          let runRootValue = environment["PHYSICAL_RUN_ROOT"]
    else {
        return nil
    }
    let root = URL(fileURLWithPath: runRootValue, isDirectory: true).standardizedFileURL
    var status = stat()
    guard root.path.hasPrefix("/"),
          root.lastPathComponent == runIDValue,
          Darwin.lstat(root.path, &status) == 0,
          status.st_mode & S_IFMT == S_IFDIR,
          status.st_uid == geteuid(),
          status.st_mode & 0o077 == 0
    else {
        return nil
    }
    return (runID, root)
}

private func authorizedOutputURL(
    arguments: [String],
    environment: [String: String],
    argumentPrefix: String,
    filenamePrefix: String
) -> URL? {
    guard let argument = arguments.first(where: { $0.hasPrefix(argumentPrefix) }),
          let authorization = environment["PHYSICAL_AUDIT_AUTHORIZATION"],
          let runID = UUID(uuidString: authorization),
          authorization == runID.uuidString.lowercased(),
          let rootPath = environment["PHYSICAL_AUDIT_ROOT"]
    else {
        return nil
    }
    let root = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
    let output = URL(
        fileURLWithPath: String(argument.dropFirst(argumentPrefix.count)),
        isDirectory: false
    ).standardizedFileURL
    var status = stat()
    guard root.path.hasPrefix("/"),
          Darwin.lstat(root.path, &status) == 0,
          status.st_mode & S_IFMT == S_IFDIR,
          status.st_uid == geteuid(),
          status.st_mode & 0o077 == 0,
          output.deletingLastPathComponent() == root,
          output.lastPathComponent == "\(filenamePrefix)\(authorization).json",
          Darwin.lstat(output.path, &status) != 0,
          errno == ENOENT
    else {
        return nil
    }
    return output
}

private func writeExclusiveJSON(_ value: some Encodable, to outputURL: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    let descriptor = Darwin.open(
        outputURL.path,
        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
        0o600
    )
    guard descriptor >= 0 else { throw posixError() }
    defer { Darwin.close(descriptor) }
    try data.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
            let count = Darwin.write(
                descriptor,
                buffer.baseAddress?.advanced(by: offset),
                buffer.count - offset
            )
            guard count >= 0 else {
                if errno == EINTR {
                    continue
                }
                throw posixError()
            }
            offset += count
        }
    }
    guard Darwin.fsync(descriptor) == 0 else { throw posixError() }
}

private func posixError() -> NSError {
    NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
}
