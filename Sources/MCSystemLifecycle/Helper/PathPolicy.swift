import Darwin
import Foundation

public struct PathPolicy: Sendable {
    private let allowedPayload: [String: PayloadEntry]
    private let installRoot: String
    private let requiredOwner: uid_t

    public init(payload: [PayloadEntry], installRoot: String, requiredOwner: uid_t) {
        let fallbackRoot = URL(fileURLWithPath: installRoot).standardizedFileURL.path
        let root = Self.canonicalDirectoryPath(installRoot) ?? fallbackRoot
        self.installRoot = root
        self.requiredOwner = requiredOwner
        allowedPayload = Dictionary(uniqueKeysWithValues: payload.map { entry in
            (root + "/" + entry.relativePath, entry)
        })
    }

    public static let runtime110 = Self(
        payload: Runtime110PathInventory.payload,
        installRoot: "/usr/local",
        requiredOwner: 0
    )

    public func allowsRemoval(_ path: String) -> Bool {
        guard let (candidate, _) = allowedEntry(for: path) else { return false }
        return candidate != installRoot + "/bin" && candidate != installRoot + "/libexec"
    }

    public func allowsResolverName(_ name: String) -> Bool {
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        guard
            (1 ... 253).contains(name.utf8.count),
            !name.hasPrefix("containerization."),
            labels.allSatisfy({ label in
                let bytes = Array(label.utf8)
                guard
                    (1 ... 63).contains(bytes.count),
                    bytes.first?.isASCIILowercaseOrDigit == true,
                    bytes.last?.isASCIILowercaseOrDigit == true
                else {
                    return false
                }
                return bytes.allSatisfy { $0.isASCIILowercaseOrDigit || $0 == 45 }
            })
        else {
            return false
        }
        return true
    }

    public func allowsPacketFilterAnchor(_ anchor: String) -> Bool {
        anchor == "com.apple.container"
    }

    public func authorizeRemoval(_ path: String) throws -> RemovalAuthorization {
        guard let (canonical, entry) = allowedEntry(for: path), allowsRemoval(path) else {
            throw PathPolicyError.pathNotAllowed
        }
        let url = URL(fileURLWithPath: canonical)
        let parentDescriptor = try Self.openDirectoryWithoutFollowingLinks(url.deletingLastPathComponent().path)
        do {
            let identity = try Self.readIdentity(
                parentDescriptor: parentDescriptor,
                childName: url.lastPathComponent,
                expected: entry,
                requiredOwner: requiredOwner
            )
            return RemovalAuthorization(
                parentDescriptor: parentDescriptor,
                childName: url.lastPathComponent,
                expectedIdentity: identity
            )
        } catch {
            Darwin.close(parentDescriptor)
            throw error
        }
    }

    private func canonicalCandidate(_ path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let parent = Self.canonicalDirectoryPath(url.deletingLastPathComponent().path) else { return nil }
        return URL(fileURLWithPath: parent).appendingPathComponent(url.lastPathComponent).path
    }

    private func allowedEntry(for path: String) -> (String, PayloadEntry)? {
        guard path.hasPrefix("/"), !path.split(separator: "/", omittingEmptySubsequences: false).contains("..") else {
            return nil
        }
        let lexical = URL(fileURLWithPath: path).standardizedFileURL.path
        if let entry = allowedPayload[lexical] {
            return (lexical, entry)
        }
        guard let canonical = canonicalCandidate(path), let entry = allowedPayload[canonical] else { return nil }
        return (canonical, entry)
    }

    private static func canonicalDirectoryPath(_ path: String) -> String? {
        guard let resolved = Darwin.realpath(path, nil) else { return nil }
        defer { Darwin.free(resolved) }
        return String(cString: resolved)
    }

    private static func openDirectoryWithoutFollowingLinks(_ path: String) throws -> Int32 {
        var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw PathPolicyError.fileSystem }
        for component in path.split(separator: "/") {
            let next = Darwin.openat(
                descriptor,
                String(component),
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
            Darwin.close(descriptor)
            guard next >= 0 else { throw PathPolicyError.fileSystem }
            descriptor = next
        }
        return descriptor
    }

    fileprivate static func readIdentity(
        parentDescriptor: Int32,
        childName: String,
        expected: PayloadEntry? = nil,
        requiredOwner: uid_t? = nil
    ) throws -> RemovalIdentity {
        var status = stat()
        guard Darwin.fstatat(parentDescriptor, childName, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw PathPolicyError.fileSystem
        }
        if let requiredOwner, status.st_uid != requiredOwner {
            throw PathPolicyError.ownerMismatch
        }
        try validateStatus(
            status,
            parentDescriptor: parentDescriptor,
            childName: childName,
            expected: expected
        )
        return RemovalIdentity(
            device: status.st_dev,
            inode: status.st_ino,
            mode: status.st_mode,
            linkCount: status.st_nlink,
            owner: status.st_uid,
            size: status.st_size,
            modifiedSeconds: status.st_mtimespec.tv_sec,
            modifiedNanoseconds: status.st_mtimespec.tv_nsec
        )
    }

    private static func validateStatus(
        _ status: stat,
        parentDescriptor: Int32,
        childName: String,
        expected: PayloadEntry?
    ) throws {
        let actualKind = try payloadKind(for: status.st_mode)
        guard let expected else {
            if actualKind != .symlink, status.st_mode & 0o022 != 0 {
                throw PathPolicyError.unsafePermissions
            }
            return
        }
        guard actualKind == expected.kind else { throw PathPolicyError.kindMismatch }
        guard actualKind == .symlink || status.st_mode & 0o022 == 0 else {
            throw PathPolicyError.unsafePermissions
        }
        if actualKind == .file, status.st_nlink != 1 {
            throw PathPolicyError.hardLink
        }
        if actualKind == .symlink {
            try validateLinkTarget(
                parentDescriptor: parentDescriptor,
                childName: childName,
                expected: expected
            )
        }
    }

    private static func payloadKind(for mode: mode_t) throws -> PayloadEntry.Kind {
        switch mode & S_IFMT {
        case S_IFREG: .file
        case S_IFDIR: .directory
        case S_IFLNK: .symlink
        default: throw PathPolicyError.kindMismatch
        }
    }

    private static func validateLinkTarget(
        parentDescriptor: Int32,
        childName: String,
        expected: PayloadEntry
    ) throws {
        guard let expectedTarget = expected.linkTarget else { throw PathPolicyError.kindMismatch }
        var buffer = [CChar](repeating: 0, count: 4096)
        let count = Darwin.readlinkat(parentDescriptor, childName, &buffer, buffer.count)
        let target = String(bytes: buffer.prefix(max(0, count)).map { UInt8(bitPattern: $0) }, encoding: .utf8)
        guard count > 0, target == expectedTarget else { throw PathPolicyError.linkTargetMismatch }
    }
}

public final class RemovalAuthorization: @unchecked Sendable {
    public let parentDescriptor: Int32
    public let childName: String
    private let expectedIdentity: RemovalIdentity

    fileprivate init(parentDescriptor: Int32, childName: String, expectedIdentity: RemovalIdentity) {
        self.parentDescriptor = parentDescriptor
        self.childName = childName
        self.expectedIdentity = expectedIdentity
    }

    deinit {
        Darwin.close(parentDescriptor)
    }

    public func revalidate() throws {
        let current = try PathPolicy.readIdentity(parentDescriptor: parentDescriptor, childName: childName)
        guard current == expectedIdentity else { throw PathPolicyError.changedAfterAuthorization }
    }
}

public enum PathPolicyError: Error, Equatable, Sendable {
    case changedAfterAuthorization
    case fileSystem
    case hardLink
    case kindMismatch
    case linkTargetMismatch
    case ownerMismatch
    case pathNotAllowed
    case unsafePermissions
}

private struct RemovalIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
    let mode: mode_t
    let linkCount: nlink_t
    let owner: uid_t
    let size: off_t
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
}

private extension UInt8 {
    var isASCIILowercaseOrDigit: Bool {
        (48 ... 57).contains(self) || (97 ... 122).contains(self)
    }
}
