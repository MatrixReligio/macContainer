import Darwin
import Foundation

public struct PhysicalCleanupPolicy: Sendable {
    public let runID: UUID
    public let runRoot: URL
    public let resourcePrefix: String
    public let credentialPrefix: String

    private let canonicalRunRoot: String

    public init(runID: UUID, runRoot: URL) {
        self.runID = runID
        let standardizedRoot = runRoot.standardizedFileURL
        self.runRoot = standardizedRoot
        canonicalRunRoot = Self.realPath(standardizedRoot.path) ?? standardizedRoot.path
        let suffix = runID.uuidString.lowercased()
        resourcePrefix = "mct-e2e-\(suffix)"
        credentialPrefix = "container.matrixreligio.com.tests.\(suffix)"
    }

    public func validate(_ artifact: TestArtifact) throws {
        switch artifact {
        case let .container(name), let .image(name), let .network(name), let .volume(name),
             let .machine(name):
            try validateResourceName(name)
        case let .registryCredential(name), let .keychain(name), let .launchService(name):
            guard name == credentialPrefix || name.hasPrefix("\(credentialPrefix).") else {
                throw CleanupPolicyError.outsideRunNamespace
            }
        case let .resolver(name):
            guard name == "containerization.\(resourcePrefix)" else {
                throw CleanupPolicyError.outsideRunNamespace
            }
        case let .packetFilterAnchor(name):
            guard name == "com.apple.container.\(resourcePrefix)" else {
                throw CleanupPolicyError.outsideRunNamespace
            }
        case let .rollbackPoint(identifier):
            guard identifier == runID else {
                throw CleanupPolicyError.outsideRunNamespace
            }
        case let .runtimePackage(path), let .temporaryDirectory(path), let .file(path),
             let .resultBundle(path):
            try validatePath(path, allowRunRoot: artifact.isTemporaryDirectory)
        }
    }

    public func validatePath(_ path: String, allowRunRoot: Bool = false) throws {
        guard path.hasPrefix("/"), !path.split(separator: "/", omittingEmptySubsequences: false).contains("..") else {
            throw CleanupPolicyError.outsideRunNamespace
        }
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard let canonical = Self.canonicalPath(standardized) else {
            throw CleanupPolicyError.outsideRunNamespace
        }
        guard canonical != "/", canonical != "/Users", canonical != "/usr/local" else {
            throw CleanupPolicyError.protectedPath
        }
        if canonical == canonicalRunRoot {
            guard allowRunRoot else { throw CleanupPolicyError.outsideRunNamespace }
        } else {
            guard canonical.hasPrefix("\(canonicalRunRoot)/") else {
                throw CleanupPolicyError.outsideRunNamespace
            }
        }

        let parent = URL(fileURLWithPath: standardized).deletingLastPathComponent().path
        if let canonicalParent = Self.realPath(parent) {
            guard canonicalParent == canonicalRunRoot || canonicalParent.hasPrefix("\(canonicalRunRoot)/") else {
                throw CleanupPolicyError.ancestorSubstitution
            }
        }
    }

    private static func canonicalPath(_ path: String) -> String? {
        var ancestor = URL(fileURLWithPath: path).standardizedFileURL
        var missingComponents: [String] = []
        while realPath(ancestor.path) == nil {
            guard ancestor.path != "/", !ancestor.lastPathComponent.isEmpty else { return nil }
            missingComponents.insert(ancestor.lastPathComponent, at: 0)
            let parent = ancestor.deletingLastPathComponent()
            guard parent.path != ancestor.path else { return nil }
            ancestor = parent
        }
        guard let resolvedAncestor = realPath(ancestor.path) else { return nil }
        return missingComponents.reduce(resolvedAncestor) { partial, component in
            partial == "/" ? "/\(component)" : "\(partial)/\(component)"
        }
    }

    private func validateResourceName(_ name: String) throws {
        guard name == resourcePrefix || name.hasPrefix("\(resourcePrefix)-") else {
            throw CleanupPolicyError.outsideRunNamespace
        }
    }

    private static func realPath(_ path: String) -> String? {
        path.withCString { pointer in
            guard let resolved = Darwin.realpath(pointer, nil) else { return nil }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }
}

public enum CleanupPolicyError: Error, Equatable {
    case outsideRunNamespace
    case protectedPath
    case ancestorSubstitution
    case symbolicLinkSubstitution
    case hardLinkSubstitution
    case identityChanged
    case unsupportedArtifact
    case removalFailed
    case absenceVerificationFailed
}

public protocol TestResourceRemoving: Sendable {
    func remove(_ artifact: TestArtifact) async throws
    func isAbsent(_ artifact: TestArtifact) async throws -> Bool
}

public struct RefusingTestResourceRemover: TestResourceRemoving {
    public init() {}

    public func remove(_: TestArtifact) async throws {
        throw CleanupPolicyError.unsupportedArtifact
    }

    public func isAbsent(_: TestArtifact) async throws -> Bool {
        throw CleanupPolicyError.unsupportedArtifact
    }
}

public actor GuardedCleanup {
    private let policy: PhysicalCleanupPolicy
    private let ledger: CleanupLedger
    private let resources: any TestResourceRemoving

    public init(
        policy: PhysicalCleanupPolicy,
        ledger: CleanupLedger,
        resources: any TestResourceRemoving = RefusingTestResourceRemover()
    ) {
        self.policy = policy
        self.ledger = ledger
        self.resources = resources
    }

    public func remove(_ artifact: TestArtifact) async throws {
        try policy.validate(artifact)
        let state = await ledger.state(of: artifact)
        if state == .verifiedAbsent {
            return
        }
        guard state == .created || state == .removed else {
            throw CleanupLedgerError.invalidTransition(from: state, to: .removed)
        }

        if let path = artifact.fileSystemPath {
            try await removePath(path, artifact: artifact, state: state)
        } else {
            try await removeResource(artifact, state: state)
        }
    }

    private func removeResource(_ artifact: TestArtifact, state: CleanupState?) async throws {
        if state == .created {
            try await resources.remove(artifact)
            try await ledger.markRemoved(artifact)
        }
        guard try await resources.isAbsent(artifact) else {
            throw CleanupPolicyError.absenceVerificationFailed
        }
        try await ledger.markVerifiedAbsent(artifact)
    }

    // The explicit branches are the security checks for every filesystem identity transition.
    // swiftlint:disable:next cyclomatic_complexity
    private func removePath(_ path: String, artifact: TestArtifact, state: CleanupState?) async throws {
        if state == .removed {
            guard lstatExists(path) == false else {
                throw CleanupPolicyError.absenceVerificationFailed
            }
            try await ledger.markVerifiedAbsent(artifact)
            return
        }

        var before = stat()
        guard lstat(path, &before) == 0 else {
            if errno == ENOENT {
                try await ledger.markRemoved(artifact)
                try await ledger.markVerifiedAbsent(artifact)
                return
            }
            throw CleanupPolicyError.removalFailed
        }
        let kind = before.st_mode & S_IFMT
        guard kind != S_IFLNK else {
            throw CleanupPolicyError.symbolicLinkSubstitution
        }
        if kind == S_IFREG, before.st_nlink != 1 {
            throw CleanupPolicyError.hardLinkSubstitution
        }
        guard kind == S_IFREG || kind == S_IFDIR else {
            throw CleanupPolicyError.unsupportedArtifact
        }

        let flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC | (kind == S_IFDIR ? O_DIRECTORY : 0)
        let descriptor = open(path, flags)
        guard descriptor >= 0 else {
            throw CleanupPolicyError.identityChanged
        }
        defer { close(descriptor) }
        var opened = stat()
        guard fstat(descriptor, &opened) == 0,
              opened.st_dev == before.st_dev,
              opened.st_ino == before.st_ino,
              opened.st_mode & S_IFMT == kind
        else {
            throw CleanupPolicyError.identityChanged
        }

        if kind == S_IFDIR {
            try removeDirectoryContents(descriptor)
        }
        let removalStatus = kind == S_IFDIR ? rmdir(path) : unlink(path)
        guard removalStatus == 0 else {
            throw CleanupPolicyError.removalFailed
        }
        try await ledger.markRemoved(artifact)
        guard lstatExists(path) == false else {
            throw CleanupPolicyError.absenceVerificationFailed
        }
        try await ledger.markVerifiedAbsent(artifact)
    }

    private func removeDirectoryContents(_ descriptor: Int32) throws {
        let streamDescriptor = Darwin.dup(descriptor)
        guard streamDescriptor >= 0, let stream = fdopendir(streamDescriptor) else {
            if streamDescriptor >= 0 {
                Darwin.close(streamDescriptor)
            }
            throw CleanupPolicyError.removalFailed
        }
        defer { closedir(stream) }

        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                guard errno == 0 else { throw CleanupPolicyError.removalFailed }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
                    String(cString: $0)
                }
            }
            guard name != ".", name != ".." else { continue }
            try removeDirectoryEntry(parent: descriptor, name: name)
        }
    }

    // Each supported POSIX node kind has a distinct no-follow deletion policy.
    // swiftlint:disable:next cyclomatic_complexity
    private func removeDirectoryEntry(parent: Int32, name: String) throws {
        var before = stat()
        guard fstatat(parent, name, &before, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw CleanupPolicyError.identityChanged
        }
        let kind = before.st_mode & S_IFMT
        switch kind {
        case S_IFDIR:
            let child = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard child >= 0 else { throw CleanupPolicyError.identityChanged }
            defer { Darwin.close(child) }
            var opened = stat()
            guard fstat(child, &opened) == 0,
                  opened.st_dev == before.st_dev,
                  opened.st_ino == before.st_ino,
                  opened.st_mode & S_IFMT == S_IFDIR
            else {
                throw CleanupPolicyError.identityChanged
            }
            try removeDirectoryContents(child)
            guard unlinkat(parent, name, AT_REMOVEDIR) == 0 else {
                throw CleanupPolicyError.removalFailed
            }
        case S_IFREG:
            guard before.st_nlink == 1 else { throw CleanupPolicyError.hardLinkSubstitution }
            let child = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard child >= 0 else { throw CleanupPolicyError.identityChanged }
            defer { Darwin.close(child) }
            var opened = stat()
            guard fstat(child, &opened) == 0,
                  opened.st_dev == before.st_dev,
                  opened.st_ino == before.st_ino,
                  opened.st_mode & S_IFMT == S_IFREG
            else {
                throw CleanupPolicyError.identityChanged
            }
            guard unlinkat(parent, name, 0) == 0 else {
                throw CleanupPolicyError.removalFailed
            }
        case S_IFLNK:
            guard unlinkat(parent, name, 0) == 0 else {
                throw CleanupPolicyError.removalFailed
            }
        default:
            throw CleanupPolicyError.unsupportedArtifact
        }
    }

    private func lstatExists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 || errno != ENOENT
    }
}

public struct GuardedCleanupRecovery: Sendable {
    private let policy: PhysicalCleanupPolicy
    private let ledger: CleanupLedger
    private let cleanup: GuardedCleanup
    private let ledgerURL: URL

    public init(
        policy: PhysicalCleanupPolicy,
        ledger: CleanupLedger,
        cleanup: GuardedCleanup,
        ledgerURL: URL
    ) {
        self.policy = policy
        self.ledger = ledger
        self.cleanup = cleanup
        self.ledgerURL = ledgerURL.standardizedFileURL
    }

    public func run() async throws {
        let states = await ledger.allStates()
        try verifyNoUnledgeredPaths(states: states)
        for artifact in states.keys.sorted(by: stableArtifactOrder) {
            switch states[artifact] {
            case .planned:
                guard artifact.fileSystemPath != nil else {
                    throw CleanupPolicyError.unsupportedArtifact
                }
                try await ledger.markCreated(artifact)
                try await cleanup.remove(artifact)
            case .created, .removed:
                try await cleanup.remove(artifact)
            case .verifiedAbsent:
                continue
            case nil:
                throw CleanupLedgerError.corruptLedger
            }
        }
    }

    private func verifyNoUnledgeredPaths(states: [TestArtifact: CleanupState]) throws {
        let manager = FileManager.default
        let allowedPaths = Set(states.keys.compactMap(\.fileSystemPath).map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        }).union([ledgerURL.path])
        guard manager.fileExists(atPath: policy.runRoot.path) else { return }
        guard let enumerator = manager.enumerator(
            at: policy.runRoot,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) else {
            throw CleanupPolicyError.absenceVerificationFailed
        }
        while let url = enumerator.nextObject() as? URL {
            let path = url.standardizedFileURL.path
            guard allowedPaths.contains(path) else {
                throw CleanupPolicyError.outsideRunNamespace
            }
        }
    }

    private func stableArtifactOrder(_ lhs: TestArtifact, _ rhs: TestArtifact) -> Bool {
        let encoder = JSONEncoder()
        let left = (try? encoder.encode(lhs)) ?? Data()
        let right = (try? encoder.encode(rhs)) ?? Data()
        return left.lexicographicallyPrecedes(right)
    }
}
