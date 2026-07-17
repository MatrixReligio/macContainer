@testable import MCCompatibility
import MCModel
import Testing

@Suite("Fail-closed compatibility decisions")
struct CompatibilityDecisionTests {
    @Test func `exact compatible input is allowed`() throws {
        let fixture = try DecisionFixture()

        #expect(CompatibilityDecisionEngine().decide(fixture.input()) == .allow(fixture.entry))
    }

    @Test func `decision table holds every unsafe condition in fixed order`() throws {
        let fixture = try DecisionFixture()
        let engine = CompatibilityDecisionEngine()

        #expect(engine.decide(fixture.input(catalogAvailable: false)) == .hold(.catalogInvalid))
        #expect(engine.decide(fixture.input(targetRuntimeVersion: "9.9.9")) == .hold(.unknownRuntime))
        #expect(engine.decide(fixture.input(appVersion: "0.0.9")) == .hold(.appVersionOutsideRange))
        #expect(engine.decide(fixture.input(macOSMajor: 25)) == .hold(.unsupportedHost))
        #expect(
            engine.decide(fixture.input(packageSHA256: String(repeating: "0", count: 64))) ==
                .hold(.packageIdentityMismatch)
        )
        #expect(engine.decide(fixture.input(installedRuntimeVersion: "0.9.0")) == .hold(.packageIdentityMismatch))
        #expect(engine.decide(fixture.input(verifiedAttestationIDs: [])) == .hold(.missingPhysicalAttestation))
        #expect(
            engine.decide(fixture.input(blockedAttestationID: fixture.entry.attestation.id)) ==
                .hold(.previousRollback)
        )
    }

    @Test func `destructive storage migration requires explicit consent`() throws {
        let fixture = try DecisionFixture(storageMigration: .destructive)
        let engine = CompatibilityDecisionEngine()

        #expect(engine.decide(fixture.input(destructiveMigrationConsent: false)) == .hold(.explicitConsentRequired))
        #expect(engine.decide(fixture.input(destructiveMigrationConsent: true)) == .allow(fixture.entry))
    }

    @Test func `ten thousand versions absent from the catalog are unknown`() throws {
        let fixture = try DecisionFixture()
        let engine = CompatibilityDecisionEngine()

        let allUnknown = (0 ..< 10000).allSatisfy { index in
            let version = "7.\(index / 100).\(index % 100)"
            return engine.decide(fixture.input(targetRuntimeVersion: version)) == .hold(.unknownRuntime)
        }
        #expect(allUnknown)
    }
}

private struct DecisionFixture {
    let catalog: CompatibilityCatalog
    let entry: CompatibilityEntry

    init(storageMigration: StorageMigrationClassification = .metadataOnly) throws {
        let bundled = try CompatibilityCatalog.bundled()
        let original = try #require(bundled.entries.first)
        entry = CompatibilityEntry(
            runtimeVersion: original.runtimeVersion,
            package: original.package,
            minimumAppVersion: original.minimumAppVersion,
            maximumAppVersion: original.maximumAppVersion,
            adapterPackageVersion: original.adapterPackageVersion,
            capabilityIDs: original.capabilityIDs,
            minimumMacOSMajor: original.minimumMacOSMajor,
            requiredHardwareCapabilities: original.requiredHardwareCapabilities,
            storageMigration: storageMigration,
            rollback: original.rollback,
            allowedUpgradeSources: original.allowedUpgradeSources,
            requiredProbeIDs: original.requiredProbeIDs,
            attestation: original.attestation,
            supersedesBlockedAttestationIDs: original.supersedesBlockedAttestationIDs
        )
        catalog = try CompatibilityCatalog(
            schemaVersion: bundled.schemaVersion,
            revision: bundled.revision,
            generatedAt: bundled.generatedAt,
            entries: [entry],
            updateURL: nil
        ).validated()
    }

    func input(
        catalogAvailable: Bool = true,
        targetRuntimeVersion: String = "1.1.0",
        appVersion: String = "0.1.0",
        macOSMajor: Int = 26,
        packageSHA256: String? = nil,
        installedRuntimeVersion: String = "1.0.0",
        verifiedAttestationIDs: Set<String>? = nil,
        blockedAttestationID: String? = nil,
        destructiveMigrationConsent: Bool = false
    ) -> CompatibilityDecisionInput {
        CompatibilityDecisionInput(
            catalog: catalogAvailable ? catalog : nil,
            targetRuntimeVersion: targetRuntimeVersion,
            appVersion: appVersion,
            host: HostProfile(
                logicalCPUs: 8,
                physicalMemoryBytes: 16 * 1_073_741_824,
                chip: .appleSilicon,
                macOSMajor: macOSMajor,
                capabilities: []
            ),
            package: RuntimePackageIdentity(
                runtimeVersion: entry.package.runtimeVersion,
                assetName: entry.package.assetName,
                sha256: packageSHA256 ?? entry.package.sha256,
                installerTeamID: entry.package.installerTeamID,
                signerCommonName: entry.package.signerCommonName,
                receiptIdentifier: entry.package.receiptIdentifier
            ),
            installedRuntimeVersion: installedRuntimeVersion,
            installedPackageSHA256: entry.allowedUpgradeSources[0].packageSHA256,
            verifiedAttestationIDs: verifiedAttestationIDs ?? [entry.attestation.id],
            blockedAttestationID: blockedAttestationID,
            destructiveMigrationConsent: destructiveMigrationConsent
        )
    }
}
