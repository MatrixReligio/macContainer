import Darwin
import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("Transactional runtime installation")
struct InstallTransactionTests {
    @Test func `successful install uses verified descriptor and cleans download`() async throws {
        let fixture = try InstallFixture()
        defer { fixture.cleanup() }

        let report = try await fixture.transaction.install(.testTarget)

        #expect(report.runtimeVersion == "1.1.0")
        #expect(report.packageSHA256 == RuntimePackageManifest.installFixture.sha256)
        #expect(fixture.actions.values == InstallStage.allCases.map(\.rawValue) + ["download.cleanup"])
        #expect(fixture.temporaryDirectories.activePaths.isEmpty)
        #expect(fixture.helper.receivedDescriptor != nil)
        #expect(fixture.journal.appliedCount == 1)
        #expect(fixture.journal.verifiedCount == 1)
    }

    @Test(arguments: InstallStage.allCases)
    func `failure at every stage is journaled and leaves no temporary path`(_ stage: InstallStage) async throws {
        let fixture = try InstallFixture(failingAt: stage)
        defer { fixture.cleanup() }

        await #expect(throws: InstallError.self) {
            _ = try await fixture.transaction.install(.testTarget)
        }

        #expect(fixture.temporaryDirectories.activePaths.isEmpty)
        #expect(fixture.journal.failureCount == 1)
        if stage.isAtOrAfterInstallAttempt {
            #expect(fixture.actions.values.suffix(3) == [
                "uninstall.partial", "residue.audit", "download.cleanup"
            ])
        } else {
            #expect(fixture.actions.values.last == "download.cleanup")
            #expect(!fixture.actions.values.contains("uninstall.partial"))
        }
    }

    @Test func `partial install residue fails closed as incomplete recovery`() async throws {
        let fixture = try InstallFixture(
            failingAt: .probeRun,
            audit: .init(isEmpty: false, hasUnverifiableItems: true)
        )
        defer { fixture.cleanup() }

        await #expect(throws: InstallError.incompleteRecovery) {
            _ = try await fixture.transaction.install(.testTarget)
        }
        #expect(fixture.actions.values.suffix(3) == [
            "uninstall.partial", "residue.audit", "download.cleanup"
        ])
    }

    @Test func `existing installation is routed to upgrade without download or mutation`() async throws {
        let fixture = try InstallFixture(existingVersion: "1.0.0")
        defer { fixture.cleanup() }

        await #expect(throws: InstallError.upgradeRequired(installedVersion: "1.0.0")) {
            _ = try await fixture.transaction.install(.testTarget)
        }
        #expect(fixture.actions.values == ["platform.preflight", "download.cleanup"])
        #expect(fixture.helper.receivedDescriptor == nil)
    }

    @Test func `rejects metadata asset substitution before download`() async throws {
        let fixture = try InstallFixture(metadataAssetName: "attacker.pkg")
        defer { fixture.cleanup() }

        await #expect(throws: InstallError.invalidReleaseMetadata) {
            _ = try await fixture.transaction.install(.testTarget)
        }
        #expect(fixture.actions.values == [
            "platform.preflight", "metadata.fetch", "download.cleanup"
        ])
    }

    @Test func `local temporary root is private cleaned and rejects symlink replacement`() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainerLocalInstallRootTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: base) }
        let provider = LocalInstallTemporaryDirectoryProvider(baseDirectory: base)

        let normal = try provider.create()
        var status = stat()
        #expect(Darwin.lstat(normal.url.path, &status) == 0)
        #expect(status.st_mode & 0o777 == 0o700)
        try Data("download".utf8).write(to: normal.url.appendingPathComponent("runtime.pkg"))
        try normal.cleanup()
        #expect(Darwin.lstat(normal.url.path, &status) != 0 && errno == ENOENT)

        let replaced = try provider.create()
        let protected = base.appendingPathComponent("protected")
        try Data("keep".utf8).write(to: protected)
        try FileManager.default.removeItem(at: replaced.url)
        try FileManager.default.createSymbolicLink(at: replaced.url, withDestinationURL: protected)
        #expect(throws: InstallError.unsafeTemporaryDirectory) {
            try replaced.cleanup()
        }
        #expect(try String(contentsOf: protected, encoding: .utf8) == "keep")
        try FileManager.default.removeItem(at: replaced.url)
        try replaced.cleanup()
    }
}

private final class InstallFixture {
    let root: URL
    let actions: LockedInstallActions
    let temporaryDirectories: RecordingTemporaryDirectoryProvider
    let journal: RecordingInstallJournal
    let helper: RecordingInstallHelper
    let transaction: InstallTransaction

    init(
        failingAt: InstallStage? = nil,
        audit: PartialInstallAudit = .init(isEmpty: true, hasUnverifiableItems: false),
        existingVersion: String? = nil,
        metadataAssetName: String = RuntimePackageManifest.installFixture.assetName
    ) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainerInstallTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        actions = LockedInstallActions(failingAt: failingAt)
        temporaryDirectories = RecordingTemporaryDirectoryProvider(base: root, actions: actions)
        journal = RecordingInstallJournal(actions: actions)
        helper = RecordingInstallHelper(actions: actions)
        transaction = InstallTransaction(
            platform: RecordingPlatformChecker(
                actions: actions,
                result: .init(installedRuntimeVersion: existingVersion)
            ),
            metadata: RecordingMetadataClient(
                actions: actions,
                assetName: metadataAssetName
            ),
            downloader: RecordingPackageDownloader(actions: actions),
            verifier: RecordingInstallPackageVerifier(actions: actions),
            consent: RecordingInstallConsent(actions: actions),
            journal: journal,
            helper: helper,
            receipt: RecordingReceiptVerifier(actions: actions),
            payload: RecordingPayloadVerifier(actions: actions),
            service: RecordingInstallServiceController(actions: actions),
            kernel: RecordingInstallKernelEnsurer(actions: actions),
            probes: RecordingInstallProbeRunner(actions: actions),
            partialUninstaller: RecordingPartialUninstaller(actions: actions),
            residueAuditor: RecordingPartialResidueAuditor(actions: actions, result: audit),
            temporaryDirectories: temporaryDirectories
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class LockedInstallActions: @unchecked Sendable {
    private let lock = NSLock()
    private let failingAt: InstallStage?
    private var storage: [String] = []

    init(failingAt: InstallStage?) {
        self.failingAt = failingAt
    }

    var values: [String] {
        lock.withLock { storage }
    }

    func stage(_ stage: InstallStage) throws {
        lock.withLock { storage.append(stage.rawValue) }
        if failingAt == stage {
            throw InstallFixtureError.injected(stage)
        }
    }

    func append(_ value: String) {
        lock.withLock { storage.append(value) }
    }
}

private final class RecordingTemporaryDirectoryProvider: InstallTemporaryDirectoryProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let base: URL
    private let actions: LockedInstallActions
    private var paths: Set<URL> = []

    init(base: URL, actions: LockedInstallActions) {
        self.base = base
        self.actions = actions
    }

    var activePaths: Set<URL> {
        lock.withLock { paths }
    }

    func create() throws -> InstallTemporaryDirectory {
        let url = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        lock.withLock { _ = paths.insert(url) }
        return InstallTemporaryDirectory(url: url) { [weak self] in
            guard let self else { return }
            try? FileManager.default.removeItem(at: url)
            lock.withLock { _ = paths.remove(url) }
            actions.append("download.cleanup")
        }
    }
}

private struct RecordingPlatformChecker: InstallPlatformChecking {
    let actions: LockedInstallActions
    let result: InstallPlatformReport

    func preflight(for _: RuntimeInstallTarget) async throws -> InstallPlatformReport {
        try actions.stage(.platformPreflight)
        return result
    }
}

private struct RecordingMetadataClient: RuntimeReleaseMetadataFetching {
    let actions: LockedInstallActions
    let assetName: String

    func fetchRelease(at _: URL) async throws -> RuntimeReleaseMetadata {
        try actions.stage(.metadataFetch)
        return RuntimeReleaseMetadata(
            asset: .init(
                name: assetName,
                downloadURL: URL(string: "https://github.com/apple/container/releases/download/1.1.0/\(assetName)")!
            )
        )
    }
}

private struct RecordingPackageDownloader: RuntimePackageDownloading {
    let actions: LockedInstallActions

    func download(_: RuntimeReleaseAsset, to destination: URL) async throws {
        try actions.stage(.packageDownload)
        try Data("reviewed-package".utf8).write(to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}

private struct RecordingInstallPackageVerifier: InstallRuntimePackageVerifying {
    let actions: LockedInstallActions

    func verify(
        packageAt url: URL,
        against manifest: RuntimePackageManifest
    ) async throws -> VerifiedRuntimePackage {
        try actions.stage(.packageVerification)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let openFile = try OpenRuntimePackageFile(duplicating: handle.fileDescriptor)
        return VerifiedRuntimePackage(
            runtimeVersion: manifest.runtimeVersion,
            sha256: manifest.sha256,
            installerTeamID: manifest.installerTeamID,
            signerCommonName: manifest.signerCommonName,
            receiptIdentifier: manifest.receiptIdentifier,
            installLocation: manifest.installLocation,
            payload: manifest.payload,
            openFile: openFile
        )
    }
}

private struct RecordingInstallConsent: InstallConsentProviding {
    let actions: LockedInstallActions

    func approve(_: InstallConsentRequest) async throws -> Bool {
        try actions.stage(.consent)
        return true
    }
}

private final class RecordingInstallJournal: InstallJournalWriting, @unchecked Sendable {
    let actions: LockedInstallActions
    private(set) var appliedCount = 0
    private(set) var verifiedCount = 0
    private(set) var failureCount = 0

    init(actions: LockedInstallActions) {
        self.actions = actions
    }

    func begin(targetVersion _: String) async throws -> UUID {
        UUID()
    }

    func recordInstallIntent(transactionID _: UUID, digest _: String) async throws {
        try actions.stage(.journalIntent)
    }

    func recordInstallApplied(transactionID _: UUID, digest _: String) async throws {
        appliedCount += 1
    }

    func recordVerified(transactionID _: UUID) async throws {
        verifiedCount += 1
    }

    func commit(transactionID _: UUID) async throws {
        try actions.stage(.journalCommit)
    }

    func fail(transactionID _: UUID, failure _: RedactedLifecycleFailure) async throws {
        failureCount += 1
    }
}

private final class RecordingInstallHelper: InstallPrivilegedHelping, @unchecked Sendable {
    let actions: LockedInstallActions
    private(set) var receivedDescriptor: Int32?

    init(actions: LockedInstallActions) {
        self.actions = actions
    }

    func install(_ package: VerifiedRuntimePackage) async throws {
        receivedDescriptor = package.openFile.fileDescriptor
        try actions.stage(.helperInstall)
    }
}

private struct RecordingReceiptVerifier: InstalledReceiptVerifying {
    let actions: LockedInstallActions

    func verify(expected manifest: RuntimePackageManifest) async throws -> InstalledPackageReceipt {
        try actions.stage(.receiptVerification)
        return .init(
            identifier: manifest.receiptIdentifier,
            version: manifest.runtimeVersion,
            installLocation: manifest.installLocation
        )
    }
}

private struct RecordingPayloadVerifier: InstalledPayloadVerifying {
    let actions: LockedInstallActions

    func verify(expected _: RuntimePackageManifest) async throws {
        try actions.stage(.payloadVerification)
    }
}

private struct RecordingInstallServiceController: InstallServiceControlling {
    let actions: LockedInstallActions

    func startRuntime() async throws {
        try actions.stage(.serviceStart)
    }
}

private struct RecordingInstallKernelEnsurer: InstallKernelEnsuring {
    let actions: LockedInstallActions

    func ensureKernel(for _: RuntimeInstallTarget) async throws {
        try actions.stage(.kernelEnsure)
    }
}

private struct RecordingInstallProbeRunner: InstallProbeRunning {
    let actions: LockedInstallActions

    func run(probes _: [String]) async throws {
        try actions.stage(.probeRun)
    }
}

private struct RecordingPartialUninstaller: PartialInstallUninstalling {
    let actions: LockedInstallActions

    func removePartialInstall(manifest _: RuntimePackageManifest) async throws {
        actions.append("uninstall.partial")
    }
}

private struct RecordingPartialResidueAuditor: PartialInstallResidueAuditing {
    let actions: LockedInstallActions
    let result: PartialInstallAudit

    func audit(manifest _: RuntimePackageManifest) async throws -> PartialInstallAudit {
        actions.append("residue.audit")
        return result
    }
}

private enum InstallFixtureError: Error {
    case injected(InstallStage)
}

private extension RuntimeInstallTarget {
    static let testTarget = Self(
        manifest: .installFixture,
        releaseAPIURL: URL(string: "https://api.github.com/repos/apple/container/releases/tags/1.1.0")!,
        requiredProbes: ["service.health", "images.decode"]
    )
}

private extension RuntimePackageManifest {
    static let installFixture = Self(
        runtimeVersion: "1.1.0",
        assetName: "container-1.1.0-installer-signed.pkg",
        sha256: "0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714",
        installerTeamID: "UPBK2H6LZM",
        signerCommonName: "Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)",
        receiptIdentifier: "com.apple.container-installer",
        installLocation: "/usr/local",
        payload: [.init(relativePath: "bin", kind: .directory)]
    )
}
