import CryptoKit
import Darwin
import Foundation
import MCCompatibility
import MCContainerBridge
import MCModel
@testable import MCSystemLifecycle
import Testing
import TestSupport

@Suite("Production automatic update components")
struct ProductionAutomaticUpdateComponentsTests {
    @Test func `bundled provider verifies exact signed evidence once and caches it`() async throws {
        let fixture = try PhysicalAttestationProviderFixture()
        let replay = CountingReplayStore()
        let provider = BundledPhysicalAttestationIDProvider(
            materialProvider: FixedPhysicalAttestationMaterialProvider(material: fixture.material),
            identityProvider: FixedPhysicalApplicationIdentityProvider(identity: fixture.identity),
            trustedSigners: [fixture.signer],
            replayStore: replay,
            now: { fixture.now }
        )

        #expect(await provider.verifiedIDs(for: fixture.entry) == [fixture.entry.attestation.id])
        #expect(await provider.verifiedIDs(for: fixture.entry) == [fixture.entry.attestation.id])
        #expect(await replay.acceptedCount == 1)
    }

    @Test func `bundled provider fails closed for identity mismatch or missing material`() async throws {
        let fixture = try PhysicalAttestationProviderFixture()
        let mismatch = PhysicalAttestationApplicationIdentity(
            bundleIdentifier: fixture.identity.bundleIdentifier,
            version: fixture.identity.version,
            build: fixture.identity.build,
            designatedRequirementHash: String(repeating: "b", count: 64)
        )
        let mismatched = BundledPhysicalAttestationIDProvider(
            materialProvider: FixedPhysicalAttestationMaterialProvider(material: fixture.material),
            identityProvider: FixedPhysicalApplicationIdentityProvider(identity: mismatch),
            trustedSigners: [fixture.signer],
            replayStore: InMemoryAttestationReplayStore(),
            now: { fixture.now }
        )
        let missing = BundledPhysicalAttestationIDProvider(
            materialProvider: FixedPhysicalAttestationMaterialProvider(material: nil),
            identityProvider: FixedPhysicalApplicationIdentityProvider(identity: fixture.identity),
            trustedSigners: [fixture.signer],
            replayStore: InMemoryAttestationReplayStore(),
            now: { fixture.now }
        )

        #expect(await mismatched.verifiedIDs(for: fixture.entry).isEmpty)
        #expect(await missing.verifiedIDs(for: fixture.entry).isEmpty)
    }

    @Test func `context binds installed source policy authorization activity and attestation`() async throws {
        let catalog = try CompatibilityCatalog.bundled()
        let entry = try #require(catalog.entry(runtimeVersion: "1.1.0"))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainerAutomaticContextTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = SystemAutomaticUpdateContextProvider(
            catalogProvider: FixedCatalogProvider(catalog: catalog),
            appVersion: "0.1.0",
            hostProvider: FixedHostProvider(profile: .init(
                logicalCPUs: 8,
                physicalMemoryBytes: 16 * 1024 * 1024 * 1024,
                chip: .appleSilicon,
                macOSMajor: 26,
                capabilities: []
            )),
            targetResolver: FixedInstalledTargetResolver(target: .reviewedRuntime100),
            preferences: FixedUpdatePreferencesPersistence(value: .init(
                automaticallyChecks: true,
                mode: .automaticWhenIdle,
                consentVersion: RuntimeUpdatePolicy.currentConsentVersion
            )),
            registrar: FixedUpdateHelperRegistrar(status: .enabled),
            activityProvider: FixedRuntimeActivityProvider(value: .init(activeContainers: 1)),
            attestationProvider: FixedAttestationProvider(ids: [entry.attestation.id]),
            blockedVersions: BlockedVersionStore(fileURL: root.appendingPathComponent("blocked.json")),
            bridge: FakeRuntimeBridge()
        )
        let candidate = try RuntimeReleaseCandidate(
            version: entry.runtimeVersion,
            packageURL: #require(URL(string: "https://github.com/apple/container/releases/download/1.1.0/\(entry.package.assetName)")),
            packageSHA256: entry.package.sha256
        )

        let context = try await provider.context(for: candidate)

        #expect(context.catalog == catalog)
        #expect(context.appVersion == "0.1.0")
        #expect(context.installedRuntimeVersion == "1.0.0")
        #expect(context.installedPackageSHA256 == ReviewedRuntime100Manifest.package.sha256)
        #expect(context.verifiedAttestationIDs == [entry.attestation.id])
        #expect(context.mode == .automaticWhenIdle)
        #expect(context.consentVersion == RuntimeUpdatePolicy.currentConsentVersion)
        #expect(context.helperAuthorized)
        #expect(context.activity.activeContainers == 1)
        #expect(context.enabledCapabilityIDs == entry.capabilityIDs)
    }

    @Test func `rollback availability re-verifies exact previous package baseline`() async throws {
        let baseline = UpgradeBaseline(
            previousTarget: .reviewed100,
            previousPackageURL: URL(fileURLWithPath: "/tmp/reviewed-1.0.pkg"),
            configurationAndMetadata: [URL(fileURLWithPath: "/tmp/config")],
            fullData: []
        )
        let capture = FixedAutomaticBaselineCapture(baseline: baseline)
        let verifier = RecordingPreviousPackageVerifier()
        let checker = SystemRollbackAvailabilityChecker(
            baselineCapture: capture,
            previousPackageVerifier: verifier
        )

        await #expect(throws: RecordingAutomaticComponentError.expectedVerificationStop) {
            try await checker.check(target: .reviewed110)
        }

        #expect(await verifier.verifiedURLs == [baseline.previousPackageURL])
    }

    @Test func `reviewed target blocker durably records the attestation gate`() async throws {
        let catalog = try CompatibilityCatalog.bundled()
        let entry = try #require(catalog.entry(runtimeVersion: "1.1.0"))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainerReviewedBlockerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BlockedVersionStore(fileURL: root.appendingPathComponent("blocked.json"))
        let blocker = ReviewedUpgradeTargetBlocker(
            entry: entry,
            catalogRevision: catalog.revision,
            appVersion: "0.1.0",
            store: store,
            now: { Date(timeIntervalSince1970: 123) }
        )

        try await blocker.block(version: "1.1.0", failureCode: "upgrade.probes.run")

        let record = try #require(try await store.record(for: "1.1.0"))
        #expect(record.attestationID == entry.attestation.id)
        #expect(record.catalogRevision == catalog.revision)
        #expect(record.timestamp == Date(timeIntervalSince1970: 123))
    }

    @Test func `diagnostic recorder stores only redacted failure in private file`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainerUpgradeDiagnosticTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Updates", isDirectory: true)
            .appendingPathComponent("upgrade-diagnostics.json")
        let recorder = PrivateUpgradeDiagnosticStore(fileURL: file)

        try await recorder.persist(.init(code: "upgrade.probes.run", redactedDetail: "stage-failed"))

        let records = try await recorder.records()
        #expect(records.map(\.failure.code) == ["upgrade.probes.run"])
        #expect(filePermissions(file) == 0o600)
    }

    @Test func `production coordinator factory composes the reviewed upgrade path`() throws {
        _ = try ProductionUpdateCoordinatorFactory.make(
            stateSink: FixedRuntimeUpdateStateSink(),
            bridge: FakeRuntimeBridge(),
            registrar: FixedUpdateHelperRegistrar(status: .enabled),
            preferences: FixedUpdatePreferencesPersistence(value: .safeDefaults),
            attestationProvider: FailClosedPhysicalAttestationIDProvider()
        )
    }
}

private struct PhysicalAttestationProviderFixture {
    let entry: CompatibilityEntry
    let identity: PhysicalAttestationApplicationIdentity
    let signer: TrustedAttestationSigner
    let material: PhysicalAttestationMaterial
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let catalog = try CompatibilityCatalog.bundled()
        entry = try #require(catalog.entry(runtimeVersion: "1.1.0"))
        identity = PhysicalAttestationApplicationIdentity(
            bundleIdentifier: "container.matrixreligio.com",
            version: "0.1.0",
            build: "1",
            designatedRequirementHash: String(repeating: "a", count: 64)
        )
        let privateKey = P256.Signing.PrivateKey()
        let publicKey = privateKey.publicKey.derRepresentation
        signer = TrustedAttestationSigner(
            keyID: "test-provider-key",
            publicKeyDERBase64: publicKey.base64EncodedString(),
            publicKeySHA256: SHA256.hash(data: publicKey).map { String(format: "%02x", $0) }.joined()
        )
        let unsigned = PhysicalTestAttestation(
            schemaVersion: 1,
            nonce: UUID(),
            issuedAt: now.addingTimeInterval(-60),
            sourceCommit: entry.attestation.sourceCommit,
            appBundleIdentifier: identity.bundleIdentifier,
            appVersion: identity.version,
            appBuild: identity.build,
            appDesignatedRequirementHash: identity.designatedRequirementHash,
            runtimeVersion: entry.runtimeVersion,
            runtimePackageSHA256: entry.package.sha256,
            testPlanVersion: entry.attestation.testPlanVersion,
            hostModel: "MacFixture",
            macOSBuild: "26AFixture",
            operationResults: ["system.status": true],
            residueCount: 0,
            baselineRestored: true,
            cleanupLedgerEmpty: true,
            signerKeyID: signer.keyID,
            signature: ""
        )
        let signature = try privateKey.signature(for: unsigned.canonicalSigningData())
        material = try PhysicalAttestationMaterial(
            attestationData: unsigned.replacing(
                signature: signature.derRepresentation.base64EncodedString()
            ).encoded(),
            requiredOperationIDs: ["system.status"]
        )
    }
}

private struct FixedPhysicalAttestationMaterialProvider: PhysicalAttestationMaterialProviding {
    let material: PhysicalAttestationMaterial?
    func material(for _: CompatibilityEntry) throws -> PhysicalAttestationMaterial? {
        material
    }
}

private struct FixedPhysicalApplicationIdentityProvider: PhysicalAppIdentityProviding {
    let value: PhysicalAttestationApplicationIdentity
    init(identity: PhysicalAttestationApplicationIdentity) {
        value = identity
    }

    func identity() throws -> PhysicalAttestationApplicationIdentity {
        value
    }
}

private actor CountingReplayStore: AttestationReplayChecking {
    private(set) var acceptedCount = 0
    func accept(nonce _: UUID, issuedAt _: Date) -> Bool {
        acceptedCount += 1
        return true
    }
}

private func filePermissions(_ url: URL) -> mode_t {
    var status = stat()
    guard Darwin.lstat(url.path, &status) == 0 else { return 0 }
    return status.st_mode & 0o777
}

private struct FixedCatalogProvider: CompatibilityCatalogProviding {
    let storedCatalog: CompatibilityCatalog
    init(catalog: CompatibilityCatalog) {
        storedCatalog = catalog
    }

    func catalog() throws -> CompatibilityCatalog {
        storedCatalog
    }
}

private struct FixedHostProvider: RuntimeUpdateHostProfiling {
    let storedProfile: HostProfile
    init(profile: HostProfile) {
        storedProfile = profile
    }

    func profile() -> HostProfile {
        storedProfile
    }
}

private struct FixedInstalledTargetResolver: InstalledRuntimeTargetResolving {
    let target: RuntimeUninstallTarget
    func resolve() async throws -> RuntimeUninstallTarget {
        target
    }
}

private struct FixedUpdatePreferencesPersistence: RuntimeUpdatePreferencesPersisting {
    let value: RuntimeUpdatePreferences
    func load() throws -> RuntimeUpdatePreferences {
        value
    }

    func save(_: RuntimeUpdatePreferences) throws {}
}

private struct FixedUpdateHelperRegistrar: PrivilegedHelperRegistering {
    let value: PrivilegedHelperRegistrationStatus
    init(status: PrivilegedHelperRegistrationStatus) {
        value = status
    }

    func status() async -> PrivilegedHelperRegistrationStatus {
        value
    }

    func ensureAvailable() async throws -> PrivilegedHelperRegistrationStatus {
        value
    }

    func unregister() async throws {}
    func openApprovalSettings() {}
}

private struct FixedRuntimeActivityProvider: RuntimeUpdateActivityProviding {
    let value: RuntimeActivitySnapshot
    func currentActivity() async throws -> RuntimeActivitySnapshot {
        value
    }
}

private struct FixedAttestationProvider: PhysicalAttestationIDProviding {
    let ids: Set<String>
    func verifiedIDs(for _: CompatibilityEntry) async -> Set<String> {
        ids
    }
}

private struct FixedRuntimeUpdateStateSink: RuntimeUpdateStateSink {
    func publish(_: RuntimeUpdateState) async {}
}

private struct FixedAutomaticBaselineCapture: UpgradeBaselineCapturing {
    let baseline: UpgradeBaseline
    func capture() async throws -> UpgradeBaseline {
        baseline
    }
}

private actor RecordingPreviousPackageVerifier: PreviousRuntimePackageVerifying {
    private(set) var verifiedURLs: [URL] = []

    func verify(_ baseline: UpgradeBaseline) async throws -> VerifiedRuntimePackage {
        verifiedURLs.append(baseline.previousPackageURL)
        throw RecordingAutomaticComponentError.expectedVerificationStop
    }
}

private enum RecordingAutomaticComponentError: Error {
    case expectedVerificationStop
}

private extension RuntimeInstallTarget {
    static let reviewed100 = Self(
        manifest: ReviewedRuntime100Manifest.package,
        releaseAPIURL: URL(string: "https://github.com/apple/container/releases/download/1.0.0/container-1.0.0-installer-signed.pkg")!,
        requiredProbes: ProbeID.baselineAllCases.map(\.rawValue)
    )
}

private extension RuntimeUpgradeTarget {
    static let reviewed110 = Self(
        installTarget: .appleContainer110,
        requiresFullDataRollback: false,
        destroysStorageCompatibility: false
    )
}
