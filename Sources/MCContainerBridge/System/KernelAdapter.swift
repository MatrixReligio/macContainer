import ContainerAPIClient
import Containerization
import ContainerizationArchive
import CryptoKit
import Foundation
import MCModel

public struct KernelArchiveDescriptor: Equatable, Sendable {
    public let url: URL
    public let binaryPath: String
    public let expectedSHA256: String
    public let allowedHosts: Set<String>

    public init(
        url: URL,
        binaryPath: String,
        expectedSHA256: String,
        allowedHosts: Set<String>
    ) {
        self.url = url
        self.binaryPath = binaryPath
        self.expectedSHA256 = expectedSHA256
        self.allowedHosts = allowedHosts
    }

    public static func pinnedKata328(platform: String) -> Self {
        // Apple container 1.1.0 defaults to Kata 3.28.0. These release-asset
        // digests are intentionally part of the versioned compatibility contract.
        let architecture = platform.split(separator: "/").last.map(String.init) ?? platform
        let asset: String
        let digest: String
        switch architecture {
        case "amd64":
            asset = "kata-static-3.28.0-amd64.tar.zst"
            digest = "99cefb46d70bc27b7bcffd7595be9010c6bed43e1cdfcf8078554c19e7c9b19d"
        default:
            asset = "kata-static-3.28.0-arm64.tar.zst"
            digest = "f63d54507d1f18635d94475077e4c2330de4d8e05cedf25f7c38f063b0e66a91"
        }
        return Self(
            url: URL(string: "https://github.com/kata-containers/kata-containers/releases/download/3.28.0/\(asset)")!,
            binaryPath: "opt/kata/share/kata-containers/vmlinux-6.18.15-186",
            expectedSHA256: digest,
            allowedHosts: ["github.com", "release-assets.githubusercontent.com"]
        )
    }
}

public protocol KernelBackend: Sendable {
    func recommended(platform: String) async throws -> KernelArchiveDescriptor
    func installBinary(url: URL, platform: String, force: Bool) async throws -> KernelSummary
    func installArchive(url: URL, binaryPath: String, platform: String, force: Bool) async throws -> KernelSummary
}

public protocol KernelDownloading: Sendable {
    func download(from source: URL, to destination: URL, allowedHosts: Set<String>) async throws
}

public protocol KernelArchiveValidating: Sendable {
    func validate(archive: URL, binaryPath: String) async throws
}

public enum KernelAdapterError: Error, Equatable, Sendable {
    case invalidPlatform(String)
    case invalidLocalFile
    case invalidRemoteURL
    case invalidDigest
    case hostNotAllowed(String)
    case digestMismatch
    case archiveTraversal
    case kernelMissingFromArchive(String)
    case unsafeKernelSymlink
    case invalidKernelEntry
    case downloadTooLarge
}

public struct KernelAdapter: KernelOperations, Sendable {
    private let backend: any KernelBackend
    private let downloader: any KernelDownloading
    private let archiveValidator: any KernelArchiveValidating
    private let coordinator: OperationCoordinator
    private let temporaryRoot: URL

    public init(
        backend: any KernelBackend = AppleKernelBackend(),
        downloader: any KernelDownloading = URLSessionKernelDownloader(),
        archiveValidator: any KernelArchiveValidating = AppleKernelArchiveValidator(),
        coordinator: OperationCoordinator = OperationCoordinator(),
        temporaryRoot: URL = FileManager.default.temporaryDirectory
            .appending(path: "container.matrixreligio.com/kernel-downloads", directoryHint: .isDirectory)
    ) {
        self.backend = backend
        self.downloader = downloader
        self.archiveValidator = archiveValidator
        self.coordinator = coordinator
        self.temporaryRoot = temporaryRoot
    }

    public func setRecommended(platform: String, force: Bool) async throws -> KernelSummary {
        let platform = try Self.normalizedPlatform(platform)
        let descriptor = try await backend.recommended(platform: platform)
        return try await installVerified(descriptor, platform: platform, force: force)
    }

    public func setLocalBinary(_ url: URL, platform: String, force: Bool) async throws -> KernelSummary {
        let platform = try Self.normalizedPlatform(platform)
        let file = try Self.validatedLocalFile(url)
        return try await coordinator.withLock(.systemService) {
            try await backend.installBinary(url: file, platform: platform, force: force)
        }
    }

    public func setLocalArchive(_ url: URL, platform: String, force: Bool) async throws -> KernelSummary {
        let platform = try Self.normalizedPlatform(platform)
        let file = try Self.validatedLocalFile(url)
        let descriptor = try await backend.recommended(platform: platform)
        try await archiveValidator.validate(archive: file, binaryPath: descriptor.binaryPath)
        return try await coordinator.withLock(.systemService) {
            try await backend.installArchive(
                url: file,
                binaryPath: descriptor.binaryPath,
                platform: platform,
                force: force
            )
        }
    }

    public func setVerifiedRemoteArchive(
        _ request: VerifiedKernelArchiveRequest
    ) async throws -> KernelSummary {
        let platform = try Self.normalizedPlatform(request.platform)
        let allowedHosts = Set(request.allowedHosts.map { $0.lowercased() })
        _ = try Self.validateRemote(
            url: request.url,
            expectedSHA256: request.expectedSHA256,
            allowedHosts: allowedHosts
        )
        let descriptor = try await backend.recommended(platform: platform)
        let supplied = KernelArchiveDescriptor(
            url: request.url,
            binaryPath: descriptor.binaryPath,
            expectedSHA256: request.expectedSHA256,
            allowedHosts: allowedHosts
        )
        return try await installVerified(supplied, platform: platform, force: request.force)
    }

    private func installVerified(
        _ descriptor: KernelArchiveDescriptor,
        platform: String,
        force: Bool
    ) async throws -> KernelSummary {
        let digest = try Self.validateRemote(
            url: descriptor.url,
            expectedSHA256: descriptor.expectedSHA256,
            allowedHosts: descriptor.allowedHosts
        )
        try Self.validateArchiveMemberPath(descriptor.binaryPath)

        let rootExisted = FileManager.default.fileExists(atPath: temporaryRoot.path)
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let workspace = temporaryRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: workspace)
            if !rootExisted {
                try? FileManager.default.removeItem(at: temporaryRoot)
            }
        }
        let archive = workspace.appending(path: "kernel.archive")
        try await downloader.download(
            from: descriptor.url,
            to: archive,
            allowedHosts: descriptor.allowedHosts
        )
        guard try Self.sha256(of: archive) == digest else {
            throw KernelAdapterError.digestMismatch
        }
        try await archiveValidator.validate(archive: archive, binaryPath: descriptor.binaryPath)
        return try await coordinator.withLock(.systemService) {
            try await backend.installArchive(
                url: archive,
                binaryPath: descriptor.binaryPath,
                platform: platform,
                force: force
            )
        }
    }

    static func normalizedPlatform(_ value: String) throws -> String {
        switch value.lowercased() {
        case "arm64", "linux/arm64": "linux/arm64"
        case "amd64", "linux/amd64": "linux/amd64"
        default: throw KernelAdapterError.invalidPlatform(value)
        }
    }

    static func validatedLocalFile(_ url: URL) throws -> URL {
        guard url.isFileURL, !url.path.contains("\0") else {
            throw KernelAdapterError.invalidLocalFile
        }
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: canonical.path),
              let values = try? canonical.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize,
              size > 0
        else {
            throw KernelAdapterError.invalidLocalFile
        }
        return canonical
    }

    static func validateArchiveMemberPath(_ value: String) throws {
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.contains("\0"),
              !value.split(separator: "/", omittingEmptySubsequences: false).contains("..")
        else {
            throw KernelAdapterError.archiveTraversal
        }
    }

    private static func validateRemote(
        url: URL,
        expectedSHA256: String,
        allowedHosts: Set<String>
    ) throws -> String {
        let digest = expectedSHA256.lowercased()
        guard digest.count == 64,
              digest.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdef").contains($0) })
        else {
            throw KernelAdapterError.invalidDigest
        }
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty
        else {
            throw KernelAdapterError.invalidRemoteURL
        }
        guard allowedHosts.contains(host) else {
            throw KernelAdapterError.hostNotAllowed(host)
        }
        return digest
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
            guard !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public struct AppleKernelBackend: KernelBackend, Sendable {
    public init() {}

    public func recommended(platform: String) async throws -> KernelArchiveDescriptor {
        .pinnedKata328(platform: platform)
    }

    public func installBinary(url: URL, platform: String, force: Bool) async throws -> KernelSummary {
        let systemPlatform = try Self.systemPlatform(platform)
        try await ClientKernel.installKernel(
            kernelFilePath: url.absoluteString,
            platform: systemPlatform,
            force: force
        )
        return try await Self.summary(systemPlatform)
    }

    public func installArchive(
        url: URL,
        binaryPath: String,
        platform: String,
        force: Bool
    ) async throws -> KernelSummary {
        let systemPlatform = try Self.systemPlatform(platform)
        try await ClientKernel.installKernelFromTar(
            tarFile: url.path,
            kernelFilePath: binaryPath,
            platform: systemPlatform,
            force: force
        )
        return try await Self.summary(systemPlatform)
    }

    private static func systemPlatform(_ value: String) throws -> SystemPlatform {
        switch value {
        case "linux/arm64": .linuxArm
        case "linux/amd64": .linuxAmd
        default: throw KernelAdapterError.invalidPlatform(value)
        }
    }

    private static func summary(_ platform: SystemPlatform) async throws -> KernelSummary {
        let kernel = try await ClientKernel.getDefaultKernel(for: platform)
        return KernelSummary(
            identifier: kernel.path.path,
            platform: "\(kernel.platform.os.rawValue)/\(kernel.platform.architecture.rawValue)"
        )
    }
}

public struct AppleKernelArchiveValidator: KernelArchiveValidating, Sendable {
    public init() {}

    public func validate(archive: URL, binaryPath: String) async throws {
        try KernelAdapter.validateArchiveMemberPath(binaryPath)
        let reader = try ArchiveReader(file: archive)
        var iterator = reader.makeStreamingIterator()
        var entries = Set<String>()
        var symlinks: [String: String] = [:]
        var types: [String: URLFileResourceType] = [:]
        var sizes: [String: Int64] = [:]
        var hardlinks = Set<String>()
        while let (entry, _) = iterator.next() {
            try Task.checkCancellation()
            guard let rawPath = entry.path else { continue }
            if rawPath == "." || rawPath == "./" {
                try Self.validateRootDirectoryMarker(fileType: entry.fileType)
                continue
            }
            let path = try Self.normalizedMember(rawPath)
            entries.insert(path)
            if types[path] == nil {
                types[path] = entry.fileType
                sizes[path] = entry.size ?? 0
                if entry.fileType == .symbolicLink, let target = entry.symlinkTarget {
                    symlinks[path] = target
                }
                if entry.hardlink != nil {
                    hardlinks.insert(path)
                }
            }
        }

        let target = try Self.normalizedMember(binaryPath)
        guard entries.contains(target) else {
            throw KernelAdapterError.kernelMissingFromArchive(binaryPath)
        }
        if let symlink = symlinks[target] {
            let parent = target.split(separator: "/").dropLast().map(String.init)
            let resolved = try Self.resolve(parent: parent, target: symlink)
            guard entries.contains(resolved),
                  types[resolved] == .regular,
                  (sizes[resolved] ?? 0) > 0,
                  !hardlinks.contains(resolved)
            else {
                throw KernelAdapterError.unsafeKernelSymlink
            }
        } else if types[target] != .regular || (sizes[target] ?? 0) <= 0 || hardlinks.contains(target) {
            throw KernelAdapterError.invalidKernelEntry
        }
    }

    private static func validateRootDirectoryMarker(fileType: URLFileResourceType) throws {
        guard fileType == .directory else {
            throw KernelAdapterError.archiveTraversal
        }
    }

    private static func normalizedMember(_ value: String) throws -> String {
        guard !value.hasPrefix("/"), !value.contains("\0") else {
            throw KernelAdapterError.archiveTraversal
        }
        var components: [String] = []
        for component in value.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".": continue
            case "..": throw KernelAdapterError.archiveTraversal
            default: components.append(String(component))
            }
        }
        guard !components.isEmpty else {
            throw KernelAdapterError.archiveTraversal
        }
        return components.joined(separator: "/")
    }

    private static func resolve(parent: [String], target: String) throws -> String {
        guard !target.hasPrefix("/") else {
            throw KernelAdapterError.unsafeKernelSymlink
        }
        var result = parent
        for component in target.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".": continue
            case "..":
                guard !result.isEmpty else {
                    throw KernelAdapterError.unsafeKernelSymlink
                }
                result.removeLast()
            default: result.append(String(component))
            }
        }
        guard !result.isEmpty else {
            throw KernelAdapterError.unsafeKernelSymlink
        }
        return result.joined(separator: "/")
    }
}

public struct URLSessionKernelDownloader: KernelDownloading, Sendable {
    private let maximumBytes: Int64

    public init(maximumBytes: Int64 = 4 * 1024 * 1024 * 1024) {
        self.maximumBytes = maximumBytes
    }

    public func download(from source: URL, to destination: URL, allowedHosts: Set<String>) async throws {
        let guardDelegate = RedirectGuard(allowedHosts: allowedHosts, maximumBytes: maximumBytes)
        let session = URLSession(configuration: .ephemeral, delegate: guardDelegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let temporary: URL
        let response: URLResponse
        do {
            (temporary, response) = try await session.download(from: source)
        } catch {
            if guardDelegate.exceededLimit {
                throw KernelAdapterError.downloadTooLarge
            }
            throw error
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        if let violation = guardDelegate.violation {
            throw KernelAdapterError.hostNotAllowed(violation)
        }
        guard let response = response as? HTTPURLResponse,
              (200 ..< 300).contains(response.statusCode),
              let finalHost = response.url?.host?.lowercased(),
              allowedHosts.contains(finalHost),
              response.url?.scheme?.lowercased() == "https"
        else {
            throw KernelAdapterError.invalidRemoteURL
        }
        let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, Int64(size) <= maximumBytes else {
            throw KernelAdapterError.downloadTooLarge
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}

private final class RedirectGuard: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
    private let allowedHosts: Set<String>
    private let maximumBytes: Int64
    private let lock = NSLock()
    private var storedViolation: String?
    private var storedExceededLimit = false

    var violation: String? {
        lock.withLock { storedViolation }
    }

    var exceededLimit: Bool {
        lock.withLock { storedExceededLimit }
    }

    init(allowedHosts: Set<String>, maximumBytes: Int64) {
        self.allowedHosts = allowedHosts
        self.maximumBytes = maximumBytes
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        let host = request.url?.host?.lowercased() ?? ""
        guard request.url?.scheme?.lowercased() == "https", allowedHosts.contains(host) else {
            lock.withLock { storedViolation = host }
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesWritten > maximumBytes
            || (totalBytesExpectedToWrite > 0 && totalBytesExpectedToWrite > maximumBytes)
        else { return }
        lock.withLock { storedExceededLimit = true }
        downloadTask.cancel()
    }

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didFinishDownloadingTo _: URL
    ) {}
}
