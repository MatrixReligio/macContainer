import Foundation
import MCCompatibility
import MCContainerBridge
import MCModel

public struct ReviewedAutomaticUpdatePackageVerifier: AutomaticUpdatePackageVerifying, Sendable {
    public init() {}

    public func verify(
        candidate: RuntimeReleaseCandidate,
        entry: CompatibilityEntry
    ) async throws -> RuntimeUpgradeTarget {
        let manifest = ReviewedRuntime110Manifest.package
        let expectedPath = "/apple/container/releases/download/\(entry.runtimeVersion)/\(entry.package.assetName)"
        guard
            entry.runtimeVersion == manifest.runtimeVersion,
            entry.package.runtimeVersion == manifest.runtimeVersion,
            entry.package.assetName == manifest.assetName,
            entry.package.sha256 == manifest.sha256,
            entry.package.installerTeamID == manifest.installerTeamID,
            entry.package.signerCommonName == manifest.signerCommonName,
            entry.package.receiptIdentifier == manifest.receiptIdentifier,
            candidate.version == entry.runtimeVersion,
            candidate.packageSHA256 == entry.package.sha256,
            candidate.packageURL.scheme == "https",
            candidate.packageURL.host == "github.com",
            candidate.packageURL.path == expectedPath,
            candidate.packageURL.query == nil,
            candidate.packageURL.fragment == nil
        else {
            throw ProductionUpgradeComponentError.packageIdentityMismatch
        }
        return RuntimeUpgradeTarget(
            installTarget: RuntimeInstallTarget(
                manifest: manifest,
                releaseAPIURL: candidate.packageURL,
                requiredProbes: entry.requiredProbeIDs
            ),
            requiresFullDataRollback: entry.rollback == .fullDataClone,
            destroysStorageCompatibility: entry.storageMigration == .destructive
        )
    }
}

public struct SystemUpgradePackagePreparer: UpgradePackagePreparing, Sendable {
    private let downloader: any RuntimePackageDownloading
    private let verifier: any InstallRuntimePackageVerifying
    private let temporaryDirectories: any InstallTemporaryDirectoryProviding

    public init(
        downloader: any RuntimePackageDownloading = SystemRuntimePackageDownloader(),
        verifier: any InstallRuntimePackageVerifying = RuntimePackageVerifier.system,
        temporaryDirectories: any InstallTemporaryDirectoryProviding = LocalInstallTemporaryDirectoryProvider()
    ) {
        self.downloader = downloader
        self.verifier = verifier
        self.temporaryDirectories = temporaryDirectories
    }

    public func prepare(_ target: RuntimeUpgradeTarget) async throws -> PreparedUpgradePackage {
        let manifest = target.installTarget.manifest
        let source = target.installTarget.releaseAPIURL
        guard source.scheme == "https",
              source.host == "github.com",
              source.lastPathComponent == manifest.assetName,
              source.query == nil,
              source.fragment == nil
        else {
            throw ProductionUpgradeComponentError.packageIdentityMismatch
        }
        let temporary = try temporaryDirectories.create(transactionID: UUID())
        do {
            let destination = temporary.url.appendingPathComponent(manifest.assetName)
            try await downloader.download(
                RuntimeReleaseAsset(name: manifest.assetName, downloadURL: source),
                to: destination
            )
            let package = try await verifier.verify(packageAt: destination, against: manifest)
            return PreparedUpgradePackage(package: package) {
                try temporary.cleanup()
            }
        } catch {
            try? temporary.cleanup()
            throw error
        }
    }
}

public struct SystemUpgradeBaselineCapture: UpgradeBaselineCapturing, Sendable {
    private let previousTarget: RuntimeInstallTarget
    private let previousPackageURL: URL
    private let configurationAndMetadata: [URL]
    private let fullData: [URL]

    public init(
        previousTarget: RuntimeInstallTarget,
        previousPackageURL: URL,
        configurationAndMetadata: [URL],
        fullData: [URL]
    ) {
        self.previousTarget = previousTarget
        self.previousPackageURL = previousPackageURL.standardizedFileURL
        self.configurationAndMetadata = configurationAndMetadata.map(\.standardizedFileURL)
        self.fullData = fullData.map(\.standardizedFileURL)
    }

    public func capture() async throws -> UpgradeBaseline {
        let optionalNodes = configurationAndMetadata + fullData
        guard previousTarget.manifest == ReviewedRuntime100Manifest.package,
              previousPackageURL.isFileURL,
              !configurationAndMetadata.isEmpty,
              FileManager.default.fileExists(atPath: previousPackageURL.path),
              ([previousPackageURL] + optionalNodes).allSatisfy({
                  $0.isFileURL && $0.path.hasPrefix("/")
              }),
              optionalNodes.allSatisfy(Self.isSafePresentOrAbsentNode),
              Set(([previousPackageURL] + configurationAndMetadata + fullData).map(\.path)).count ==
              1 + configurationAndMetadata.count + fullData.count
        else {
            throw ProductionUpgradeComponentError.invalidBaseline
        }
        return UpgradeBaseline(
            previousTarget: previousTarget,
            previousPackageURL: previousPackageURL,
            configurationAndMetadata: configurationAndMetadata,
            fullData: fullData
        )
    }

    private static func isSafePresentOrAbsentNode(_ url: URL) -> Bool {
        var status = stat()
        guard Darwin.lstat(url.path, &status) == 0 else {
            return errno == ENOENT || errno == ENOTDIR
        }
        let kind = status.st_mode & S_IFMT
        return status.st_uid == geteuid() && (kind == S_IFREG || kind == S_IFDIR)
    }
}

public struct SystemPreviousRuntimePackageVerifier: PreviousRuntimePackageVerifying, Sendable {
    private let verifier: any InstallRuntimePackageVerifying

    public init(verifier: any InstallRuntimePackageVerifying = RuntimePackageVerifier.system) {
        self.verifier = verifier
    }

    public func verify(_ baseline: UpgradeBaseline) async throws -> VerifiedRuntimePackage {
        try await verifier.verify(
            packageAt: baseline.previousPackageURL,
            against: baseline.previousTarget.manifest
        )
    }
}

public struct SystemUpgradeInstalledRuntimeVerifier: UpgradeInstalledRuntimeVerifying, Sendable {
    private let receipts: PackageReceiptReader
    private let payload: any InstalledPayloadVerifying
    private let bridge: any RuntimeBridge

    public init(
        receipts: PackageReceiptReader = PackageReceiptReader(backend: SystemPackageReceiptBackend()),
        payload: any InstalledPayloadVerifying = SystemInstalledPayloadVerifier(),
        bridge: any RuntimeBridge = AppleRuntimeBridge()
    ) {
        self.receipts = receipts
        self.payload = payload
        self.bridge = bridge
    }

    public func verify(target: RuntimeUpgradeTarget) async throws -> UpgradeVersionAgreement {
        let manifest = target.installTarget.manifest
        guard let receipt = try await receipts.readReviewedRuntimeReceipt(
            identifier: manifest.receiptIdentifier
        ), receipt.version == manifest.runtimeVersion,
        receipt.installLocation == manifest.installLocation
        else {
            throw ProductionUpgradeComponentError.versionAgreementMismatch
        }
        try await payload.verify(expected: manifest)
        let version = try await bridge.system.version()
        guard let apiVersion = version.apiVersion else {
            throw ProductionUpgradeComponentError.versionAgreementMismatch
        }
        return UpgradeVersionAgreement(
            receipt: receipt.version,
            payload: manifest.runtimeVersion,
            binary: version.version,
            api: apiVersion
        )
    }
}

public struct BridgeUpgradeWorkObserver: UpgradeWorkObserving, Sendable {
    private let bridge: any RuntimeBridge

    public init(bridge: any RuntimeBridge) {
        self.bridge = bridge
    }

    public func activeWork() async throws -> [String] {
        async let containers = bridge.containers.list()
        async let machines = bridge.machines.list()
        async let builder = bridge.builders.status()
        var work = try await containers.filter { Self.isActive($0.state) }
            .map { "container:\($0.id)" }
        work += try await machines.filter { Self.isActive($0.state) }
            .map { "machine:\($0.id)" }
        if try await Self.isActive(builder.state) {
            work.append("builder")
        }
        return work.sorted()
    }

    private static func isActive(_ state: RuntimeResourceState) -> Bool {
        switch state {
        case .stopped: false
        case .starting, .running, .stopping, .failed, .unknown: true
        }
    }
}

public struct BridgeUpgradeServiceController: UpgradeServiceControlling, Sendable {
    private let bridge: any RuntimeBridge

    public init(bridge: any RuntimeBridge) {
        self.bridge = bridge
    }

    public func stopRuntime() async throws {
        let status = try await bridge.system.stop(.init(
            stopActiveWorkloads: false,
            timeoutSeconds: 60
        ))
        guard status.state == .stopped else {
            throw ProductionUpgradeComponentError.serviceTransitionFailed
        }
    }

    public func startRuntime(expectedVersion: String) async throws {
        let status = try await bridge.system.start(.init(healthTimeoutSeconds: 60))
        let version = try await bridge.system.version()
        guard status.state == .running,
              version.version == expectedVersion,
              version.apiVersion == expectedVersion
        else {
            throw ProductionUpgradeComponentError.serviceTransitionFailed
        }
    }
}

public struct BridgeUpgradeProbeRunner: UpgradeProbeRunning, Sendable {
    private let bridge: any RuntimeBridge
    private let enabledCapabilityIDs: Set<String>
    private let registry: ProbeRegistry

    public init(
        bridge: any RuntimeBridge,
        enabledCapabilityIDs: Set<String>,
        registry: ProbeRegistry = ProbeRegistry()
    ) {
        self.bridge = bridge
        self.enabledCapabilityIDs = enabledCapabilityIDs
        self.registry = registry
    }

    public func run(probes: [String], runtimeVersion: String) async throws {
        guard probes == ProbeID.baselineAllCases.map(\.rawValue),
              !enabledCapabilityIDs.isEmpty
        else {
            throw ProductionUpgradeComponentError.invalidProbeSet
        }
        let report = await registry.runAll(context: .init(
            bridge: bridge,
            expectedRuntimeVersion: runtimeVersion,
            expectedCapabilityIDs: enabledCapabilityIDs,
            enabledCapabilityIDs: enabledCapabilityIDs,
            phase: .postflight
        ))
        guard report.isCompatible else {
            throw ProductionUpgradeComponentError.postflightFailed
        }
    }
}

public enum ProductionUpgradeComponentError: Error, Equatable, Sendable {
    case invalidBaseline
    case invalidProbeSet
    case packageIdentityMismatch
    case postflightFailed
    case serviceTransitionFailed
    case versionAgreementMismatch
}
