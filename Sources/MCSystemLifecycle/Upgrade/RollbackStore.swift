import Darwin
import Foundation

public enum RollbackItemKind: String, Codable, Equatable, Sendable {
    case previousPackage
    case configurationAndMetadata
    case fullData
}

public enum RollbackItemState: String, Codable, Equatable, Sendable {
    case planned
    case created
}

public struct RollbackItem: Codable, Equatable, Sendable {
    public let kind: RollbackItemKind
    public let sourcePath: String
    public let backupName: String
    public let logicalBytes: UInt64
    public var state: RollbackItemState

    public init(
        kind: RollbackItemKind,
        sourcePath: String,
        backupName: String,
        logicalBytes: UInt64,
        state: RollbackItemState
    ) {
        self.kind = kind
        self.sourcePath = sourcePath
        self.backupName = backupName
        self.logicalBytes = logicalBytes
        self.state = state
    }
}

public struct RollbackPointManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let pointID: UUID
    public let previousManifest: RuntimePackageManifest
    public let requiresFullData: Bool
    public var items: [RollbackItem]

    public init(
        schemaVersion: Int = 1,
        pointID: UUID,
        previousManifest: RuntimePackageManifest,
        requiresFullData: Bool,
        items: [RollbackItem]
    ) {
        self.schemaVersion = schemaVersion
        self.pointID = pointID
        self.previousManifest = previousManifest
        self.requiresFullData = requiresFullData
        self.items = items
    }
}

public struct RollbackDirectoryIdentity: Equatable, Sendable {
    public let device: dev_t
    public let inode: ino_t
    public let owner: uid_t

    public init(device: dev_t, inode: ino_t, owner: uid_t) {
        self.device = device
        self.inode = inode
        self.owner = owner
    }
}

public struct RollbackPoint: Equatable, Sendable {
    public let id: UUID
    public let rootURL: URL
    public let manifestURL: URL
    public let previousPackageURL: URL
    public let manifest: RollbackPointManifest
    public let identity: RollbackDirectoryIdentity

    public init(
        id: UUID,
        rootURL: URL,
        manifestURL: URL,
        previousPackageURL: URL,
        manifest: RollbackPointManifest,
        identity: RollbackDirectoryIdentity
    ) {
        self.id = id
        self.rootURL = rootURL
        self.manifestURL = manifestURL
        self.previousPackageURL = previousPackageURL
        self.manifest = manifest
        self.identity = identity
    }
}

public struct RollbackCaptureRequest: Equatable, Sendable {
    public let previousPackageURL: URL
    public let previousManifest: RuntimePackageManifest
    public let configurationAndMetadata: [URL]
    public let fullData: [URL]
    public let requiresFullData: Bool

    public init(
        previousPackageURL: URL,
        previousManifest: RuntimePackageManifest,
        configurationAndMetadata: [URL],
        fullData: [URL],
        requiresFullData: Bool
    ) {
        self.previousPackageURL = previousPackageURL.standardizedFileURL
        self.previousManifest = previousManifest
        self.configurationAndMetadata = configurationAndMetadata.map(\.standardizedFileURL)
        self.fullData = fullData.map(\.standardizedFileURL)
        self.requiresFullData = requiresFullData
    }
}

public protocol RollbackStoreFileSystem: Sendable {
    func logicalSize(of url: URL) throws -> UInt64
    func availableCapacity(at url: URL) throws -> UInt64
    func createPrivateDirectory(at url: URL) throws
    func createManifest(_ data: Data, at url: URL) throws
    func replaceManifest(_ data: Data, at url: URL) throws
    func readManifest(at url: URL) throws -> Data
    func clonePackage(from package: OpenRuntimePackageFile, to destination: URL) throws
    func cloneItem(from source: URL, to destination: URL) throws
    func restoreItem(from source: URL, to destination: URL) throws
    func removePoint(at url: URL, identity: RollbackDirectoryIdentity) throws
    func directoryIdentity(at url: URL) throws -> RollbackDirectoryIdentity
}

public enum RollbackStoreError: Error, Equatable, Sendable {
    case duplicateSource
    case insufficientSpace(required: UInt64, available: UInt64)
    case invalidPreviousPackage
    case invalidRequest
    case unsafeFileSystemItem
    case unsafePoint
}

public actor RollbackStore {
    private let rootDirectory: URL
    private let fileSystem: any RollbackStoreFileSystem
    private let packageVerifier: any InstallRuntimePackageVerifying
    var upgradePoints: [UUID: RollbackPoint] = [:]

    public init(
        rootDirectory: URL = RollbackStore.defaultRootDirectory,
        fileSystem: any RollbackStoreFileSystem = LocalRollbackStoreFileSystem(),
        packageVerifier: any InstallRuntimePackageVerifying
    ) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.fileSystem = fileSystem
        self.packageVerifier = packageVerifier
    }

    public func createPoint(
        _ request: RollbackCaptureRequest,
        verifiedPrevious: VerifiedRuntimePackage
    ) async throws -> RollbackPoint {
        try validate(request, verifiedPrevious: verifiedPrevious)
        let plannedItems = try makePlannedItems(request)
        let logicalBytes = try sumLogicalBytes(plannedItems)
        let requiredBytes = try addingHeadroom(to: logicalBytes)
        let availableBytes = try fileSystem.availableCapacity(at: rootDirectory)
        guard availableBytes >= requiredBytes else {
            throw RollbackStoreError.insufficientSpace(
                required: requiredBytes,
                available: availableBytes
            )
        }

        let pointID = UUID()
        let pointRoot = rootDirectory.appendingPathComponent(pointID.uuidString, isDirectory: true)
        let manifestURL = pointRoot.appendingPathComponent("manifest.json")
        var manifest = RollbackPointManifest(
            pointID: pointID,
            previousManifest: request.previousManifest,
            requiresFullData: request.requiresFullData,
            items: plannedItems
        )
        do {
            try fileSystem.createPrivateDirectory(at: pointRoot)
            let identity = try fileSystem.directoryIdentity(at: pointRoot)
            try fileSystem.createManifest(encode(manifest), at: manifestURL)
            for index in manifest.items.indices {
                let item = manifest.items[index]
                let destination = pointRoot.appendingPathComponent(item.backupName)
                if item.kind == .previousPackage {
                    try fileSystem.clonePackage(from: verifiedPrevious.openFile, to: destination)
                } else {
                    try fileSystem.cloneItem(
                        from: URL(fileURLWithPath: item.sourcePath),
                        to: destination
                    )
                }
                manifest.items[index].state = .created
                try fileSystem.replaceManifest(encode(manifest), at: manifestURL)
            }
            guard let packageItem = manifest.items.first(where: { $0.kind == .previousPackage }) else {
                throw RollbackStoreError.invalidRequest
            }
            return RollbackPoint(
                id: pointID,
                rootURL: pointRoot,
                manifestURL: manifestURL,
                previousPackageURL: pointRoot.appendingPathComponent(packageItem.backupName),
                manifest: manifest,
                identity: identity
            )
        } catch {
            if let identity = try? fileSystem.directoryIdentity(at: pointRoot) {
                try? fileSystem.removePoint(at: pointRoot, identity: identity)
            }
            throw error
        }
    }

    public func openPreviousPackage(in point: RollbackPoint) async throws -> VerifiedRuntimePackage {
        try await packageVerifier.verify(
            packageAt: point.previousPackageURL,
            against: point.manifest.previousManifest
        )
    }

    public func loadPoint(id: UUID) throws -> RollbackPoint {
        do {
            _ = try fileSystem.directoryIdentity(at: rootDirectory)
            let pointRoot = rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
            let identity = try fileSystem.directoryIdentity(at: pointRoot)
            let manifestURL = pointRoot.appendingPathComponent("manifest.json")
            let manifest = try JSONDecoder().decode(
                RollbackPointManifest.self,
                from: fileSystem.readManifest(at: manifestURL)
            )
            try validateReopenedManifest(manifest, expectedID: id, pointRoot: pointRoot)
            guard let packageItem = manifest.items.first(where: { $0.kind == .previousPackage }) else {
                throw RollbackStoreError.unsafePoint
            }
            let point = RollbackPoint(
                id: id,
                rootURL: pointRoot,
                manifestURL: manifestURL,
                previousPackageURL: pointRoot.appendingPathComponent(packageItem.backupName),
                manifest: manifest,
                identity: identity
            )
            upgradePoints[id] = point
            return point
        } catch {
            throw RollbackStoreError.unsafePoint
        }
    }

    public func restore(_ point: RollbackPoint) throws {
        for item in point.manifest.items where item.kind != .previousPackage {
            guard item.state == .created else { throw RollbackStoreError.unsafePoint }
            try fileSystem.restoreItem(
                from: point.rootURL.appendingPathComponent(item.backupName),
                to: URL(fileURLWithPath: item.sourcePath)
            )
        }
    }

    public func discard(_ point: RollbackPoint) throws {
        try fileSystem.removePoint(at: point.rootURL, identity: point.identity)
    }

    private func validate(
        _ request: RollbackCaptureRequest,
        verifiedPrevious: VerifiedRuntimePackage
    ) throws {
        do {
            try request.previousManifest.validate()
            try verifiedPrevious.openFile.revalidateIdentity()
        } catch {
            throw RollbackStoreError.invalidPreviousPackage
        }
        let manifest = request.previousManifest
        guard
            verifiedPrevious.runtimeVersion == manifest.runtimeVersion,
            verifiedPrevious.sha256 == manifest.sha256,
            verifiedPrevious.installerTeamID == manifest.installerTeamID,
            verifiedPrevious.signerCommonName == manifest.signerCommonName,
            verifiedPrevious.receiptIdentifier == manifest.receiptIdentifier,
            verifiedPrevious.installLocation == manifest.installLocation,
            verifiedPrevious.payload == manifest.payload,
            request.previousPackageURL.isFileURL,
            !request.configurationAndMetadata.isEmpty,
            !request.requiresFullData || !request.fullData.isEmpty
        else {
            throw RollbackStoreError.invalidPreviousPackage
        }
        let sources = [request.previousPackageURL] + request.configurationAndMetadata +
            (request.requiresFullData ? request.fullData : [])
        guard sources.allSatisfy(\.isFileURL), Set(sources.map(\.path)).count == sources.count else {
            throw RollbackStoreError.duplicateSource
        }
    }

    private func validateReopenedManifest(
        _ manifest: RollbackPointManifest,
        expectedID: UUID,
        pointRoot: URL
    ) throws {
        try manifest.previousManifest.validate()
        guard
            manifest.schemaVersion == 1,
            manifest.pointID == expectedID,
            !manifest.items.isEmpty,
            manifest.items.allSatisfy({ $0.state == .created }),
            manifest.items.filter({ $0.kind == .previousPackage }).count == 1,
            !manifest.requiresFullData || manifest.items.contains(where: { $0.kind == .fullData }),
            Set(manifest.items.map(\.backupName)).count == manifest.items.count,
            Set(manifest.items.map(\.sourcePath)).count == manifest.items.count
        else {
            throw RollbackStoreError.unsafePoint
        }
        for item in manifest.items {
            guard
                Self.isSafeBackupName(item.backupName),
                item.sourcePath.hasPrefix("/"),
                try fileSystem.logicalSize(
                    of: pointRoot.appendingPathComponent(item.backupName)
                ) == item.logicalBytes
            else {
                throw RollbackStoreError.unsafePoint
            }
        }
    }

    private func makePlannedItems(_ request: RollbackCaptureRequest) throws -> [RollbackItem] {
        var sources: [(RollbackItemKind, URL)] = [(.previousPackage, request.previousPackageURL)]
        sources += request.configurationAndMetadata.map { (.configurationAndMetadata, $0) }
        if request.requiresFullData {
            sources += request.fullData.map { (.fullData, $0) }
        }
        return try sources.enumerated().map { index, entry in
            let safeName = Self.safeBackupName(entry.1.lastPathComponent)
            return try RollbackItem(
                kind: entry.0,
                sourcePath: entry.1.path,
                backupName: String(format: "%02d-%@", index, safeName),
                logicalBytes: fileSystem.logicalSize(of: entry.1),
                state: .planned
            )
        }
    }

    private func sumLogicalBytes(_ items: [RollbackItem]) throws -> UInt64 {
        try items.reduce(0) { partial, item in
            let (sum, overflow) = partial.addingReportingOverflow(item.logicalBytes)
            guard !overflow else { throw RollbackStoreError.invalidRequest }
            return sum
        }
    }

    private func addingHeadroom(to value: UInt64) throws -> UInt64 {
        let (adjusted, adjustmentOverflow) = value.addingReportingOverflow(4)
        guard !adjustmentOverflow else { throw RollbackStoreError.invalidRequest }
        let headroom = adjusted / 5
        let (required, requiredOverflow) = value.addingReportingOverflow(headroom)
        guard !requiredOverflow else { throw RollbackStoreError.invalidRequest }
        return required
    }

    private func encode(_ manifest: RollbackPointManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }

    private static func safeBackupName(_ value: String) -> String {
        let filtered = value.filter { $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }
        return filtered.isEmpty ? "item" : String(filtered.prefix(96))
    }

    private static func isSafeBackupName(_ value: String) -> Bool {
        guard (1 ... 128).contains(value.utf8.count), value == URL(fileURLWithPath: value).lastPathComponent else {
            return false
        }
        return !value.contains("..") && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0))
        }
    }

    public static var defaultRootDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("container.matrixreligio.com", isDirectory: true)
            .appendingPathComponent("Rollback", isDirectory: true)
    }
}

extension RollbackStore: RecoveryRollbackPointVerifying {
    public func verifiedPointIDs(_ recordedPointIDs: Set<UUID>) async -> Set<UUID> {
        var verified: Set<UUID> = []
        for pointID in recordedPointIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            do {
                let point = try loadPoint(id: pointID)
                _ = try await openPreviousPackage(in: point)
                verified.insert(pointID)
            } catch {}
        }
        return verified
    }
}

public struct LocalRollbackStoreFileSystem: RollbackStoreFileSystem {
    public init() {}

    public func logicalSize(of url: URL) throws -> UInt64 {
        try validateTree(at: url)
        return try accumulatedSize(at: url)
    }

    public func availableCapacity(at url: URL) throws -> UInt64 {
        let existing = nearestExistingAncestor(of: url)
        let values = try existing.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let capacity = values.volumeAvailableCapacityForImportantUsage, capacity >= 0 else {
            throw RollbackStoreError.unsafeFileSystemItem
        }
        return UInt64(capacity)
    }

    public func createPrivateDirectory(at url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
        guard Darwin.mkdir(url.path, 0o700) == 0 else { throw posixError() }
        var status = stat()
        guard
            Darwin.lstat(url.path, &status) == 0,
            status.st_mode & S_IFMT == S_IFDIR,
            status.st_uid == geteuid(),
            status.st_mode & 0o077 == 0
        else {
            throw RollbackStoreError.unsafePoint
        }
    }

    public func createManifest(_ data: Data, at url: URL) throws {
        try writeExclusive(data, to: url)
    }

    public func replaceManifest(_ data: Data, at url: URL) throws {
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".manifest-\(UUID().uuidString).tmp")
        do {
            try writeExclusive(data, to: temporary)
            guard Darwin.rename(temporary.path, url.path) == 0 else { throw posixError() }
            try synchronizeDirectory(url.deletingLastPathComponent())
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    public func readManifest(at url: URL) throws -> Data {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posixError() }
        defer { Darwin.close(descriptor) }
        var status = stat()
        guard
            Darwin.fstat(descriptor, &status) == 0,
            status.st_mode & S_IFMT == S_IFREG,
            status.st_uid == geteuid(),
            status.st_nlink == 1,
            status.st_mode & 0o077 == 0,
            status.st_size <= 1024 * 1024
        else {
            throw RollbackStoreError.unsafePoint
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else {
                if errno == EINTR {
                    continue
                }
                throw posixError()
            }
            guard count > 0 else { break }
            guard data.count + count <= 1024 * 1024 else {
                throw RollbackStoreError.unsafePoint
            }
            data.append(buffer, count: count)
        }
        return data
    }

    public func clonePackage(from package: OpenRuntimePackageFile, to destination: URL) throws {
        try package.revalidateIdentity()
        let parent = destination.deletingLastPathComponent()
        let parentDescriptor = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard parentDescriptor >= 0 else { throw posixError() }
        defer { Darwin.close(parentDescriptor) }
        let result = destination.lastPathComponent.withCString { name in
            Darwin.fclonefileat(package.fileDescriptor, parentDescriptor, name, 0)
        }
        guard result == 0 else { throw posixError() }
        try setPrivatePermissions(destination)
    }

    public func cloneItem(from source: URL, to destination: URL) throws {
        try validateTree(at: source)
        guard Darwin.clonefile(source.path, destination.path, UInt32(CLONE_NOFOLLOW)) == 0 else {
            throw posixError()
        }
        try applyPrivatePermissionsRecursively(destination)
    }

    public func restoreItem(from source: URL, to destination: URL) throws {
        try validateTree(at: source)
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let replacement = parent.appendingPathComponent(".rollback-restore-\(UUID().uuidString)")
        guard Darwin.clonefile(source.path, replacement.path, UInt32(CLONE_NOFOLLOW)) == 0 else {
            throw posixError()
        }
        let displaced = parent.appendingPathComponent(".rollback-displaced-\(UUID().uuidString)")
        let existed = Darwin.rename(destination.path, displaced.path) == 0
        if !existed, errno != ENOENT {
            try? FileManager.default.removeItem(at: replacement)
            throw posixError()
        }
        guard Darwin.rename(replacement.path, destination.path) == 0 else {
            if existed {
                _ = Darwin.rename(displaced.path, destination.path)
            }
            try? FileManager.default.removeItem(at: replacement)
            throw posixError()
        }
        if existed {
            try FileManager.default.removeItem(at: displaced)
        }
        try synchronizeDirectory(parent)
    }

    public func removePoint(at url: URL, identity: RollbackDirectoryIdentity) throws {
        guard try directoryIdentity(at: url) == identity else {
            throw RollbackStoreError.unsafePoint
        }
        try FileManager.default.removeItem(at: url)
        var status = stat()
        guard Darwin.lstat(url.path, &status) != 0, errno == ENOENT else {
            throw RollbackStoreError.unsafePoint
        }
    }

    public func directoryIdentity(at url: URL) throws -> RollbackDirectoryIdentity {
        var status = stat()
        guard
            Darwin.lstat(url.path, &status) == 0,
            status.st_mode & S_IFMT == S_IFDIR,
            status.st_uid == geteuid(),
            status.st_mode & 0o077 == 0
        else {
            throw RollbackStoreError.unsafePoint
        }
        return .init(device: status.st_dev, inode: status.st_ino, owner: status.st_uid)
    }

    private func accumulatedSize(at url: URL) throws -> UInt64 {
        var status = stat()
        guard Darwin.lstat(url.path, &status) == 0 else { throw posixError() }
        if status.st_mode & S_IFMT == S_IFREG {
            return UInt64(status.st_size)
        }
        guard status.st_mode & S_IFMT == S_IFDIR else {
            throw RollbackStoreError.unsafeFileSystemItem
        }
        return try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        ).reduce(0) { try $0 + accumulatedSize(at: $1) }
    }

    private func validateTree(at url: URL) throws {
        var status = stat()
        guard Darwin.lstat(url.path, &status) == 0, status.st_uid == geteuid() else {
            throw RollbackStoreError.unsafeFileSystemItem
        }
        let kind = status.st_mode & S_IFMT
        guard kind == S_IFREG || kind == S_IFDIR else {
            throw RollbackStoreError.unsafeFileSystemItem
        }
        if kind == S_IFREG {
            guard status.st_nlink == 1, status.st_mode & 0o022 == 0 else {
                throw RollbackStoreError.unsafeFileSystemItem
            }
            return
        }
        for child in try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            try validateTree(at: child)
        }
    }

    private func writeExclusive(_ data: Data, to url: URL) throws {
        let descriptor = Darwin.open(
            url.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            0o600
        )
        guard descriptor >= 0 else { throw posixError() }
        defer { Darwin.close(descriptor) }
        var status = stat()
        guard
            Darwin.fstat(descriptor, &status) == 0,
            status.st_mode & S_IFMT == S_IFREG,
            status.st_uid == geteuid(),
            status.st_nlink == 1,
            status.st_mode & 0o077 == 0
        else {
            throw RollbackStoreError.unsafePoint
        }
        try writeAll(data, descriptor: descriptor)
        guard Darwin.fsync(descriptor) == 0 else { throw posixError() }
        try synchronizeDirectory(url.deletingLastPathComponent())
    }

    private func writeAll(_ data: Data, descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset
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
    }

    private func applyPrivatePermissionsRecursively(_ url: URL) throws {
        try setPrivatePermissions(url)
        var status = stat()
        guard Darwin.lstat(url.path, &status) == 0 else { throw posixError() }
        guard status.st_mode & S_IFMT == S_IFDIR else { return }
        for child in try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            try applyPrivatePermissionsRecursively(child)
        }
    }

    private func setPrivatePermissions(_ url: URL) throws {
        var status = stat()
        guard Darwin.lstat(url.path, &status) == 0 else { throw posixError() }
        let permissions: mode_t = status.st_mode & S_IFMT == S_IFDIR ? 0o700 : 0o600
        guard Darwin.chmod(url.path, permissions) == 0 else { throw posixError() }
    }

    private func nearestExistingAncestor(of url: URL) -> URL {
        var candidate = url
        var status = stat()
        while Darwin.lstat(candidate.path, &status) != 0, candidate.path != "/" {
            candidate.deleteLastPathComponent()
        }
        return candidate
    }

    private func synchronizeDirectory(_ url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posixError() }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw posixError() }
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
