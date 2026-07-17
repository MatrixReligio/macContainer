import Darwin
import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("Guarded physical cleanup")
struct GuardedCleanupTests {
    @Test func `records artifact before creation`() async throws {
        let storage = RecordingCleanupLedgerStorage()
        let runID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let root = URL(fileURLWithPath: "/private/tmp/mct-fixture", isDirectory: true)
        let artifact = TestArtifact.temporaryDirectory(root.appendingPathComponent("tmp").path)
        let ledger = CleanupLedger(storage: storage, runID: runID)

        try await ledger.plan(artifact)

        #expect(await storage.events.map(\.state) == [.planned])
        #expect(await storage.events.map(\.artifact) == [artifact])
    }

    @Test(arguments: [
        "/",
        "/Users",
        "/usr/local",
        "../other",
        ".artifacts/physical/other-run"
    ])
    func `refuses a path outside the exact run namespace`(_ path: String) async throws {
        let fixture = try CleanupFixture()
        defer { fixture.destroy() }
        let artifact = TestArtifact.temporaryDirectory(path)

        await #expect(throws: CleanupPolicyError.self) {
            try await fixture.cleanup.remove(artifact)
        }
        #expect(FileManager.default.fileExists(atPath: fixture.outsideSentinel.path))
    }

    @Test func `accepts a child expressed through the private tmp alias of the canonical run root`() throws {
        let runID = UUID()
        let runRoot = URL(
            fileURLWithPath: "/private/tmp/maccontainer-cleanup-alias-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: runRoot,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: runRoot) }
        let child = runRoot.appendingPathComponent("results", isDirectory: true)

        try PhysicalCleanupPolicy(runID: runID, runRoot: runRoot).validate(
            .temporaryDirectory(child.path)
        )
    }

    @Test func `requires planned created removed verified transition order`() async throws {
        let fixture = try CleanupFixture()
        defer { fixture.destroy() }
        let file = fixture.runRoot.appendingPathComponent("owned.txt")
        let artifact = TestArtifact.file(file.path)

        await #expect(throws: CleanupLedgerError.self) {
            try await fixture.ledger.markCreated(artifact)
        }
        try await fixture.ledger.plan(artifact)
        try Data("fixture".utf8).write(to: file, options: .atomic)
        try await fixture.ledger.markCreated(artifact)
        try await fixture.cleanup.remove(artifact)

        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(await fixture.ledger.state(of: artifact) == .verifiedAbsent)
        #expect(await fixture.storage.events.map(\.state) == [.planned, .created, .removed, .verifiedAbsent])

        try await fixture.cleanup.remove(artifact)
        #expect(await fixture.storage.events.count == 4)
    }

    @Test func `refuses symbolic link substitution without touching its target`() async throws {
        let fixture = try CleanupFixture()
        defer { fixture.destroy() }
        let target = fixture.outsideSentinel
        let link = fixture.runRoot.appendingPathComponent("substituted")
        let artifact = TestArtifact.file(link.path)
        try await fixture.ledger.plan(artifact)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        try await fixture.ledger.markCreated(artifact)

        await #expect(throws: CleanupPolicyError.self) {
            try await fixture.cleanup.remove(artifact)
        }
        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(await fixture.ledger.state(of: artifact) == .created)
    }

    @Test func `refuses hard linked file substitution`() async throws {
        let fixture = try CleanupFixture()
        defer { fixture.destroy() }
        let owned = fixture.runRoot.appendingPathComponent("owned")
        let alias = fixture.runRoot.appendingPathComponent("alias")
        try Data("fixture".utf8).write(to: owned)
        #expect(link(owned.path, alias.path) == 0)
        let artifact = TestArtifact.file(alias.path)
        try await fixture.ledger.plan(artifact)
        try await fixture.ledger.markCreated(artifact)

        await #expect(throws: CleanupPolicyError.self) {
            try await fixture.cleanup.remove(artifact)
        }
        #expect(FileManager.default.fileExists(atPath: owned.path))
    }

    @Test func `removes an owned nonempty directory tree without following links`() async throws {
        let fixture = try CleanupFixture()
        defer { fixture.destroy() }
        let directory = fixture.runRoot.appendingPathComponent("DerivedData", isDirectory: true)
        let nested = directory.appendingPathComponent("Build/Products", isDirectory: true)
        let file = nested.appendingPathComponent("artifact")
        let artifact = TestArtifact.temporaryDirectory(directory.path)
        try await fixture.ledger.plan(artifact)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: file)
        try await fixture.ledger.markCreated(artifact)

        try await fixture.cleanup.remove(artifact)

        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(await fixture.ledger.state(of: artifact) == .verifiedAbsent)
    }

    @Test func `file ledger persists synchronized events and rejects corruption`() async throws {
        let fixture = try CleanupFixture()
        defer { fixture.destroy() }
        let ledgerURL = fixture.runRoot.appendingPathComponent("cleanup.jsonl")
        let storage = try FileCleanupLedgerStorage(url: ledgerURL)
        let artifact = TestArtifact.file(fixture.runRoot.appendingPathComponent("owned").path)
        let ledger = CleanupLedger(storage: storage, runID: fixture.runID)
        try await ledger.plan(artifact)
        try await ledger.markCreated(artifact)

        let recovered = try await CleanupLedger.recover(storage: storage, runID: fixture.runID)
        #expect(await recovered.state(of: artifact) == .created)

        try Data("not-json\n".utf8).write(to: ledgerURL, options: .atomic)
        await #expect(throws: CleanupLedgerError.self) {
            _ = try await CleanupLedger.recover(storage: storage, runID: fixture.runID)
        }
    }

    @Test func `recovery closes every filesystem crash boundary`() async throws {
        for boundary in CleanupCrashBoundary.allCases {
            let fixture = try CleanupFixture()
            let file = fixture.runRoot.appendingPathComponent("owned")
            let artifact = TestArtifact.file(file.path)
            try await fixture.ledger.plan(artifact)
            if boundary != .afterPlanBeforeCreate {
                try Data("fixture".utf8).write(to: file)
            }
            if boundary == .afterCreated || boundary == .afterRemoval {
                try await fixture.ledger.markCreated(artifact)
            }
            if boundary == .afterRemoval {
                try FileManager.default.removeItem(at: file)
                try await fixture.ledger.markRemoved(artifact)
            }
            let recovery = GuardedCleanupRecovery(
                policy: PhysicalCleanupPolicy(runID: fixture.runID, runRoot: fixture.runRoot),
                ledger: fixture.ledger,
                cleanup: fixture.cleanup,
                ledgerURL: fixture.runRoot.appendingPathComponent("cleanup.jsonl")
            )

            try await recovery.run()

            #expect(await fixture.ledger.state(of: artifact) == .verifiedAbsent)
            #expect(!FileManager.default.fileExists(atPath: file.path))
            fixture.destroy()
        }
    }

    @Test func `recovery refuses an unledgered filesystem entry`() async throws {
        let fixture = try CleanupFixture()
        defer { fixture.destroy() }
        let planned = fixture.runRoot.appendingPathComponent("planned")
        try await fixture.ledger.plan(.file(planned.path))
        let unknown = fixture.runRoot.appendingPathComponent("unknown")
        try Data("unknown".utf8).write(to: unknown)
        let recovery = GuardedCleanupRecovery(
            policy: PhysicalCleanupPolicy(runID: fixture.runID, runRoot: fixture.runRoot),
            ledger: fixture.ledger,
            cleanup: fixture.cleanup,
            ledgerURL: fixture.runRoot.appendingPathComponent("cleanup.jsonl")
        )

        await #expect(throws: CleanupPolicyError.self) {
            try await recovery.run()
        }
        #expect(FileManager.default.fileExists(atPath: unknown.path))
    }
}

private enum CleanupCrashBoundary: CaseIterable {
    case afterPlanBeforeCreate
    case afterCreateBeforeCreated
    case afterCreated
    case afterRemoval
}

private actor RecordingCleanupLedgerStorage: CleanupLedgerStorage {
    private(set) var events: [CleanupEvent] = []

    func append(_ event: CleanupEvent) async throws {
        events.append(event)
    }

    func load() async throws -> [CleanupEvent] {
        events
    }
}

private final class CleanupFixture: @unchecked Sendable {
    let runID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let root: URL
    let runRoot: URL
    let outsideSentinel: URL
    let storage: RecordingCleanupLedgerStorage
    let ledger: CleanupLedger
    let cleanup: GuardedCleanup

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("maccontainer-cleanup-tests-\(UUID().uuidString)", isDirectory: true)
        runRoot = root.appendingPathComponent(runID.uuidString.lowercased(), isDirectory: true)
        outsideSentinel = root.appendingPathComponent("outside-sentinel")
        try FileManager.default.createDirectory(
            at: runRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try Data("do-not-remove".utf8).write(to: outsideSentinel)
        storage = RecordingCleanupLedgerStorage()
        ledger = CleanupLedger(storage: storage, runID: runID)
        cleanup = GuardedCleanup(
            policy: PhysicalCleanupPolicy(runID: runID, runRoot: runRoot),
            ledger: ledger
        )
    }

    func destroy() {
        try? FileManager.default.removeItem(at: root)
    }
}
