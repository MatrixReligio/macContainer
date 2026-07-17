import CryptoKit
import Darwin
import Foundation
import MCCompatibility
import MCContainerBridge

public struct RuntimeReleaseHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let finalURL: URL
    public let body: Data

    public init(statusCode: Int, finalURL: URL, body: Data) {
        self.statusCode = statusCode
        self.finalURL = finalURL
        self.body = body
    }
}

public protocol RuntimeReleaseDataLoading: Sendable {
    func load(_ url: URL) async throws -> RuntimeReleaseHTTPResponse
}

public struct URLSessionRuntimeReleaseDataLoader: RuntimeReleaseDataLoading, Sendable {
    public init() {}

    public func load(_ url: URL) async throws -> RuntimeReleaseHTTPResponse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(
            configuration: configuration,
            delegate: RuntimeReleaseRedirectRefuser(),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse, let finalURL = response.url else {
            throw ProductionLifecycleComponentError.untrustedReleaseResponse
        }
        return .init(statusCode: response.statusCode, finalURL: finalURL, body: data)
    }
}

private final class RuntimeReleaseRedirectRefuser: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public struct SystemRuntimeReleaseMetadataFetcher: RuntimeReleaseMetadataFetching, Sendable {
    private static let maximumResponseBytes = 2_000_000
    private let loader: any RuntimeReleaseDataLoading

    public init(loader: any RuntimeReleaseDataLoading = URLSessionRuntimeReleaseDataLoader()) {
        self.loader = loader
    }

    public func fetchRelease(at apiURL: URL) async throws -> RuntimeReleaseMetadata {
        let version = try Self.validateAPIURL(apiURL)
        let response = try await loader.load(apiURL)
        guard response.statusCode == 200, response.finalURL == apiURL else {
            throw ProductionLifecycleComponentError.untrustedReleaseResponse
        }
        guard response.body.count <= Self.maximumResponseBytes else {
            throw ProductionLifecycleComponentError.releaseMetadataTooLarge
        }
        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: response.body)
        } catch {
            throw ProductionLifecycleComponentError.invalidReleaseMetadata
        }
        guard release.assets.count <= 256 else {
            throw ProductionLifecycleComponentError.invalidReleaseMetadata
        }
        let expectedName = "container-\(version)-installer-signed.pkg"
        let matching = release.assets.filter { $0.name == expectedName }
        guard matching.count == 1,
              let asset = matching.first,
              let downloadURL = URL(string: asset.browserDownloadURL),
              downloadURL.scheme == "https",
              downloadURL.user == nil,
              downloadURL.password == nil,
              downloadURL.fragment == nil,
              downloadURL.lastPathComponent == expectedName
        else {
            throw ProductionLifecycleComponentError.invalidReleaseMetadata
        }
        return RuntimeReleaseMetadata(asset: .init(name: asset.name, downloadURL: downloadURL))
    }

    private static func validateAPIURL(_ url: URL) throws -> String {
        let prefix = "/repos/apple/container/releases/tags/"
        guard url.scheme == "https",
              url.host == "api.github.com",
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              url.path.hasPrefix(prefix)
        else {
            throw ProductionLifecycleComponentError.invalidReleaseMetadata
        }
        let version = String(url.path.dropFirst(prefix.count))
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
        else {
            throw ProductionLifecycleComponentError.invalidReleaseMetadata
        }
        return version
    }
}

private struct GitHubRelease: Decodable {
    let assets: [GitHubReleaseAsset]
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

public struct PackageReceiptCommandResult: Equatable, Sendable {
    public let exitStatus: Int32
    public let output: Data

    public init(exitStatus: Int32, output: Data) {
        self.exitStatus = exitStatus
        self.output = output
    }
}

public protocol PackageReceiptCommandRunning: Sendable {
    func packageInfo(identifier: String) throws -> PackageReceiptCommandResult
}

public struct SystemPackageReceiptCommandRunner: PackageReceiptCommandRunning, Sendable {
    public init() {}

    public func packageInfo(identifier: String) throws -> PackageReceiptCommandResult {
        guard Self.isSafeIdentifier(identifier) else {
            throw ProductionLifecycleComponentError.invalidReceipt
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        process.arguments = ["--pkg-info-plist", identifier]
        process.environment = [:]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard data.count <= 1_000_000 else {
            throw ProductionLifecycleComponentError.commandOutputTooLarge
        }
        return .init(exitStatus: process.terminationStatus, output: data)
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        return components.count >= 3 && components.allSatisfy { component in
            !component.isEmpty && component.allSatisfy {
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")
            }
        }
    }
}

public struct SystemPackageReceiptBackend: PackageReceiptReading, Sendable {
    private let command: any PackageReceiptCommandRunning

    public init(command: any PackageReceiptCommandRunning = SystemPackageReceiptCommandRunner()) {
        self.command = command
    }

    public func receipt(identifier: String) async throws -> InstalledPackageReceipt? {
        let result = try command.packageInfo(identifier: identifier)
        if result.exitStatus != 0 {
            let expected = "No receipt for '\(identifier)' found at '/'."
            guard String(data: result.output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) == expected
            else {
                throw ProductionLifecycleComponentError.receiptCommandFailed(result.exitStatus)
            }
            return nil
        }
        let values: [String: Any]
        do {
            let plist = try PropertyListSerialization.propertyList(from: result.output, options: [], format: nil)
            guard let dictionary = plist as? [String: Any] else {
                throw ProductionLifecycleComponentError.invalidReceipt
            }
            values = dictionary
        } catch let error as ProductionLifecycleComponentError {
            throw error
        } catch {
            throw ProductionLifecycleComponentError.invalidReceipt
        }
        guard values["pkgid"] as? String == identifier,
              let version = values["pkg-version"] as? String,
              !version.isEmpty,
              let receiptLocation = values["install-location"] as? String,
              receiptLocation == "usr/local" || receiptLocation == "/usr/local"
        else {
            throw ProductionLifecycleComponentError.invalidReceipt
        }
        return .init(identifier: identifier, version: version, installLocation: "/usr/local")
    }
}

public struct SystemInstalledPayloadVerifier: InstalledPayloadVerifying, Sendable {
    private let installRoot: URL?

    public init(installRoot: URL? = nil) {
        self.installRoot = installRoot?.standardizedFileURL
    }

    public func verify(expected manifest: RuntimePackageManifest) async throws {
        try manifest.validate()
        let root = installRoot ?? URL(fileURLWithPath: manifest.installLocation, isDirectory: true)
        guard root.isFileURL, root.path.hasPrefix("/") else {
            throw ProductionLifecycleComponentError.unsafeInstallRoot
        }
        for entry in manifest.payload {
            try verify(entry, at: root.appendingPathComponent(entry.relativePath))
        }
    }

    private func verify(_ entry: PayloadEntry, at url: URL) throws {
        switch entry.kind {
        case .directory:
            try verifyDirectory(at: url, relativePath: entry.relativePath)
        case .file:
            try verifyFile(at: url, entry: entry)
        case .symlink:
            try verifySymlink(at: url, entry: entry)
        }
    }

    private func verifyDirectory(at url: URL, relativePath: String) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw ProductionLifecycleComponentError.payloadMismatch(relativePath)
        }
        defer { Darwin.close(descriptor) }
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFDIR else {
            throw ProductionLifecycleComponentError.payloadMismatch(relativePath)
        }
    }

    private func verifyFile(at url: URL, entry: PayloadEntry) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw ProductionLifecycleComponentError.payloadMismatch(entry.relativePath)
        }
        defer { Darwin.close(descriptor) }
        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              before.st_mode & S_IFMT == S_IFREG,
              before.st_nlink == 1,
              let expectedDigest = entry.sha256
        else {
            throw ProductionLifecycleComponentError.payloadMismatch(entry.relativePath)
        }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else {
                if errno == EINTR {
                    continue
                }
                throw ProductionLifecycleComponentError.payloadMismatch(entry.relativePath)
            }
            guard count > 0 else { break }
            buffer.withUnsafeBytes { pointer in
                hasher.update(bufferPointer: UnsafeRawBufferPointer(
                    start: pointer.baseAddress,
                    count: count
                ))
            }
        }
        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              hasher.finalize().map({ String(format: "%02x", $0) }).joined() == expectedDigest
        else {
            throw ProductionLifecycleComponentError.payloadMismatch(entry.relativePath)
        }
    }

    private func verifySymlink(at url: URL, entry: PayloadEntry) throws {
        var status = stat()
        guard Darwin.lstat(url.path, &status) == 0,
              status.st_mode & S_IFMT == S_IFLNK,
              let expectedTarget = entry.linkTarget
        else {
            throw ProductionLifecycleComponentError.payloadMismatch(entry.relativePath)
        }
        var buffer = [CChar](repeating: 0, count: 4096)
        let count = Darwin.readlink(url.path, &buffer, buffer.count)
        guard count > 0,
              count < buffer.count,
              String(bytes: buffer.prefix(count).map { UInt8(bitPattern: $0) }, encoding: .utf8) == expectedTarget
        else {
            throw ProductionLifecycleComponentError.payloadMismatch(entry.relativePath)
        }
    }
}

public struct SystemRuntimePackageDownloader: RuntimePackageDownloading, Sendable {
    public static let allowedHosts: Set<String> = [
        "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"
    ]

    private let backend: any KernelDownloading

    public init(
        backend: any KernelDownloading = URLSessionKernelDownloader(maximumBytes: 1_000_000_000)
    ) {
        self.backend = backend
    }

    public func download(_ asset: RuntimeReleaseAsset, to destination: URL) async throws {
        let destination = destination.standardizedFileURL
        guard destination.isFileURL,
              destination.path.hasPrefix("/"),
              destination.lastPathComponent == asset.name,
              asset.downloadURL.scheme == "https",
              asset.downloadURL.user == nil,
              asset.downloadURL.password == nil,
              asset.downloadURL.fragment == nil,
              asset.downloadURL.lastPathComponent == asset.name,
              asset.downloadURL.host.map({ Self.allowedHosts.contains($0.lowercased()) }) == true
        else {
            throw ProductionLifecycleComponentError.unsafePackageDestination
        }
        var parentStatus = stat()
        let parent = destination.deletingLastPathComponent()
        guard Darwin.lstat(parent.path, &parentStatus) == 0,
              parentStatus.st_mode & S_IFMT == S_IFDIR,
              parentStatus.st_uid == geteuid(),
              parentStatus.st_mode & 0o077 == 0
        else {
            throw ProductionLifecycleComponentError.unsafePackageDestination
        }
        var destinationStatus = stat()
        guard Darwin.lstat(destination.path, &destinationStatus) != 0, errno == ENOENT else {
            throw ProductionLifecycleComponentError.unsafePackageDestination
        }

        try await backend.download(
            from: asset.downloadURL,
            to: destination,
            allowedHosts: Self.allowedHosts
        )

        guard Darwin.lstat(destination.path, &destinationStatus) == 0,
              destinationStatus.st_mode & S_IFMT == S_IFREG,
              destinationStatus.st_uid == geteuid(),
              destinationStatus.st_nlink == 1,
              destinationStatus.st_mode & 0o077 == 0,
              destinationStatus.st_size > 0
        else {
            throw ProductionLifecycleComponentError.unsafePackageDestination
        }
    }
}

public protocol InstallHostInspecting: Sendable {
    var macOSMajor: Int { get }
    var isAppleSilicon: Bool { get }
}

public struct SystemInstallHostInspector: InstallHostInspecting, Sendable {
    public init() {}

    public var macOSMajor: Int {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }

    public var isAppleSilicon: Bool {
        #if arch(arm64)
            true
        #else
            false
        #endif
    }
}

public struct SystemInstallPlatformChecker: InstallPlatformChecking, Sendable {
    private let host: any InstallHostInspecting
    private let receipts: PackageReceiptReader

    public init(
        host: any InstallHostInspecting = SystemInstallHostInspector(),
        receipts: PackageReceiptReader = PackageReceiptReader(backend: SystemPackageReceiptBackend())
    ) {
        self.host = host
        self.receipts = receipts
    }

    public func preflight(for target: RuntimeInstallTarget) async throws -> InstallPlatformReport {
        try target.manifest.validate()
        guard host.macOSMajor >= 26, host.isAppleSilicon else {
            throw ProductionLifecycleComponentError.unsupportedHost
        }
        let installed = try await receipts.readReviewedRuntimeReceipt(
            identifier: target.manifest.receiptIdentifier
        )
        return .init(installedRuntimeVersion: installed?.version)
    }
}

public struct SystemInstalledReceiptVerifier: InstalledReceiptVerifying, Sendable {
    private let receipts: PackageReceiptReader

    public init(
        receipts: PackageReceiptReader = PackageReceiptReader(backend: SystemPackageReceiptBackend())
    ) {
        self.receipts = receipts
    }

    public func verify(expected manifest: RuntimePackageManifest) async throws -> InstalledPackageReceipt {
        try manifest.validate()
        guard let receipt = try await receipts.readReviewedRuntimeReceipt(
            identifier: manifest.receiptIdentifier
        ) else {
            throw ProductionLifecycleComponentError.receiptMissing
        }
        guard receipt.identifier == manifest.receiptIdentifier,
              receipt.version == manifest.runtimeVersion,
              receipt.installLocation == manifest.installLocation
        else {
            throw ProductionLifecycleComponentError.invalidReceipt
        }
        return receipt
    }
}

public struct BridgeInstallServiceController: InstallServiceControlling, Sendable {
    private let bridge: any RuntimeBridge

    public init(bridge: any RuntimeBridge) {
        self.bridge = bridge
    }

    public func startRuntime() async throws {
        let result = try await bridge.system.start(.init(healthTimeoutSeconds: 60))
        guard result.state == .running else {
            throw ProductionLifecycleComponentError.runtimeStartFailed
        }
    }
}

public struct BridgeInstallKernelEnsurer: InstallKernelEnsuring, Sendable {
    private let bridge: any RuntimeBridge

    public init(bridge: any RuntimeBridge) {
        self.bridge = bridge
    }

    public func ensureKernel(for target: RuntimeInstallTarget) async throws {
        guard target.manifest.runtimeVersion == ReviewedRuntime110Manifest.package.runtimeVersion else {
            throw ProductionLifecycleComponentError.invalidReleaseMetadata
        }
        let result = try await bridge.kernel.setRecommended(platform: "linux/arm64", force: false)
        guard result.platform == "linux/arm64" else {
            throw ProductionLifecycleComponentError.kernelInstallFailed
        }
    }
}

public struct BridgeInstallProbeRunner: InstallProbeRunning, Sendable {
    private let bridge: any RuntimeBridge
    private let expectedRuntimeVersion: String
    private let enabledCapabilityIDs: Set<String>
    private let registry: ProbeRegistry

    public init(
        bridge: any RuntimeBridge,
        expectedRuntimeVersion: String,
        enabledCapabilityIDs: Set<String>,
        registry: ProbeRegistry = ProbeRegistry()
    ) {
        self.bridge = bridge
        self.expectedRuntimeVersion = expectedRuntimeVersion
        self.enabledCapabilityIDs = enabledCapabilityIDs
        self.registry = registry
    }

    public func run(probes: [String]) async throws {
        guard probes == ProbeID.baselineAllCases.map(\.rawValue), !enabledCapabilityIDs.isEmpty else {
            throw ProductionLifecycleComponentError.invalidProbeSet
        }
        let report = await registry.runAll(context: .init(
            bridge: bridge,
            expectedRuntimeVersion: expectedRuntimeVersion,
            expectedCapabilityIDs: enabledCapabilityIDs,
            enabledCapabilityIDs: enabledCapabilityIDs,
            phase: .postflight
        ))
        guard report.isCompatible else {
            let failed = report.results.first { result in
                if case .failed = result.outcome {
                    return true
                }
                return false
            }
            throw ProductionLifecycleComponentError.probeFailed(failed?.id.rawValue ?? "unknown")
        }
    }
}

public enum ProductionLifecycleComponentError: Error, Equatable, Sendable {
    case commandOutputTooLarge
    case invalidReceipt
    case invalidReleaseMetadata
    case invalidProbeSet
    case kernelInstallFailed
    case payloadMismatch(String)
    case probeFailed(String)
    case receiptCommandFailed(Int32)
    case receiptMissing
    case releaseMetadataTooLarge
    case runtimeStartFailed
    case unsafeInstallRoot
    case unsafePackageDestination
    case unsupportedHost
    case untrustedReleaseResponse
}
