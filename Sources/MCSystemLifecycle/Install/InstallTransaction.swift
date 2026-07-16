import Darwin
import Foundation

public enum InstallStage: String, CaseIterable, Codable, Sendable {
    case platformPreflight = "platform.preflight"
    case metadataFetch = "metadata.fetch"
    case packageDownload = "download"
    case packageVerification = "package.verify"
    case consent
    case journalIntent = "journal.intent.install"
    case helperInstall = "helper.install"
    case receiptVerification = "receipt.verify"
    case payloadVerification = "payload.verify"
    case serviceStart = "service.start"
    case kernelEnsure = "kernel.ensure"
    case probeRun = "probes.run"
    case journalCommit = "journal.commit"

    public var isAtOrAfterInstallAttempt: Bool {
        switch self {
        case .helperInstall, .receiptVerification, .payloadVerification, .serviceStart,
             .kernelEnsure, .probeRun, .journalCommit:
            true
        default:
            false
        }
    }
}

public struct RuntimeInstallTarget: Equatable, Sendable {
    public let manifest: RuntimePackageManifest
    public let releaseAPIURL: URL
    public let requiredProbes: [String]

    public init(
        manifest: RuntimePackageManifest,
        releaseAPIURL: URL,
        requiredProbes: [String]
    ) {
        self.manifest = manifest
        self.releaseAPIURL = releaseAPIURL
        self.requiredProbes = requiredProbes
    }

    public static let appleContainer110 = Self(
        manifest: ReviewedRuntime110Manifest.package,
        releaseAPIURL: reviewedReleaseURL(),
        requiredProbes: [
            "api.version", "service.health", "images.list", "images.decode",
            "network.list", "container.lifecycle", "build.smoke", "logs.stream"
        ]
    )

    private static func reviewedReleaseURL() -> URL {
        guard let url = URL(
            string: "https://api.github.com/repos/apple/container/releases/tags/1.1.0"
        ) else {
            preconditionFailure("Reviewed release URL must be valid")
        }
        return url
    }
}

public struct InstallPlatformReport: Equatable, Sendable {
    public let installedRuntimeVersion: String?

    public init(installedRuntimeVersion: String?) {
        self.installedRuntimeVersion = installedRuntimeVersion
    }
}

public struct RuntimeReleaseAsset: Equatable, Sendable {
    public let name: String
    public let downloadURL: URL

    public init(name: String, downloadURL: URL) {
        self.name = name
        self.downloadURL = downloadURL
    }
}

public struct RuntimeReleaseMetadata: Equatable, Sendable {
    public let asset: RuntimeReleaseAsset

    public init(asset: RuntimeReleaseAsset) {
        self.asset = asset
    }
}

public struct InstallConsentRequest: Equatable, Sendable {
    public let runtimeVersion: String
    public let packageSHA256: String
    public let assetName: String

    public init(runtimeVersion: String, packageSHA256: String, assetName: String) {
        self.runtimeVersion = runtimeVersion
        self.packageSHA256 = packageSHA256
        self.assetName = assetName
    }
}

public struct PartialInstallAudit: Equatable, Sendable {
    public let isEmpty: Bool
    public let hasUnverifiableItems: Bool

    public init(isEmpty: Bool, hasUnverifiableItems: Bool) {
        self.isEmpty = isEmpty
        self.hasUnverifiableItems = hasUnverifiableItems
    }
}

public struct InstallReport: Equatable, Sendable {
    public let runtimeVersion: String
    public let packageSHA256: String
    public let receipt: InstalledPackageReceipt

    public init(
        runtimeVersion: String,
        packageSHA256: String,
        receipt: InstalledPackageReceipt
    ) {
        self.runtimeVersion = runtimeVersion
        self.packageSHA256 = packageSHA256
        self.receipt = receipt
    }
}

public protocol InstallPlatformChecking: Sendable {
    func preflight(for target: RuntimeInstallTarget) async throws -> InstallPlatformReport
}

public protocol RuntimeReleaseMetadataFetching: Sendable {
    func fetchRelease(at apiURL: URL) async throws -> RuntimeReleaseMetadata
}

public protocol RuntimePackageDownloading: Sendable {
    func download(_ asset: RuntimeReleaseAsset, to destination: URL) async throws
}

public protocol InstallRuntimePackageVerifying: Sendable {
    func verify(
        packageAt url: URL,
        against manifest: RuntimePackageManifest
    ) async throws -> VerifiedRuntimePackage
}

extension RuntimePackageVerifier: InstallRuntimePackageVerifying {}

public protocol InstallConsentProviding: Sendable {
    func approve(_ request: InstallConsentRequest) async throws -> Bool
}

public protocol InstallJournalWriting: Sendable {
    func begin(targetVersion: String) async throws -> UUID
    func recordInstallIntent(transactionID: UUID, digest: String) async throws
    func recordInstallApplied(transactionID: UUID, digest: String) async throws
    func recordVerified(transactionID: UUID) async throws
    func commit(transactionID: UUID) async throws
    func fail(transactionID: UUID, failure: RedactedLifecycleFailure) async throws
}

public protocol InstallPrivilegedHelping: Sendable {
    func install(_ package: VerifiedRuntimePackage) async throws
}

public protocol InstalledReceiptVerifying: Sendable {
    func verify(expected manifest: RuntimePackageManifest) async throws -> InstalledPackageReceipt
}

public protocol InstalledPayloadVerifying: Sendable {
    func verify(expected manifest: RuntimePackageManifest) async throws
}

public protocol InstallServiceControlling: Sendable {
    func startRuntime() async throws
}

public protocol InstallKernelEnsuring: Sendable {
    func ensureKernel(for target: RuntimeInstallTarget) async throws
}

public protocol InstallProbeRunning: Sendable {
    func run(probes: [String]) async throws
}

public protocol PartialInstallUninstalling: Sendable {
    func removePartialInstall(manifest: RuntimePackageManifest) async throws
}

public protocol PartialInstallResidueAuditing: Sendable {
    func audit(manifest: RuntimePackageManifest) async throws -> PartialInstallAudit
}

public protocol InstallTemporaryDirectoryProviding: Sendable {
    func create(transactionID: UUID) throws -> InstallTemporaryDirectory
}

public final class InstallTemporaryDirectory: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()
    private let cleanupAction: @Sendable () throws -> Void
    private var cleaned = false

    public init(url: URL, cleanup: @escaping @Sendable () throws -> Void) {
        self.url = url
        cleanupAction = cleanup
    }

    deinit {
        try? cleanup()
    }

    public func cleanup() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !cleaned else { return }
        try cleanupAction()
        cleaned = true
    }
}

public struct LocalInstallTemporaryDirectoryProvider: InstallTemporaryDirectoryProviding {
    private let baseDirectory: URL

    public init(baseDirectory: URL = Self.defaultBaseDirectory) {
        self.baseDirectory = baseDirectory.standardizedFileURL
    }

    public func create(transactionID: UUID) throws -> InstallTemporaryDirectory {
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: baseDirectory.path)
        var status = stat()
        guard
            Darwin.lstat(baseDirectory.path, &status) == 0,
            status.st_mode & S_IFMT == S_IFDIR,
            status.st_uid == geteuid(),
            status.st_mode & 0o077 == 0
        else { throw InstallError.unsafeTemporaryDirectory }
        let url = baseDirectory.appendingPathComponent(transactionID.uuidString, isDirectory: true)
        guard Darwin.mkdir(url.path, 0o700) == 0 else { throw posixError() }
        guard Darwin.lstat(url.path, &status) == 0 else { throw posixError() }
        let identity = TemporaryDirectoryIdentity(status)
        return InstallTemporaryDirectory(url: url) {
            var current = stat()
            if Darwin.lstat(url.path, &current) != 0 {
                if errno == ENOENT {
                    return
                }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            guard
                TemporaryDirectoryIdentity(current) == identity,
                current.st_mode & S_IFMT == S_IFDIR,
                current.st_uid == geteuid(),
                current.st_mode & 0o077 == 0
            else {
                throw InstallError.unsafeTemporaryDirectory
            }
            try FileManager.default.removeItem(at: url)
            var removed = stat()
            guard Darwin.lstat(url.path, &removed) != 0, errno == ENOENT else {
                throw InstallError.temporaryCleanupFailed
            }
        }
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    public static var defaultBaseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("container.matrixreligio.com", isDirectory: true)
            .appendingPathComponent("Lifecycle", isDirectory: true)
            .appendingPathComponent("Staging", isDirectory: true)
    }
}

public struct LifecycleInstallJournalWriter: InstallJournalWriting {
    private let journal: LifecycleJournal

    public init(journal: LifecycleJournal) {
        self.journal = journal
    }

    public func begin(targetVersion: String) async throws -> UUID {
        try await journal.begin(kind: .install, targetVersion: targetVersion)
    }

    public func recordInstallIntent(transactionID: UUID, digest: String) async throws {
        try await journal.recordIntent(.installPackage(digest: digest), transactionID: transactionID)
    }

    public func recordInstallApplied(transactionID: UUID, digest: String) async throws {
        try await journal.recordApplied(.installPackage(digest: digest), transactionID: transactionID)
    }

    public func recordVerified(transactionID: UUID) async throws {
        try await journal.recordVerified(transactionID: transactionID)
    }

    public func commit(transactionID: UUID) async throws {
        try await journal.commit(transactionID: transactionID)
    }

    public func fail(transactionID: UUID, failure: RedactedLifecycleFailure) async throws {
        try await journal.recordFailure(failure, transactionID: transactionID)
    }
}

public struct InstallTransaction: Sendable {
    private let platform: any InstallPlatformChecking
    private let metadata: any RuntimeReleaseMetadataFetching
    private let downloader: any RuntimePackageDownloading
    private let verifier: any InstallRuntimePackageVerifying
    private let consent: any InstallConsentProviding
    private let journal: any InstallJournalWriting
    private let helper: any InstallPrivilegedHelping
    private let receipt: any InstalledReceiptVerifying
    private let payload: any InstalledPayloadVerifying
    private let service: any InstallServiceControlling
    private let kernel: any InstallKernelEnsuring
    private let probes: any InstallProbeRunning
    private let partialUninstaller: any PartialInstallUninstalling
    private let residueAuditor: any PartialInstallResidueAuditing
    private let temporaryDirectories: any InstallTemporaryDirectoryProviding

    public init(
        platform: any InstallPlatformChecking,
        metadata: any RuntimeReleaseMetadataFetching,
        downloader: any RuntimePackageDownloading,
        verifier: any InstallRuntimePackageVerifying,
        consent: any InstallConsentProviding,
        journal: any InstallJournalWriting,
        helper: any InstallPrivilegedHelping,
        receipt: any InstalledReceiptVerifying,
        payload: any InstalledPayloadVerifying,
        service: any InstallServiceControlling,
        kernel: any InstallKernelEnsuring,
        probes: any InstallProbeRunning,
        partialUninstaller: any PartialInstallUninstalling,
        residueAuditor: any PartialInstallResidueAuditing,
        temporaryDirectories: any InstallTemporaryDirectoryProviding
    ) {
        self.platform = platform
        self.metadata = metadata
        self.downloader = downloader
        self.verifier = verifier
        self.consent = consent
        self.journal = journal
        self.helper = helper
        self.receipt = receipt
        self.payload = payload
        self.service = service
        self.kernel = kernel
        self.probes = probes
        self.partialUninstaller = partialUninstaller
        self.residueAuditor = residueAuditor
        self.temporaryDirectories = temporaryDirectories
    }

    public func install(_ target: RuntimeInstallTarget) async throws -> InstallReport {
        let transactionID = try await beginTransaction(for: target)
        let temporary = try await createTemporaryDirectory(transactionID: transactionID)
        var needsFallbackCleanup = true
        defer {
            if needsFallbackCleanup {
                try? temporary.cleanup()
            }
        }

        var currentStage = InstallStage.journalIntent
        var installAttempted = false
        let report: InstallReport
        do {
            currentStage = .platformPreflight
            try Self.validate(target)
            let platformReport = try await platform.preflight(for: target)
            if let installed = platformReport.installedRuntimeVersion {
                throw InstallError.upgradeRequired(installedVersion: installed)
            }

            currentStage = .metadataFetch
            let release = try await metadata.fetchRelease(at: target.releaseAPIURL)
            try Self.validate(release.asset, against: target.manifest)

            currentStage = .packageDownload
            let packageURL = temporary.url.appendingPathComponent(
                target.manifest.assetName,
                isDirectory: false
            )
            try await downloader.download(release.asset, to: packageURL)

            currentStage = .packageVerification
            let verified = try await verifier.verify(packageAt: packageURL, against: target.manifest)
            try Self.validate(verified, against: target.manifest)

            currentStage = .consent
            let approved = try await consent.approve(.init(
                runtimeVersion: target.manifest.runtimeVersion,
                packageSHA256: target.manifest.sha256,
                assetName: target.manifest.assetName
            ))
            guard approved else { throw InstallError.consentDenied }

            currentStage = .journalIntent
            try await journal.recordInstallIntent(
                transactionID: transactionID,
                digest: verified.sha256
            )

            currentStage = .helperInstall
            installAttempted = true
            try await helper.install(verified)
            try await journal.recordInstallApplied(
                transactionID: transactionID,
                digest: verified.sha256
            )

            currentStage = .receiptVerification
            let installedReceipt = try await receipt.verify(expected: target.manifest)
            guard
                installedReceipt.identifier == target.manifest.receiptIdentifier,
                installedReceipt.version == target.manifest.runtimeVersion,
                installedReceipt.installLocation == target.manifest.installLocation
            else {
                throw InstallError.receiptMismatch
            }

            currentStage = .payloadVerification
            try await payload.verify(expected: target.manifest)

            currentStage = .serviceStart
            try await service.startRuntime()

            currentStage = .kernelEnsure
            try await kernel.ensureKernel(for: target)

            currentStage = .probeRun
            try await probes.run(probes: target.requiredProbes)

            currentStage = .journalCommit
            try await journal.recordVerified(transactionID: transactionID)
            try await journal.commit(transactionID: transactionID)
            report = InstallReport(
                runtimeVersion: verified.runtimeVersion,
                packageSHA256: verified.sha256,
                receipt: installedReceipt
            )
        } catch {
            let result = await recoverFailure(
                error,
                stage: currentStage,
                transactionID: transactionID,
                installAttempted: installAttempted,
                manifest: target.manifest
            )
            if try Self.cleanupAfterFailure(temporary, preserving: result) {
                needsFallbackCleanup = false
            }
            throw result
        }

        try Self.cleanupAfterSuccess(temporary)
        needsFallbackCleanup = false
        return report
    }

    private func beginTransaction(for target: RuntimeInstallTarget) async throws -> UUID {
        do {
            return try await journal.begin(targetVersion: target.manifest.runtimeVersion)
        } catch {
            throw InstallError.journalUnavailable
        }
    }

    private func createTemporaryDirectory(transactionID: UUID) async throws -> InstallTemporaryDirectory {
        do {
            return try temporaryDirectories.create(transactionID: transactionID)
        } catch {
            try? await journal.fail(
                transactionID: transactionID,
                failure: .init(code: "install.staging.create", redactedDetail: "stage-failed")
            )
            throw InstallError.temporaryDirectoryUnavailable
        }
    }

    private static func cleanupAfterSuccess(_ temporary: InstallTemporaryDirectory) throws {
        do {
            try temporary.cleanup()
        } catch {
            throw InstallError.installedButTemporaryCleanupFailed
        }
    }

    private static func cleanupAfterFailure(
        _ temporary: InstallTemporaryDirectory,
        preserving result: InstallError
    ) throws -> Bool {
        do {
            try temporary.cleanup()
            return true
        } catch {
            guard result == .incompleteRecovery else {
                throw InstallError.temporaryCleanupFailed
            }
            return false
        }
    }

    private func recoverFailure(
        _ error: Error,
        stage: InstallStage,
        transactionID: UUID?,
        installAttempted: Bool,
        manifest: RuntimePackageManifest
    ) async -> InstallError {
        var incompleteRecovery = false
        if installAttempted {
            do {
                try await partialUninstaller.removePartialInstall(manifest: manifest)
                let audit = try await residueAuditor.audit(manifest: manifest)
                if !audit.isEmpty || audit.hasUnverifiableItems {
                    incompleteRecovery = true
                }
            } catch {
                incompleteRecovery = true
            }
        }

        if let transactionID {
            do {
                try await journal.fail(
                    transactionID: transactionID,
                    failure: .init(
                        code: "install.\(stage.rawValue)",
                        redactedDetail: incompleteRecovery ? "recovery-incomplete" : "stage-failed"
                    )
                )
            } catch {
                incompleteRecovery = true
            }
        }
        if incompleteRecovery {
            return .incompleteRecovery
        }
        if installAttempted {
            return .postflightFailed
        }
        if let installError = error as? InstallError {
            return installError
        }
        return .stageFailed(stage)
    }

    private static func validate(_ target: RuntimeInstallTarget) throws {
        do {
            try target.manifest.validate()
        } catch {
            throw InstallError.invalidTarget
        }
        let probes = target.requiredProbes
        guard
            (1 ... 64).contains(probes.count),
            Set(probes).count == probes.count,
            probes.allSatisfy({ probe in
                (1 ... 64).contains(probe.count) && probe.allSatisfy {
                    $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-")
                }
            })
        else {
            throw InstallError.invalidTarget
        }
        try validateReleaseAPIURL(
            target.releaseAPIURL,
            runtimeVersion: target.manifest.runtimeVersion
        )
    }

    private static func validateReleaseAPIURL(_ url: URL, runtimeVersion: String) throws {
        guard
            url.scheme == "https",
            url.host == "api.github.com",
            url.user == nil,
            url.password == nil,
            url.query == nil,
            url.fragment == nil,
            url.path == "/repos/apple/container/releases/tags/\(runtimeVersion)"
        else {
            throw InstallError.invalidReleaseMetadata
        }
    }

    private static func validate(
        _ asset: RuntimeReleaseAsset,
        against manifest: RuntimePackageManifest
    ) throws {
        let allowedHosts = Set([
            "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"
        ])
        guard
            asset.name == manifest.assetName,
            asset.downloadURL.scheme == "https",
            asset.downloadURL.user == nil,
            asset.downloadURL.password == nil,
            asset.downloadURL.fragment == nil,
            asset.downloadURL.lastPathComponent == manifest.assetName,
            asset.downloadURL.host.map(allowedHosts.contains) == true
        else {
            throw InstallError.invalidReleaseMetadata
        }
    }

    private static func validate(
        _ verified: VerifiedRuntimePackage,
        against manifest: RuntimePackageManifest
    ) throws {
        guard
            verified.runtimeVersion == manifest.runtimeVersion,
            verified.sha256 == manifest.sha256,
            verified.installerTeamID == manifest.installerTeamID,
            verified.signerCommonName == manifest.signerCommonName,
            verified.receiptIdentifier == manifest.receiptIdentifier,
            verified.installLocation == manifest.installLocation,
            verified.payload == manifest.payload
        else {
            throw InstallError.verificationReportMismatch
        }
        try verified.openFile.revalidateIdentity()
    }
}

public enum InstallError: Error, Equatable, Sendable {
    case consentDenied
    case incompleteRecovery
    case installedButTemporaryCleanupFailed
    case invalidReleaseMetadata
    case invalidTarget
    case journalUnavailable
    case postflightFailed
    case receiptMismatch
    case stageFailed(InstallStage)
    case temporaryCleanupFailed
    case temporaryDirectoryUnavailable
    case unsafeTemporaryDirectory
    case upgradeRequired(installedVersion: String)
    case verificationReportMismatch
}

private struct TemporaryDirectoryIdentity: Equatable, Sendable {
    let device: dev_t
    let inode: ino_t

    init(_ status: stat) {
        device = status.st_dev
        inode = status.st_ino
    }
}
