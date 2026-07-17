import Foundation
@testable import MCCompatibility
import Testing

@Suite("Compatibility catalog")
struct CompatibilityCatalogTests {
    @Test func `bundled catalog contains the exact reviewed runtime`() throws {
        let catalog = try CompatibilityCatalog.bundled()
        let entry = try #require(catalog.entry(runtimeVersion: "1.1.0"))

        #expect(catalog.schemaVersion == 1)
        #expect(catalog.entries.count == 1)
        #expect(entry.package.sha256 == "0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714")
        #expect(entry.package.installerTeamID == "UPBK2H6LZM")
        #expect(entry.package.receiptIdentifier == "com.apple.container-installer")
        #expect(entry.adapterPackageVersion == "1.1.0")
        #expect(entry.allowedUpgradeSources == [
            .init(
                runtimeVersion: "1.0.0",
                packageSHA256: "13f45f26da94c354adcbefe1e8f7631e7f126e93c5d4dd6a5a538aa66b4f479d"
            )
        ])
        #expect(Set(entry.requiredProbeIDs) == Set(ProbeID.baselineAllCases.map(\.rawValue)))
        #expect(entry.capabilityIDs.count == 61)
    }

    @Test func `catalog grants no remote compatibility authority`() throws {
        let catalog = try CompatibilityCatalog.bundled()

        #expect(catalog.updateURL == nil)
        #expect(catalog.entries.allSatisfy { $0.attestation.source == .embeddedPhysicalGate })
    }

    @Test func `decoder rejects duplicate runtimes and missing probes`() throws {
        let catalog = try CompatibilityCatalog.bundled()
        let entry = try #require(catalog.entries.first)

        #expect(throws: CompatibilityCatalogError.duplicateRuntimeVersion("1.1.0")) {
            try CompatibilityCatalog(
                schemaVersion: 1,
                revision: catalog.revision,
                generatedAt: catalog.generatedAt,
                entries: [entry, entry],
                updateURL: nil
            ).validated()
        }

        let missingProbe = entry.replacing(requiredProbeIDs: Array(entry.requiredProbeIDs.dropLast()))
        #expect(throws: CompatibilityCatalogError.invalidProbeSet("1.1.0")) {
            try CompatibilityCatalog(
                schemaVersion: 1,
                revision: catalog.revision,
                generatedAt: catalog.generatedAt,
                entries: [missingProbe],
                updateURL: nil
            ).validated()
        }
    }

    @Test func `decoder rejects remote authority and malformed version intervals`() throws {
        let catalog = try CompatibilityCatalog.bundled()
        let entry = try #require(catalog.entries.first)

        #expect(throws: CompatibilityCatalogError.remoteAuthorityForbidden) {
            try CompatibilityCatalog(
                schemaVersion: 1,
                revision: catalog.revision,
                generatedAt: catalog.generatedAt,
                entries: [entry],
                updateURL: URL(string: "https://example.invalid/catalog.json")
            ).validated()
        }

        let invalidInterval = entry.replacing(minimumAppVersion: "2.0.0", maximumAppVersion: "1.0.0")
        #expect(throws: CompatibilityCatalogError.invalidAppVersionRange("1.1.0")) {
            try CompatibilityCatalog(
                schemaVersion: 1,
                revision: catalog.revision,
                generatedAt: catalog.generatedAt,
                entries: [invalidInterval],
                updateURL: nil
            ).validated()
        }
    }
}
