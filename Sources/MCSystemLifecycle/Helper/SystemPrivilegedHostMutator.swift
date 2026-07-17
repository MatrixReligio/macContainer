import Darwin
import Foundation

public struct SystemPrivilegedHostMutator: PrivilegedHostMutating {
    private let installRoot: URL
    private let resolverDirectory: URL
    private let packetFilterConfig: URL
    private let packetFilterAnchorsDirectory: URL
    private let requiredOwner: uid_t
    private let commandRunner: any FixedPrivilegedCommandRunning

    public init(
        manifest: RuntimePackageManifest,
        commandRunner: any FixedPrivilegedCommandRunning,
        installRoot: URL? = nil,
        resolverDirectory: URL = URL(fileURLWithPath: "/etc/resolver", isDirectory: true),
        packetFilterConfig: URL = URL(fileURLWithPath: "/etc/pf.conf"),
        packetFilterAnchorsDirectory: URL = URL(fileURLWithPath: "/etc/pf.anchors", isDirectory: true),
        requiredOwner: uid_t = 0
    ) {
        self.installRoot = installRoot ?? URL(fileURLWithPath: manifest.installLocation, isDirectory: true)
        self.resolverDirectory = resolverDirectory
        self.packetFilterConfig = packetFilterConfig
        self.packetFilterAnchorsDirectory = packetFilterAnchorsDirectory
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

    public func createDNSDomain(_ request: DNSDomainRequest) throws {
        let directory = try openResolverDirectory(createIfMissing: true)
        defer { Darwin.close(directory) }
        let filename = "containerization.\(request.name)"
        guard try !validateExistingResolver(filename, in: directory) else {
            throw SystemPrivilegedHostError.resolverAlreadyExists
        }
        try writeManagedFile(
            Data(Self.resolverText(for: request).utf8),
            named: filename,
            in: directory,
            replacing: false
        )

        do {
            if let redirect = request.redirectIPv4 {
                try mutatePacketFilter(domain: request.name, redirectIPv4: redirect, adding: true)
            }
            try commandRunner.run(.reloadDNS, package: nil)
        } catch {
            if let redirect = request.redirectIPv4 {
                try? mutatePacketFilter(domain: request.name, redirectIPv4: redirect, adding: false)
            }
            try? removeManagedFile(named: filename, in: directory)
            _ = try? commandRunner.run(.reloadDNS, package: nil)
            throw error
        }
    }

    public func deleteDNSDomain(name: String) throws {
        let directory = try openResolverDirectory(createIfMissing: false)
        guard directory >= 0 else { throw SystemPrivilegedHostError.resolverNotFound }
        defer { Darwin.close(directory) }
        let filename = "containerization.\(name)"
        guard let original = try readManagedFile(named: filename, in: directory) else {
            throw SystemPrivilegedHostError.resolverNotFound
        }
        let redirect = Self.redirectAddress(in: original)
        try removeManagedFile(named: filename, in: directory)

        do {
            if let redirect {
                try mutatePacketFilter(domain: name, redirectIPv4: redirect, adding: false)
            }
            try commandRunner.run(.reloadDNS, package: nil)
        } catch {
            try? writeManagedFile(Data(original.utf8), named: filename, in: directory, replacing: false)
            if let redirect {
                try? mutatePacketFilter(domain: name, redirectIPv4: redirect, adding: true)
            }
            _ = try? commandRunner.run(.reloadDNS, package: nil)
            throw error
        }
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

    private func mutatePacketFilter(domain: String, redirectIPv4: String, adding: Bool) throws {
        let configDirectory = try openTrustedDirectory(packetFilterConfig.deletingLastPathComponent())
        defer { Darwin.close(configDirectory) }
        let anchorsDirectory = try openTrustedDirectory(packetFilterAnchorsDirectory)
        defer { Darwin.close(anchorsDirectory) }
        let configName = packetFilterConfig.lastPathComponent
        let anchorName = "com.apple.container"
        guard let originalConfig = try readManagedFile(named: configName, in: configDirectory) else {
            throw SystemPrivilegedHostError.packetFilterConfigurationMissing
        }
        let originalAnchor = try readManagedFile(named: anchorName, in: anchorsDirectory)
        let anchorPath = packetFilterAnchorsDirectory.appendingPathComponent(anchorName).path
        let rule = "rdr inet from any to \(redirectIPv4) -> 127.0.0.1 # \(domain)"

        var config = originalConfig
        var anchorLines = (originalAnchor ?? "").components(separatedBy: .newlines)
        if adding {
            config = Self.addingAppleAnchor(to: config, anchorPath: anchorPath)
            if !anchorLines.contains(rule) {
                if anchorLines == [""] {
                    anchorLines = []
                }
                anchorLines.append(rule)
            }
        } else {
            anchorLines.removeAll { $0 == rule }
            if anchorLines.allSatisfy(\.isEmpty) {
                config = Self.removingAppleAnchor(from: config, anchorPath: anchorPath)
            }
        }

        do {
            try writeManagedFile(Data(config.utf8), named: configName, in: configDirectory, replacing: true)
            if anchorLines.allSatisfy(\.isEmpty) {
                try removeManagedFile(named: anchorName, in: anchorsDirectory, missingIsSuccess: true)
            } else {
                try writeManagedFile(
                    Data(anchorLines.joined(separator: "\n").utf8),
                    named: anchorName,
                    in: anchorsDirectory,
                    replacing: originalAnchor != nil
                )
            }
            try commandRunner.run(.validateSystemPacketFilter, package: nil)
            try commandRunner.run(.reloadSystemPacketFilter, package: nil)
        } catch {
            try? writeManagedFile(Data(originalConfig.utf8), named: configName, in: configDirectory, replacing: true)
            if let originalAnchor {
                try? writeManagedFile(
                    Data(originalAnchor.utf8),
                    named: anchorName,
                    in: anchorsDirectory,
                    replacing: try readManagedFile(named: anchorName, in: anchorsDirectory) != nil
                )
            } else {
                try? removeManagedFile(named: anchorName, in: anchorsDirectory, missingIsSuccess: true)
            }
            _ = try? commandRunner.run(.validateSystemPacketFilter, package: nil)
            _ = try? commandRunner.run(.reloadSystemPacketFilter, package: nil)
            throw error
        }
    }

    private static func resolverText(for request: DNSDomainRequest) -> String {
        let port = request.redirectIPv4 == nil ? "2053" : "1053"
        let options = request.redirectIPv4.map { "options localhost:\($0)" } ?? ""
        return [
            "domain \(request.name)",
            "search \(request.name)",
            "nameserver 127.0.0.1",
            "port \(port)",
            options
        ].joined(separator: "\n")
    }

    private static func redirectAddress(in resolver: String) -> String? {
        let prefix = "options localhost:"
        return resolver.components(separatedBy: .newlines).lazy.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(prefix) else { return nil }
            return String(trimmed.dropFirst(prefix.count))
        }.first
    }

    private static func addingAppleAnchor(to content: String, anchorPath: String) -> String {
        let keywords = ["scrub-anchor", "nat-anchor", "rdr-anchor", "dummynet-anchor", "anchor", "load anchor"]
        var lines = content.components(separatedBy: .newlines)
        for index in 0 ..< keywords.count - 1 {
            let required = "\(keywords[index]) \"com.apple.container\""
            guard !lines.contains(required) else { continue }
            let insertion = lines.firstIndex { line in
                keywords[index...].contains { line.hasPrefix($0) }
            } ?? max(0, lines.endIndex - 1)
            lines.insert(required, at: insertion)
        }
        let load = "load anchor \"com.apple.container\" from \"\(anchorPath)\""
        if !lines.contains(load) {
            lines.insert(load, at: max(0, lines.endIndex - 1))
        }
        return lines.joined(separator: "\n")
    }

    private static func removingAppleAnchor(from content: String, anchorPath: String) -> String {
        let exact = Set([
            "scrub-anchor \"com.apple.container\"",
            "nat-anchor \"com.apple.container\"",
            "rdr-anchor \"com.apple.container\"",
            "dummynet-anchor \"com.apple.container\"",
            "anchor \"com.apple.container\"",
            "load anchor \"com.apple.container\" from \"\(anchorPath)\""
        ])
        return content.components(separatedBy: .newlines)
            .filter { !exact.contains($0) }
            .joined(separator: "\n")
    }

    private func openTrustedDirectory(_ directory: URL) throws -> Int32 {
        let resolved = directory.resolvingSymlinksInPath()
        let descriptor = Darwin.open(resolved.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posixError() }
        do {
            try validateDirectory(descriptor, owner: requiredOwner)
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private func readManagedFile(named name: String, in directory: Int32) throws -> String? {
        guard try validateManagedFile(name, in: directory) else { return nil }
        let descriptor = Darwin.openat(directory, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posixError() }
        defer { Darwin.close(descriptor) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else {
                if errno == EINTR {
                    continue
                }
                throw posixError()
            }
            if count == 0 {
                break
            }
            guard data.count + count <= 1_048_576 else {
                throw SystemPrivilegedHostError.managedFileTooLarge
            }
            data.append(buffer, count: count)
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw SystemPrivilegedHostError.invalidManagedFile
        }
        return value
    }

    private func writeManagedFile(
        _ content: Data,
        named name: String,
        in directory: Int32,
        replacing: Bool
    ) throws {
        let exists = try validateManagedFile(name, in: directory)
        guard exists == replacing else {
            throw exists
                ? SystemPrivilegedHostError.resolverAlreadyExists
                : SystemPrivilegedHostError.managedFileMissing
        }
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
        try writeAll(content, to: descriptor)
        guard Darwin.fsync(descriptor) == 0 else { throw posixError() }
        guard Darwin.renameat(directory, temporary, directory, name) == 0 else { throw posixError() }
        temporaryExists = false
        guard Darwin.fsync(directory) == 0 else { throw posixError() }
        guard try validateManagedFile(name, in: directory) else {
            throw SystemPrivilegedHostError.managedFileMissing
        }
    }

    private func removeManagedFile(named name: String, in directory: Int32, missingIsSuccess: Bool = false) throws {
        guard try validateManagedFile(name, in: directory) else {
            if missingIsSuccess {
                return
            }
            throw SystemPrivilegedHostError.managedFileMissing
        }
        guard Darwin.unlinkat(directory, name, 0) == 0 else { throw posixError() }
        guard Darwin.fsync(directory) == 0 else { throw posixError() }
    }

    private func validateManagedFile(_ name: String, in directory: Int32) throws -> Bool {
        var status = stat()
        guard Darwin.fstatat(directory, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT {
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
            throw SystemPrivilegedHostError.invalidManagedFile
        }
        return true
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
    case invalidManagedFile
    case managedFileMissing
    case managedFileTooLarge
    case packetFilterConfigurationMissing
    case resolverAlreadyExists
    case resolverNotFound
    case unsafeDirectory
    case unsafeResolver
}
