import Darwin
import Foundation

public struct UninstallUserArtifactLocations: Equatable, Sendable {
    public let fileURLs: [ResidueKind: URL]
    public let defaultsDomain: String

    public init(
        applicationSupport: URL,
        configuration: URL,
        downloadedPackage: URL,
        rollbackPoint: URL,
        testFixture: URL,
        downloadCache: URL,
        defaultsDomain: String
    ) {
        fileURLs = [
            .applicationSupport: applicationSupport.standardizedFileURL,
            .configuration: configuration.standardizedFileURL,
            .downloadedPackage: downloadedPackage.standardizedFileURL,
            .rollbackPoint: rollbackPoint.standardizedFileURL,
            .testFixture: testFixture.standardizedFileURL,
            .downloadCache: downloadCache.standardizedFileURL
        ]
        self.defaultsDomain = defaultsDomain
    }

    public static var live: Self {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let productSupport = applicationSupport
            .appendingPathComponent("container.matrixreligio.com", isDirectory: true)
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("container.matrixreligio.com", isDirectory: true)
        return .init(
            applicationSupport: applicationSupport
                .appendingPathComponent("com.apple.container", isDirectory: true),
            configuration: home
                .appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent("container", isDirectory: true),
            downloadedPackage: productSupport
                .appendingPathComponent("RuntimePackages", isDirectory: true),
            rollbackPoint: RollbackStore.defaultRootDirectory,
            testFixture: productSupport
                .appendingPathComponent("PhysicalTests", isDirectory: true),
            downloadCache: caches.appendingPathComponent("Runtime", isDirectory: true),
            defaultsDomain: "com.apple.container.defaults"
        )
    }
}

public protocol OwnedArtifactRemoving: Sendable {
    func remove(at url: URL) throws
}

public protocol UninstallDefaultsRemoving: Sendable {
    func removePersistentDomain(_ domain: String) throws
}

public struct SystemUninstallUserArtifactRemover: UninstallUserArtifactRemoving {
    public static let fileArtifactKinds: [ResidueKind] = [
        .applicationSupport, .configuration, .downloadedPackage,
        .rollbackPoint, .testFixture, .downloadCache
    ]

    private let locations: UninstallUserArtifactLocations
    private let pathRemover: any OwnedArtifactRemoving
    private let defaults: any UninstallDefaultsRemoving

    public init(
        locations: UninstallUserArtifactLocations = .live,
        pathRemover: any OwnedArtifactRemoving = LocalOwnedArtifactRemover(),
        defaults: any UninstallDefaultsRemoving = SystemDefaultsRemover()
    ) {
        self.locations = locations
        self.pathRemover = pathRemover
        self.defaults = defaults
    }

    public func remove(_ kind: ResidueKind) async throws {
        if kind == .defaultsDomain {
            guard locations.defaultsDomain == "com.apple.container.defaults" else {
                throw UserArtifactRemovalError.unsafeDefaultsDomain
            }
            try defaults.removePersistentDomain(locations.defaultsDomain)
            return
        }
        guard Self.fileArtifactKinds.contains(kind), let url = locations.fileURLs[kind] else {
            throw UserArtifactRemovalError.unsupportedKind(kind)
        }
        try pathRemover.remove(at: url)
    }
}

public struct SystemDefaultsRemover: UninstallDefaultsRemoving {
    public init() {}

    public func removePersistentDomain(_ domain: String) throws {
        guard domain == "com.apple.container.defaults" else {
            throw UserArtifactRemovalError.unsafeDefaultsDomain
        }
        UserDefaults.standard.removePersistentDomain(forName: domain)
        guard UserDefaults.standard.persistentDomain(forName: domain) == nil else {
            throw UserArtifactRemovalError.defaultsRemovalFailed
        }
    }
}

public struct LocalOwnedArtifactRemover: OwnedArtifactRemoving {
    private let requiredOwner: uid_t

    public init(requiredOwner: uid_t = geteuid()) {
        self.requiredOwner = requiredOwner
    }

    public func remove(at url: URL) throws {
        let url = url.standardizedFileURL
        guard url.isFileURL, url.path.hasPrefix("/") else {
            throw UserArtifactRemovalError.unsafePath
        }
        var status = stat()
        guard Darwin.lstat(url.path, &status) == 0 else {
            if errno == ENOENT {
                return
            }
            throw posixError()
        }
        guard status.st_uid == requiredOwner else {
            throw UserArtifactRemovalError.ownerMismatch
        }
        switch status.st_mode & S_IFMT {
        case S_IFLNK, S_IFREG:
            guard Darwin.unlink(url.path) == 0 else { throw posixError() }
        case S_IFDIR:
            try validateTree(at: url, rootDevice: status.st_dev)
            try FileManager.default.removeItem(at: url)
        default:
            throw UserArtifactRemovalError.unsafePath
        }
        guard Darwin.lstat(url.path, &status) != 0, errno == ENOENT else {
            throw UserArtifactRemovalError.removalIncomplete
        }
    }

    private func validateTree(at url: URL, rootDevice: dev_t) throws {
        var status = stat()
        guard Darwin.lstat(url.path, &status) == 0, status.st_uid == requiredOwner else {
            throw UserArtifactRemovalError.ownerMismatch
        }
        let kind = status.st_mode & S_IFMT
        guard kind != S_IFDIR || status.st_dev == rootDevice else {
            throw UserArtifactRemovalError.mountBoundary
        }
        guard kind == S_IFDIR else { return }
        for child in try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            try validateTree(at: child, rootDevice: rootDevice)
        }
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}

public enum UserArtifactRemovalError: Error, Equatable, Sendable {
    case defaultsRemovalFailed
    case mountBoundary
    case ownerMismatch
    case removalIncomplete
    case unsafeDefaultsDomain
    case unsafePath
    case unsupportedKind(ResidueKind)
}
