import Foundation
import MCCompatibility
@testable import MCSystemLifecycle
import Testing

@Suite("Durable blocked runtime versions")
struct BlockedVersionStoreTests {
    @Test func `record persists privately and reopens`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let record = fixture.record()

        try await BlockedVersionStore(fileURL: fixture.file).record(record)
        let reopened = BlockedVersionStore(fileURL: fixture.file)

        #expect(try await reopened.record(for: "1.1.0") == record)
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.file.path)
        let permissions = attributes[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test func `block clears only for explicit new attestation supersession`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let store = BlockedVersionStore(fileURL: fixture.file)
        let record = fixture.record()
        try await store.record(record)

        #expect(try await store.blockingAttestationID(
            for: fixture.entry,
            catalogRevision: "same-revision"
        ) == record.attestationID)

        let replacement = fixture.replacementEntry(superseding: record.attestationID)
        #expect(try await store.blockingAttestationID(
            for: replacement,
            catalogRevision: "new-revision"
        ) == nil)
        #expect(try await store.record(for: "1.1.0") == nil)
    }

    @Test func `different attestation without explicit supersession stays blocked`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let store = BlockedVersionStore(fileURL: fixture.file)
        let record = fixture.record()
        try await store.record(record)

        let replacement = fixture.replacementEntry(superseding: nil)
        #expect(try await store.blockingAttestationID(
            for: replacement,
            catalogRevision: "new-revision"
        ) == record.attestationID)
    }

    @Test func `corrupt or redirected storage fails closed`() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fixture.file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fixture.file.path)

        await #expect(throws: BlockedVersionStoreError.corruptStorage) {
            try await BlockedVersionStore(fileURL: fixture.file).record(for: "1.1.0")
        }

        try FileManager.default.removeItem(at: fixture.file)
        let target = fixture.root.appending(path: "target")
        try Data("[]".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: fixture.file, withDestinationURL: target)
        await #expect(throws: BlockedVersionStoreError.unsafeStorage) {
            try await BlockedVersionStore(fileURL: fixture.file).record(for: "1.1.0")
        }
    }
}

private struct StoreFixture: Sendable {
    let root: URL
    let file: URL
    let entry: CompatibilityEntry

    init() throws {
        root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: ".blocked-store-test-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        file = root.appending(path: "blocked.json")
        entry = try #require(CompatibilityCatalog.bundled().entries.first)
    }

    func record() -> BlockedVersionRecord {
        BlockedVersionRecord(
            runtimeVersion: "1.1.0",
            appVersion: "0.1.0",
            catalogRevision: "same-revision",
            attestationID: entry.attestation.id,
            failedProbeID: .images,
            timestamp: Date(timeIntervalSince1970: 123)
        )
    }

    func replacementEntry(superseding blockedID: String?) -> CompatibilityEntry {
        CompatibilityEntry(
            runtimeVersion: entry.runtimeVersion,
            package: entry.package,
            minimumAppVersion: entry.minimumAppVersion,
            maximumAppVersion: entry.maximumAppVersion,
            adapterPackageVersion: entry.adapterPackageVersion,
            capabilityIDs: entry.capabilityIDs,
            minimumMacOSMajor: entry.minimumMacOSMajor,
            requiredHardwareCapabilities: entry.requiredHardwareCapabilities,
            storageMigration: entry.storageMigration,
            rollback: entry.rollback,
            allowedUpgradeSources: entry.allowedUpgradeSources,
            requiredProbeIDs: entry.requiredProbeIDs,
            attestation: AttestationReference(
                id: "replacement-attestation",
                source: .embeddedPhysicalGate,
                sourceCommit: entry.attestation.sourceCommit,
                testPlanVersion: entry.attestation.testPlanVersion
            ),
            supersedesBlockedAttestationIDs: blockedID.map { [$0] } ?? []
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
