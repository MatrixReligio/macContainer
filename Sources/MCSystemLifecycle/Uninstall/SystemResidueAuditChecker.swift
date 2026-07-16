import Darwin
import Foundation

public protocol RuntimeStateResidueQuerying: Sendable {
    func status(for kind: ResidueKind) async throws -> ResidueStatus
}

public protocol DefaultsResidueInspecting: Sendable {
    func containsPersistentDomain(_ domain: String) throws -> Bool
}

public struct SystemResidueAuditConfiguration: Sendable {
    public let userArtifacts: UninstallUserArtifactLocations
    public let receiptDirectory: URL
    public let resolverDirectory: URL
    public let installRoot: URL
    public let runtimeOwnedDirectory: URL
    public let manifest: RuntimePackageManifest

    public init(
        userArtifacts: UninstallUserArtifactLocations,
        receiptDirectory: URL,
        resolverDirectory: URL,
        installRoot: URL,
        runtimeOwnedDirectory: URL,
        manifest: RuntimePackageManifest
    ) {
        self.userArtifacts = userArtifacts
        self.receiptDirectory = receiptDirectory.standardizedFileURL
        self.resolverDirectory = resolverDirectory.standardizedFileURL
        self.installRoot = installRoot.standardizedFileURL
        self.runtimeOwnedDirectory = runtimeOwnedDirectory.standardizedFileURL
        self.manifest = manifest
    }

    public static var live: Self {
        let manifest = ReviewedRuntime110Manifest.package
        let installRoot = URL(fileURLWithPath: manifest.installLocation, isDirectory: true)
        return .init(
            userArtifacts: .live,
            receiptDirectory: URL(fileURLWithPath: "/var/db/receipts", isDirectory: true),
            resolverDirectory: URL(fileURLWithPath: "/etc/resolver", isDirectory: true),
            installRoot: installRoot,
            runtimeOwnedDirectory: installRoot
                .appendingPathComponent("libexec/container", isDirectory: true),
            manifest: manifest
        )
    }
}

public struct SystemResidueAuditChecker: ResidueAuditChecking {
    private static let runtimeStateKinds: Set<ResidueKind> = [
        .launchService, .process, .registryCredential, .packetFilter
    ]
    private static let sharedPayloadDirectories: Set<String> = ["bin", "libexec"]

    private let configuration: SystemResidueAuditConfiguration
    private let runtimeState: any RuntimeStateResidueQuerying
    private let defaults: any DefaultsResidueInspecting

    public init(
        configuration: SystemResidueAuditConfiguration = .live,
        runtimeState: any RuntimeStateResidueQuerying = SystemRuntimeStateResidueQuery.live,
        defaults: any DefaultsResidueInspecting = SystemDefaultsResidueInspector()
    ) {
        self.configuration = configuration
        self.runtimeState = runtimeState
        self.defaults = defaults
    }

    public func status(for kind: ResidueKind) async throws -> ResidueStatus {
        if Self.runtimeStateKinds.contains(kind) {
            return try await runtimeState.status(for: kind)
        }
        switch kind {
        case .receipt:
            return try receiptStatus()
        case .receiptPayload:
            return try payloadStatus()
        case .defaultsDomain:
            return try defaultsStatus()
        case .resolver:
            return try resolverStatus()
        case .runtimeOwnedDirectory:
            return try nonemptyDirectoryStatus(at: configuration.runtimeOwnedDirectory)
        case .applicationSupport, .configuration, .downloadedPackage,
             .rollbackPoint, .testFixture, .downloadCache:
            guard let url = configuration.userArtifacts.fileURLs[kind] else {
                throw SystemResidueAuditError.missingInventoryLocation(kind)
            }
            return try existenceStatus(at: url)
        case .launchService, .process, .registryCredential, .packetFilter:
            throw SystemResidueAuditError.unsupportedResidueKind(kind)
        }
    }

    private func receiptStatus() throws -> ResidueStatus {
        for fileExtension in ["plist", "bom"] {
            let receipt = configuration.receiptDirectory
                .appendingPathComponent("\(configuration.manifest.receiptIdentifier).\(fileExtension)")
            if try existenceStatus(at: receipt) == .present {
                return .present
            }
        }
        return .absent
    }

    private func payloadStatus() throws -> ResidueStatus {
        try configuration.manifest.validate()
        for entry in configuration.manifest.payload where !Self.sharedPayloadDirectories.contains(entry.relativePath) {
            let url = configuration.installRoot.appendingPathComponent(entry.relativePath)
            if try existenceStatus(at: url) == .present {
                return .present
            }
        }
        return .absent
    }

    private func defaultsStatus() throws -> ResidueStatus {
        let domain = configuration.userArtifacts.defaultsDomain
        guard domain == "com.apple.container.defaults" else {
            throw SystemResidueAuditError.unsafeDefaultsDomain
        }
        return try defaults.containsPersistentDomain(domain) ? .present : .absent
    }

    private func resolverStatus() throws -> ResidueStatus {
        switch try nodeStatus(at: configuration.resolverDirectory) {
        case .absent:
            return .absent
        case let .present(status):
            guard status.st_mode & S_IFMT == S_IFDIR else {
                throw SystemResidueAuditError.expectedDirectory
            }
        }
        let children = try FileManager.default.contentsOfDirectory(
            at: configuration.resolverDirectory,
            includingPropertiesForKeys: nil,
            options: []
        )
        return children.contains { $0.lastPathComponent.hasPrefix("containerization.") }
            ? .present
            : .absent
    }

    private func nonemptyDirectoryStatus(at url: URL) throws -> ResidueStatus {
        switch try nodeStatus(at: url) {
        case .absent:
            return .absent
        case let .present(status):
            guard status.st_mode & S_IFMT == S_IFDIR else { return .present }
        }
        return try FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty
            ? .absent
            : .present
    }

    private func existenceStatus(at url: URL) throws -> ResidueStatus {
        switch try nodeStatus(at: url) {
        case .absent: .absent
        case .present: .present
        }
    }

    private func nodeStatus(at url: URL) throws -> NodeStatus {
        guard url.isFileURL, url.path.hasPrefix("/") else {
            throw SystemResidueAuditError.unsafePath
        }
        var status = stat()
        if Darwin.lstat(url.path, &status) == 0 {
            return .present(status)
        }
        if errno == ENOENT || errno == ENOTDIR {
            return .absent
        }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}

public struct SystemDefaultsResidueInspector: DefaultsResidueInspecting {
    public init() {}

    public func containsPersistentDomain(_ domain: String) throws -> Bool {
        guard domain == "com.apple.container.defaults" else {
            throw SystemResidueAuditError.unsafeDefaultsDomain
        }
        return UserDefaults.standard.persistentDomain(forName: domain) != nil
    }
}

public enum SystemResidueAuditError: Error, Equatable, Sendable {
    case expectedDirectory
    case missingInventoryLocation(ResidueKind)
    case unsafeDefaultsDomain
    case unsafePath
    case unsupportedResidueKind(ResidueKind)
}

private enum NodeStatus {
    case absent
    case present(stat)
}
