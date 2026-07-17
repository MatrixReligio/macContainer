import Darwin
import Foundation

public struct RetainedRuntimePackage: Equatable, Sendable {
    public let url: URL
    public let runtimeVersion: String
    public let sha256: String

    public init(url: URL, runtimeVersion: String, sha256: String) {
        self.url = url.standardizedFileURL
        self.runtimeVersion = runtimeVersion
        self.sha256 = sha256
    }
}

public enum VerifiedRuntimePackageCacheError: Error, Equatable, Sendable {
    case cacheWriteFailed
    case unsafeAssetName
    case unsafeCacheRoot
    case unsafeExistingPackage
}

public actor VerifiedRuntimePackageCache: InstallPackageRetaining {
    private let rootDirectory: URL

    public init(rootDirectory: URL = VerifiedRuntimePackageCache.defaultRootDirectory) {
        self.rootDirectory = rootDirectory.standardizedFileURL
    }

    public func retain(
        _ package: VerifiedRuntimePackage,
        assetName: String
    ) async throws -> RetainedRuntimePackage {
        guard Self.isSafeAssetName(assetName) else {
            throw VerifiedRuntimePackageCacheError.unsafeAssetName
        }
        try package.openFile.revalidateIdentity()
        try ensurePrivateRoot()

        let directoryDescriptor = Darwin.open(
            rootDirectory.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard directoryDescriptor >= 0 else {
            throw VerifiedRuntimePackageCacheError.unsafeCacheRoot
        }
        defer { Darwin.close(directoryDescriptor) }

        try validateExistingPackage(named: assetName, directoryDescriptor: directoryDescriptor)
        let temporaryName = ".package-\(UUID().uuidString).tmp"
        let cloned = temporaryName.withCString { name in
            Darwin.fclonefileat(package.openFile.fileDescriptor, directoryDescriptor, name, 0)
        }
        guard cloned == 0 else {
            throw VerifiedRuntimePackageCacheError.cacheWriteFailed
        }
        var removeTemporary = true
        defer {
            if removeTemporary {
                _ = temporaryName.withCString { Darwin.unlinkat(directoryDescriptor, $0, 0) }
            }
        }

        let temporaryDescriptor = temporaryName.withCString {
            Darwin.openat(directoryDescriptor, $0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard temporaryDescriptor >= 0 else {
            throw VerifiedRuntimePackageCacheError.cacheWriteFailed
        }
        defer { Darwin.close(temporaryDescriptor) }
        guard Darwin.fchmod(temporaryDescriptor, 0o600) == 0,
              Darwin.fsync(temporaryDescriptor) == 0
        else {
            throw VerifiedRuntimePackageCacheError.cacheWriteFailed
        }
        try Self.validatePackageDescriptor(temporaryDescriptor)

        let renamed = temporaryName.withCString { temporary in
            assetName.withCString { destination in
                Darwin.renameat(directoryDescriptor, temporary, directoryDescriptor, destination)
            }
        }
        guard renamed == 0, Darwin.fsync(directoryDescriptor) == 0 else {
            throw VerifiedRuntimePackageCacheError.cacheWriteFailed
        }
        removeTemporary = false
        try validateExistingPackage(named: assetName, directoryDescriptor: directoryDescriptor)

        return RetainedRuntimePackage(
            url: rootDirectory.appendingPathComponent(assetName, isDirectory: false),
            runtimeVersion: package.runtimeVersion,
            sha256: package.sha256
        )
    }

    private func ensurePrivateRoot() throws {
        guard rootDirectory.isFileURL, rootDirectory.path.hasPrefix("/") else {
            throw VerifiedRuntimePackageCacheError.unsafeCacheRoot
        }
        let parent = rootDirectory.deletingLastPathComponent()
        try ensurePrivateDirectory(parent)
        try ensurePrivateDirectory(rootDirectory)
    }

    private func ensurePrivateDirectory(_ directory: URL) throws {
        var status = stat()
        if Darwin.lstat(directory.path, &status) != 0 {
            guard errno == ENOENT, Darwin.mkdir(directory.path, 0o700) == 0 else {
                throw VerifiedRuntimePackageCacheError.unsafeCacheRoot
            }
            guard Darwin.lstat(directory.path, &status) == 0 else {
                throw VerifiedRuntimePackageCacheError.unsafeCacheRoot
            }
        }
        guard status.st_mode & S_IFMT == S_IFDIR,
              status.st_uid == geteuid(),
              status.st_mode & 0o077 == 0
        else {
            throw VerifiedRuntimePackageCacheError.unsafeCacheRoot
        }
    }

    private func validateExistingPackage(
        named assetName: String,
        directoryDescriptor: Int32
    ) throws {
        let descriptor = assetName.withCString {
            Darwin.openat(directoryDescriptor, $0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            if errno == ENOENT { return }
            throw VerifiedRuntimePackageCacheError.unsafeExistingPackage
        }
        defer { Darwin.close(descriptor) }
        do {
            try Self.validatePackageDescriptor(descriptor)
        } catch {
            throw VerifiedRuntimePackageCacheError.unsafeExistingPackage
        }
    }

    private static func validatePackageDescriptor(_ descriptor: Int32) throws {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG,
              status.st_uid == geteuid(),
              status.st_nlink == 1,
              status.st_mode & 0o077 == 0,
              status.st_size > 0
        else {
            throw VerifiedRuntimePackageCacheError.cacheWriteFailed
        }
    }

    private static func isSafeAssetName(_ value: String) -> Bool {
        guard (1 ... 128).contains(value.utf8.count),
              value == URL(fileURLWithPath: value).lastPathComponent,
              value.hasSuffix("-installer-signed.pkg"),
              !value.contains("..")
        else {
            return false
        }
        return value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0))
        }
    }

    public static var defaultRootDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("container.matrixreligio.com", isDirectory: true)
            .appendingPathComponent("RuntimePackages", isDirectory: true)
    }
}
