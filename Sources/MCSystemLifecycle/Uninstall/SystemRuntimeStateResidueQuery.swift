import Darwin
import Foundation
import MCContainerBridge
import Security

public protocol LaunchServiceResidueInspecting: Sendable {
    func hasServices(prefix: String) async throws -> Bool
}

public protocol OwnedProcessResidueInspecting: Sendable {
    func hasOwnedProcess(executablePaths: Set<String>, expectedTeamID: String) throws -> Bool
}

public protocol RegistryCredentialResidueInspecting: Sendable {
    func hasCredentials() async throws -> Bool
}

public protocol PacketFilterResidueInspecting: Sendable {
    func hasRules(anchor: String) async throws -> Bool
}

public struct SystemRuntimeStateResidueQuery: RuntimeStateResidueQuerying {
    private let manifest: RuntimePackageManifest
    private let launchServices: any LaunchServiceResidueInspecting
    private let processes: any OwnedProcessResidueInspecting
    private let credentials: any RegistryCredentialResidueInspecting
    private let packetFilter: any PacketFilterResidueInspecting

    public init(
        manifest: RuntimePackageManifest,
        launchServices: any LaunchServiceResidueInspecting,
        processes: any OwnedProcessResidueInspecting,
        credentials: any RegistryCredentialResidueInspecting,
        packetFilter: any PacketFilterResidueInspecting
    ) {
        self.manifest = manifest
        self.launchServices = launchServices
        self.processes = processes
        self.credentials = credentials
        self.packetFilter = packetFilter
    }

    public static var live: Self {
        .init(
            manifest: ReviewedRuntime110Manifest.package,
            launchServices: AppleLaunchServiceResidueInspector(),
            processes: SystemOwnedProcessResidueInspector(),
            credentials: KeychainCredentialResidueInspector(),
            packetFilter: HelperClient()
        )
    }

    public func status(for kind: ResidueKind) async throws -> ResidueStatus {
        let isPresent = switch kind {
        case .launchService:
            try await launchServices.hasServices(prefix: SystemServiceController.servicePrefix)
        case .process:
            try processes.hasOwnedProcess(
                executablePaths: executablePaths,
                expectedTeamID: manifest.installerTeamID
            )
        case .registryCredential:
            try await credentials.hasCredentials()
        case .packetFilter:
            try await packetFilter.hasRules(anchor: "com.apple.container")
        default:
            throw SystemRuntimeStateResidueError.unsupportedKind(kind)
        }
        return isPresent ? .present : .absent
    }

    private var executablePaths: Set<String> {
        Set(manifest.payload.compactMap { entry in
            guard entry.kind == .file else { return nil }
            return URL(fileURLWithPath: manifest.installLocation, isDirectory: true)
                .appendingPathComponent(entry.relativePath)
                .standardizedFileURL.path
        })
    }
}

public struct AppleLaunchServiceResidueInspector: LaunchServiceResidueInspecting {
    private let services: any ServiceManaging

    public init(
        services: any ServiceManaging = AppleServiceManager(managedPlistURLs: [:])
    ) {
        self.services = services
    }

    public func hasServices(prefix: String) async throws -> Bool {
        try await !services.labels(prefix: prefix).isEmpty
    }
}

public struct KeychainCredentialResidueInspector: RegistryCredentialResidueInspecting {
    private let store: any RegistryCredentialStorage

    public init(store: any RegistryCredentialStorage = RegistryCredentialStore()) {
        self.store = store
    }

    public func hasCredentials() async throws -> Bool {
        try await !store.list().isEmpty
    }
}

extension HelperClient: PacketFilterResidueInspecting {
    public func hasRules(anchor: String) async throws -> Bool {
        let response = try await perform(.auditPacketFilter(anchor: anchor))
        guard let residuePresent = response.residuePresent else {
            throw SystemRuntimeStateResidueError.missingPrivilegedAuditResult
        }
        return residuePresent
    }
}

public struct SystemOwnedProcessResidueInspector: OwnedProcessResidueInspecting {
    public init() {}

    public func hasOwnedProcess(executablePaths: Set<String>, expectedTeamID: String) throws -> Bool {
        guard !executablePaths.isEmpty, !expectedTeamID.isEmpty else {
            throw SystemRuntimeStateResidueError.invalidProcessIdentity
        }
        for processID in try processIDs() {
            guard let path = try executablePath(processID: processID), executablePaths.contains(path) else {
                continue
            }
            try verifyTeamID(expectedTeamID, processID: processID)
            return true
        }
        return false
    }

    private func processIDs() throws -> [pid_t] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity >= 0 else { throw posixError() }
        var processIDs = [pid_t](repeating: 0, count: Int(capacity) + 32)
        let byteCount = Int32(processIDs.count * MemoryLayout<pid_t>.stride)
        let count = proc_listallpids(&processIDs, byteCount)
        guard count >= 0 else { throw posixError() }
        return Array(processIDs.prefix(Int(count))).filter { $0 > 0 }
    }

    private func executablePath(processID: pid_t) throws -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        errno = 0
        let count = proc_pidpath(processID, &buffer, UInt32(buffer.count))
        if count > 0 {
            let bytes = buffer.prefix(Int(count))
                .prefix { $0 != 0 }
                .map { UInt8(bitPattern: $0) }
            guard let path = String(bytes: bytes, encoding: .utf8) else {
                throw SystemRuntimeStateResidueError.invalidProcessPath
            }
            return path
        }
        if errno == ESRCH || errno == ENOENT || errno == 0 {
            return nil
        }
        throw posixError()
    }

    private func verifyTeamID(_ expectedTeamID: String, processID: pid_t) throws {
        let attributes = [kSecGuestAttributePid as String: processID]
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &code) == errSecSuccess,
              let code,
              SecCodeCheckValidity(code, [], nil) == errSecSuccess
        else {
            throw SystemRuntimeStateResidueError.invalidProcessSignature
        }
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode,
              SecCodeCopySigningInformation(
                  staticCode,
                  SecCSFlags(rawValue: kSecCSSigningInformation),
                  &information
              ) ==
              errSecSuccess,
              let values = information as? [String: Any],
              values[kSecCodeInfoTeamIdentifier as String] as? String == expectedTeamID
        else {
            throw SystemRuntimeStateResidueError.invalidProcessSignature
        }
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}

public enum SystemRuntimeStateResidueError: Error, Equatable, Sendable {
    case invalidProcessIdentity
    case invalidProcessPath
    case invalidProcessSignature
    case missingPrivilegedAuditResult
    case unsupportedKind(ResidueKind)
}
