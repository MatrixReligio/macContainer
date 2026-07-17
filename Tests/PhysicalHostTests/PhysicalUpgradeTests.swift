import Foundation
import MCCompatibility
import MCContainerBridge
import MCSystemLifecycle
import Testing

@Suite(
    "Authorized physical automatic upgrade and rollback",
    .serialized,
    .enabled(
        if: PhysicalTestGate.isAuthorized && PhysicalTestGate.phase == "upgrade-rollback",
        "Exact upgrade authorization, phase, and packages are required"
    )
)
struct PhysicalUpgradeTests {
    @Test func `reviewed 100 to 110 upgrade postflight and rollback are physical`() async throws {
        let package100 = try PhysicalTestGate.packageURL(version: "1.0.0")
        let package110 = try PhysicalTestGate.packageURL(version: "1.1.0")
        let stateRoot = try PhysicalTestGate.upgradeStateRoot()
        let bridge = try PhysicalTestGate.productionBridge()
        let helper = PhysicalSignedAppInstallHelper()
        let verifier = RuntimePackageVerifier.system
        let verified100 = try await verifier.verify(
            packageAt: package100,
            against: ReviewedRuntime100Manifest.package
        )
        _ = try await helper.install(verified100)
        try await verifyInstalled(
            manifest: ReviewedRuntime100Manifest.package,
            bridge: bridge,
            start: true
        )
        try PhysicalTestGate.record("upgrade.install-1.0.0")

        let target = try reviewedTarget(packageURL: package110)
        let configuration = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/container", isDirectory: true)
            .standardizedFileURL
        #expect(!FileManager.default.fileExists(atPath: configuration.path))
        let context = try makeContext(.init(
            stateRoot: stateRoot,
            package100: package100,
            package110: package110,
            configuration: configuration,
            bridge: bridge,
            helper: helper
        ))

        let first = try await context.transaction(probes: context.probes).upgrade(to: target)
        #expect(first.previousRuntimeVersion == "1.0.0")
        #expect(first.runtimeVersion == "1.1.0")
        try await verifyInstalled(
            manifest: ReviewedRuntime110Manifest.package,
            bridge: bridge,
            start: false
        )
        try PhysicalTestGate.record("upgrade.automatic-1.1.0", "upgrade.compatibility-probes")

        try await context.services.stopRuntime()
        _ = try await helper.install(verified100)
        try await context.services.startRuntime(expectedVersion: "1.0.0")
        let blocker = PhysicalUpgradeBlocker()
        let injected = context.transaction(
            probes: InjectedTargetFailureProbeRunner(base: context.probes),
            blocker: blocker
        )
        await #expect(throws: UpgradeError.rolledBack) {
            try await injected.upgrade(to: target)
        }
        #expect(await blocker.blockedVersions == ["1.1.0"])
        try PhysicalTestGate.record("upgrade.injected-postflight-failure")
        try await verifyInstalled(
            manifest: ReviewedRuntime100Manifest.package,
            bridge: bridge,
            start: false
        )
        try await context.probes.run(
            probes: ProbeID.baselineAllCases.map(\.rawValue),
            runtimeVersion: "1.0.0"
        )
        try PhysicalTestGate.record("upgrade.rollback-1.0.0")

        let final = try await context.transaction(probes: context.probes).upgrade(to: target)
        #expect(final.runtimeVersion == "1.1.0")
        try await verifyInstalled(
            manifest: ReviewedRuntime110Manifest.package,
            bridge: bridge,
            start: false
        )

        let entry = try #require(try CompatibilityCatalog.bundled().entries.first)
        let unknown = try RuntimeReleaseCandidate(
            version: "9.9.9",
            packageURL: #require(URL(string:
                "https://github.com/apple/container/releases/download/9.9.9/container-9.9.9-installer-signed.pkg")),
            packageSHA256: String(repeating: "9", count: 64)
        )
        await #expect(throws: ProductionUpgradeComponentError.packageIdentityMismatch) {
            try await ReviewedAutomaticUpdatePackageVerifier().verify(
                candidate: unknown,
                entry: entry
            )
        }
        #expect(try await bridge.system.version().version == "1.1.0")
        try PhysicalTestGate.record("upgrade.unknown-version-hold")
    }

    private func reviewedTarget(packageURL: URL) throws -> RuntimeUpgradeTarget {
        let entry = try #require(try CompatibilityCatalog.bundled().entries.first)
        return RuntimeUpgradeTarget(
            installTarget: RuntimeInstallTarget(
                manifest: ReviewedRuntime110Manifest.package,
                releaseAPIURL: packageURL,
                requiredProbes: entry.requiredProbeIDs
            ),
            requiresFullDataRollback: entry.rollback == .fullDataClone,
            destroysStorageCompatibility: entry.storageMigration == .destructive
        )
    }

    private func makeContext(_ input: PhysicalUpgradeInput) throws -> PhysicalUpgradeContext {
        let entry = try #require(try CompatibilityCatalog.bundled().entries.first)
        let previousTarget = RuntimeInstallTarget(
            manifest: ReviewedRuntime100Manifest.package,
            releaseAPIURL: input.package100,
            requiredProbes: entry.allowedUpgradeSources[0].requiredPreflightProbeIDs
        )
        let rollback = RollbackStore(
            rootDirectory: input.stateRoot.appendingPathComponent("rollback", isDirectory: true),
            packageVerifier: RuntimePackageVerifier.system,
            sourcePolicy: RollbackSourcePolicy(
                previousPackageRoots: [input.package100.deletingLastPathComponent()],
                configurationAndMetadataPaths: [input.configuration],
                fullDataPaths: []
            )
        )
        let probes = BridgeUpgradeProbeRunner(
            bridge: input.bridge,
            enabledCapabilityIDs: entry.capabilityIDs
        )
        return PhysicalUpgradeContext(
            packagePreparer: PhysicalLocalPackagePreparer(packageURL: input.package110),
            baseline: SystemUpgradeBaselineCapture(
                previousTarget: previousTarget,
                previousPackageURL: input.package100,
                configurationAndMetadata: [input.configuration],
                fullData: []
            ),
            previousVerifier: SystemPreviousRuntimePackageVerifier(),
            rollback: rollback,
            workloads: BridgeUpgradeWorkObserver(bridge: input.bridge),
            services: BridgeUpgradeServiceController(bridge: input.bridge),
            helper: input.helper,
            installedVerifier: SystemUpgradeInstalledRuntimeVerifier(bridge: input.bridge),
            probes: probes,
            journal: LifecycleUpgradeJournalWriter(journal: LifecycleJournal(
                storage: JSONLineLifecycleJournalStorage(
                    fileURL: input.stateRoot.appendingPathComponent("journal.jsonl")
                )
            )),
            diagnostics: PhysicalUpgradeDiagnostics()
        )
    }

    private func verifyInstalled(
        manifest: RuntimePackageManifest,
        bridge: AppleRuntimeBridge,
        start: Bool
    ) async throws {
        _ = try await SystemInstalledReceiptVerifier().verify(expected: manifest)
        try await SystemInstalledPayloadVerifier().verify(expected: manifest)
        if start {
            try await BridgeUpgradeServiceController(bridge: bridge)
                .startRuntime(expectedVersion: manifest.runtimeVersion)
        }
        let version = try await bridge.system.version()
        #expect(version.version == manifest.runtimeVersion)
        #expect(version.apiVersion == manifest.runtimeVersion)
    }
}

private struct PhysicalUpgradeInput {
    let stateRoot: URL
    let package100: URL
    let package110: URL
    let configuration: URL
    let bridge: AppleRuntimeBridge
    let helper: any UpgradePrivilegedHelping
}

private struct PhysicalUpgradeContext: Sendable {
    let packagePreparer: PhysicalLocalPackagePreparer
    let baseline: SystemUpgradeBaselineCapture
    let previousVerifier: SystemPreviousRuntimePackageVerifier
    let rollback: RollbackStore
    let workloads: BridgeUpgradeWorkObserver
    let services: BridgeUpgradeServiceController
    let helper: any UpgradePrivilegedHelping
    let installedVerifier: SystemUpgradeInstalledRuntimeVerifier
    let probes: BridgeUpgradeProbeRunner
    let journal: LifecycleUpgradeJournalWriter
    let diagnostics: PhysicalUpgradeDiagnostics

    func transaction(
        probes selectedProbes: any UpgradeProbeRunning,
        blocker: any UpgradeTargetBlocking = PhysicalUpgradeBlocker()
    ) -> UpgradeTransaction {
        UpgradeTransaction(
            packagePreparer: packagePreparer,
            baselineCapture: baseline,
            previousPackageVerifier: previousVerifier,
            rollback: rollback,
            workloads: workloads,
            services: services,
            helper: helper,
            installedRuntimeVerifier: installedVerifier,
            probes: selectedProbes,
            journal: journal,
            blocker: blocker,
            diagnostics: diagnostics,
            downgradeConsent: PhysicalDowngradeConsent()
        )
    }
}

private struct PhysicalLocalPackagePreparer: UpgradePackagePreparing, Sendable {
    let packageURL: URL

    func prepare(_ target: RuntimeUpgradeTarget) async throws -> PreparedUpgradePackage {
        guard target.installTarget.manifest == ReviewedRuntime110Manifest.package else {
            throw PhysicalUpgradeFailure.targetMismatch
        }
        let package = try await RuntimePackageVerifier.system.verify(
            packageAt: packageURL,
            against: target.installTarget.manifest
        )
        return PreparedUpgradePackage(package: package) {}
    }
}

private struct InjectedTargetFailureProbeRunner: UpgradeProbeRunning, Sendable {
    let base: BridgeUpgradeProbeRunner

    func run(probes: [String], runtimeVersion: String) async throws {
        if runtimeVersion == "1.1.0" {
            throw PhysicalUpgradeFailure.injectedPostflight
        }
        try await base.run(probes: probes, runtimeVersion: runtimeVersion)
    }
}

private actor PhysicalUpgradeBlocker: UpgradeTargetBlocking {
    private(set) var blockedVersions: [String] = []

    func block(version: String, failureCode _: String) {
        blockedVersions.append(version)
    }
}

private actor PhysicalUpgradeDiagnostics: UpgradeDiagnosticPersisting {
    func persist(_: RedactedLifecycleFailure) {}
}

private struct PhysicalDowngradeConsent: UpgradeDowngradeConsentProviding {
    func approve(_: DowngradeConsentRequest) async -> Bool {
        false
    }
}

private enum PhysicalUpgradeFailure: Error {
    case injectedPostflight
    case targetMismatch
}
