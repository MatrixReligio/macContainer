import Darwin
import Foundation

public struct SystemPrivilegedHostMutator: PrivilegedHostMutating {
    private let installRoot: URL
    private let resolverDirectory: URL
    private let requiredOwner: uid_t
    private let commandRunner: any FixedPrivilegedCommandRunning

    public init(
        manifest: RuntimePackageManifest,
        commandRunner: any FixedPrivilegedCommandRunning,
        installRoot: URL? = nil,
        resolverDirectory: URL = URL(fileURLWithPath: "/etc/resolver", isDirectory: true),
        requiredOwner: uid_t = 0
    ) {
        self.installRoot = installRoot ?? URL(fileURLWithPath: manifest.installLocation, isDirectory: true)
        self.resolverDirectory = resolverDirectory
        self.requiredOwner = requiredOwner
        self.commandRunner = commandRunner
    }

    public func removePayload(manifest: RuntimePackageManifest) throws {
        let policy = PathPolicy(
            payload: manifest.payload,
            installRoot: installRoot.path,
            requiredOwner: requiredOwner
        )
        for entry in manifest.payload.reversed() where entry.kind != .directory {
            let path = installRoot.appendingPathComponent(entry.relativePath).path
            guard try itemExists(path) else { continue }
            let authorization = try policy.authorizeRemoval(path)
            try authorization.revalidate()
            guard Darwin.unlinkat(authorization.parentDescriptor, authorization.childName, 0) == 0 else {
                throw posixError()
            }
        }
    }

    public func forgetReceipt() throws {
        try commandRunner.run(.forgetContainerReceipt, package: nil)
    }

    public func writeResolver(_ request: ResolverRequest) throws {
        let directory = try openResolverDirectory(createIfMissing: true)
        defer { Darwin.close(directory) }
        let filename = "containerization.\(request.name)"
        try validateExistingResolver(filename, in: directory)

        let temporary = ".maccontainer-\(UUID().uuidString.lowercased()).tmp"
        let descriptor = Darwin.openat(
            directory,
            temporary,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            0o644
        )
        guard descriptor >= 0 else { throw posixError() }
        var temporaryExists = true
        defer {
            Darwin.close(descriptor)
            if temporaryExists {
                Darwin.unlinkat(directory, temporary, 0)
            }
        }
        guard Darwin.fchown(descriptor, requiredOwner, gid_t(bitPattern: Int32(-1))) == 0 else {
            throw posixError()
        }
        guard Darwin.fchmod(descriptor, 0o644) == 0 else { throw posixError() }
        let content = Data(request.nameservers.map { "nameserver \($0)\n" }.joined().utf8)
        try writeAll(content, to: descriptor)
        guard Darwin.fsync(descriptor) == 0 else { throw posixError() }
        guard Darwin.renameat(directory, temporary, directory, filename) == 0 else { throw posixError() }
        temporaryExists = false
        guard Darwin.fsync(directory) == 0 else { throw posixError() }
        try validateExistingResolver(filename, in: directory, mustExist: true)
        try commandRunner.run(.reloadDNS, package: nil)
    }

    public func removeResolver(name: String) throws {
        let directory = try openResolverDirectory(createIfMissing: false)
        guard directory >= 0 else { return }
        defer { Darwin.close(directory) }
        let filename = "containerization.\(name)"
        guard try validateExistingResolver(filename, in: directory) else { return }
        guard Darwin.unlinkat(directory, filename, 0) == 0 else { throw posixError() }
        guard Darwin.fsync(directory) == 0 else { throw posixError() }
        try commandRunner.run(.reloadDNS, package: nil)
    }

    public func applyPacketFilter(_ request: PacketFilterRequest) throws {
        try commandRunner.run(
            .reloadContainerPacketFilter(subnetCIDR: request.subnetCIDR),
            package: nil
        )
    }

    public func removePacketFilter() throws {
        try commandRunner.run(.clearContainerPacketFilter, package: nil)
    }

    public func packetFilterRulesPresent() throws -> Bool {
        let output = try commandRunner.run(.inspectContainerPacketFilter, package: nil)
        guard let text = String(data: output, encoding: .utf8) else {
            throw SystemPrivilegedHostError.invalidCommandOutput
        }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func removeKnownEmptyDirectories(manifest: RuntimePackageManifest) throws {
        let policy = PathPolicy(
            payload: manifest.payload,
            installRoot: installRoot.path,
            requiredOwner: requiredOwner
        )
        let directories = manifest.payload
            .filter { $0.kind == .directory }
            .sorted {
                let leftDepth = $0.relativePath.split(separator: "/").count
                let rightDepth = $1.relativePath.split(separator: "/").count
                return leftDepth == rightDepth
                    ? $0.relativePath > $1.relativePath
                    : leftDepth > rightDepth
            }
        for entry in directories {
            let path = installRoot.appendingPathComponent(entry.relativePath).path
            guard policy.allowsRemoval(path), try itemExists(path) else { continue }
            let authorization = try policy.authorizeRemoval(path)
            try authorization.revalidate()
            guard Darwin.unlinkat(
                authorization.parentDescriptor,
                authorization.childName,
                AT_REMOVEDIR
            ) == 0 else {
                throw posixError()
            }
        }
    }

    private func openResolverDirectory(createIfMissing: Bool) throws -> Int32 {
        let parentURL = resolverDirectory.deletingLastPathComponent().resolvingSymlinksInPath()
        let parent = Darwin.open(parentURL.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard parent >= 0 else { throw posixError() }
        defer { Darwin.close(parent) }
        try validateDirectory(parent, owner: requiredOwner)

        let name = resolverDirectory.lastPathComponent
        var directory = Darwin.openat(parent, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        if directory < 0, errno == ENOENT, createIfMissing {
            guard Darwin.mkdirat(parent, name, 0o755) == 0 else { throw posixError() }
            guard Darwin.fsync(parent) == 0 else { throw posixError() }
            directory = Darwin.openat(parent, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        if directory < 0, errno == ENOENT, !createIfMissing {
            return -1
        }
        guard directory >= 0 else { throw posixError() }
        do {
            try validateDirectory(directory, owner: requiredOwner)
            return directory
        } catch {
            Darwin.close(directory)
            throw error
        }
    }

    @discardableResult
    private func validateExistingResolver(
        _ name: String,
        in directory: Int32,
        mustExist: Bool = false
    ) throws -> Bool {
        var status = stat()
        guard Darwin.fstatat(directory, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT, !mustExist {
                return false
            }
            throw posixError()
        }
        guard
            status.st_mode & S_IFMT == S_IFREG,
            status.st_uid == requiredOwner,
            status.st_nlink == 1,
            status.st_mode & 0o022 == 0
        else {
            throw SystemPrivilegedHostError.unsafeResolver
        }
        return true
    }

    private func validateDirectory(_ descriptor: Int32, owner: uid_t) throws {
        var status = stat()
        guard
            Darwin.fstat(descriptor, &status) == 0,
            status.st_mode & S_IFMT == S_IFDIR,
            status.st_uid == owner,
            status.st_mode & 0o022 == 0
        else {
            throw SystemPrivilegedHostError.unsafeDirectory
        }
    }

    private func itemExists(_ path: String) throws -> Bool {
        var status = stat()
        guard Darwin.lstat(path, &status) == 0 else {
            if errno == ENOENT {
                return false
            }
            throw posixError()
        }
        return true
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, baseAddress.advanced(by: offset), bytes.count - offset)
                guard count >= 0 else {
                    if errno == EINTR {
                        continue
                    }
                    throw posixError()
                }
                offset += count
            }
        }
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}

public enum SystemPrivilegedHostError: Error, Equatable, Sendable {
    case invalidCommandOutput
    case unsafeDirectory
    case unsafeResolver
}
