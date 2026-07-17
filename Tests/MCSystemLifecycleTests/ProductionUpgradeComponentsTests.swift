import Darwin
import Foundation
import MCCompatibility
@testable import MCSystemLifecycle
import Testing
import TestSupport

@Suite("Production upgrade components")
struct ProductionUpgradeComponentsTests {
    @Test func `package preparer downloads verifies and cleans one private package`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mc-upgrade-prepare-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let cleanup = UpgradeCleanupRecorder(root: root)
        let downloader = UpgradeFixtureDownloader()
        let verifier = UpgradeFixtureVerifier()
        let preparer = SystemUpgradePackagePreparer(
            downloader: downloader,
            verifier: verifier,
            temporaryDirectories: UpgradeFixtureTemporaryDirectoryProvider(root: root, cleanup: cleanup)
        )
        let target = try RuntimeUpgradeTarget(
            installTarget: RuntimeInstallTarget(
                manifest: ReviewedRuntime110Manifest.package,
                releaseAPIURL: #require(URL(string:
                    "https://github.com/apple/container/releases/download/1.1.0/container-1.1.0-installer-signed.pkg")),
                requiredProbes: ["health"]
            ),
            requiresFullDataRollback: false,
            destroysStorageCompatibility: false
        )

        let prepared = try await preparer.prepare(target)
        #expect(downloader.calls == 1)
        #expect(verifier.calls == 1)
        #expect(prepared.package.sha256 == ReviewedRuntime110Manifest.package.sha256)

        try prepared.cleanup()
        #expect(cleanup.calls == 1)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func `baseline keeps exact reviewed previous package and configuration`() async throws {
        let root = try makePrivateRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("container-1.0.0-installer-signed.pkg")
        let configuration = root.appendingPathComponent("configuration", isDirectory: true)
        try Data("package".utf8).write(to: package)
        try FileManager.default.createDirectory(at: configuration, withIntermediateDirectories: false)

        let capture = SystemUpgradeBaselineCapture(
            previousTarget: RuntimeInstallTarget(
                manifest: ReviewedRuntime100Manifest.package,
                releaseAPIURL: package,
                requiredProbes: ["health"]
            ),
            previousPackageURL: package,
            configurationAndMetadata: [configuration],
            fullData: []
        )
        let baseline = try await capture.capture()

        #expect(baseline.previousTarget.manifest == ReviewedRuntime100Manifest.package)
        #expect(baseline.previousPackageURL == package.standardizedFileURL)
        #expect(baseline.configurationAndMetadata == [configuration.standardizedFileURL])
    }

    @Test func `installed verifier requires receipt payload binary and API agreement`() async throws {
        let manifest = ReviewedRuntime110Manifest.package
        let verifier = SystemUpgradeInstalledRuntimeVerifier(
            receipts: PackageReceiptReader(backend: UpgradeFixtureReceiptBackend(receipt: .init(
                identifier: manifest.receiptIdentifier,
                version: manifest.runtimeVersion,
                installLocation: manifest.installLocation
            ))),
            payload: UpgradeFixturePayloadVerifier(),
            bridge: FakeRuntimeBridge(
                runtimeVersion: manifest.runtimeVersion,
                apiVersion: manifest.runtimeVersion
            )
        )
        let target = try RuntimeUpgradeTarget(
            installTarget: RuntimeInstallTarget(
                manifest: manifest,
                releaseAPIURL: #require(URL(string:
                    "https://github.com/apple/container/releases/download/1.1.0/\(manifest.assetName)")),
                requiredProbes: ["health"]
            ),
            requiresFullDataRollback: false,
            destroysStorageCompatibility: false
        )

        #expect(try await verifier.verify(target: target).agrees(with: "1.1.0"))
    }

    @Test func `bridge upgrade gates require idle work and complete postflight probes`() async throws {
        let bridge = FakeRuntimeBridge(
            runtimeVersion: "1.1.0",
            apiVersion: "1.1.0",
            systemState: .running
        )
        #expect(try await BridgeUpgradeWorkObserver(bridge: bridge).activeWork().isEmpty)

        let services = BridgeUpgradeServiceController(bridge: bridge)
        try await services.stopRuntime()
        try await services.startRuntime(expectedVersion: "1.1.0")

        try await BridgeUpgradeProbeRunner(
            bridge: bridge,
            enabledCapabilityIDs: #require(try CompatibilityCatalog.bundled().entries.first).capabilityIDs
        ).run(
            probes: ProbeID.baselineAllCases.map(\.rawValue),
            runtimeVersion: "1.1.0"
        )
        let operations = await bridge.recordedInvocations().map(\.operationID)
        #expect(operations.contains("system.stop"))
        #expect(operations.contains("system.start"))
        #expect(operations.contains("configuration.validate"))
    }

    private func makePrivateRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mc-upgrade-baseline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return root
    }
}

private final class UpgradeCleanupRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let root: URL
    private var count = 0

    init(root: URL) {
        self.root = root
    }

    var calls: Int {
        lock.withLock { count }
    }

    func remove() throws {
        try lock.withLock {
            try FileManager.default.removeItem(at: root)
            count += 1
        }
    }
}

private struct UpgradeFixtureTemporaryDirectoryProvider: InstallTemporaryDirectoryProviding {
    let root: URL
    let cleanup: UpgradeCleanupRecorder

    func create(transactionID _: UUID) -> InstallTemporaryDirectory {
        InstallTemporaryDirectory(url: root, cleanup: cleanup.remove)
    }
}

private final class UpgradeFixtureDownloader: RuntimePackageDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int {
        lock.withLock { count }
    }

    func download(_: RuntimeReleaseAsset, to destination: URL) async throws {
        try Data("package".utf8).write(to: destination, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        lock.withLock { count += 1 }
    }
}

private final class UpgradeFixtureVerifier: InstallRuntimePackageVerifying, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int {
        lock.withLock { count }
    }

    func verify(
        packageAt url: URL,
        against manifest: RuntimePackageManifest
    ) async throws -> VerifiedRuntimePackage {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        defer { Darwin.close(descriptor) }
        let file = try OpenRuntimePackageFile(duplicating: descriptor)
        lock.withLock { count += 1 }
        return VerifiedRuntimePackage(
            runtimeVersion: manifest.runtimeVersion,
            sha256: manifest.sha256,
            installerTeamID: manifest.installerTeamID,
            signerCommonName: manifest.signerCommonName,
            receiptIdentifier: manifest.receiptIdentifier,
            installLocation: manifest.installLocation,
            payload: manifest.payload,
            openFile: file
        )
    }
}

private struct UpgradeFixtureReceiptBackend: PackageReceiptReading {
    let receipt: InstalledPackageReceipt?

    func receipt(identifier _: String) async throws -> InstalledPackageReceipt? {
        receipt
    }
}

private struct UpgradeFixturePayloadVerifier: InstalledPayloadVerifying {
    func verify(expected _: RuntimePackageManifest) async throws {}
}
