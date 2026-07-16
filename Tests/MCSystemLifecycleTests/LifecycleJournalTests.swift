import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("Lifecycle journal")
struct LifecycleJournalTests {
    @Test func `persists intent before side effect`() async throws {
        let storage = RecordingJournalStorage()
        let journal = LifecycleJournal(storage: storage, now: { Date(timeIntervalSince1970: 1) })

        let id = try await journal.begin(kind: .install, targetVersion: "1.1.0")
        try await journal.recordIntent(.installPackage(digest: "reviewed-digest"), transactionID: id)

        #expect(await storage.events.map(\.phase) == [.began, .intent])
        #expect(await storage.events.map(\.sequence) == [1, 2])
    }

    @Test func `encoded journal redacts secrets and private temporary paths`() async throws {
        let storage = RecordingJournalStorage()
        let journal = LifecycleJournal(storage: storage)
        let id = try await journal.begin(kind: .install, targetVersion: "1.1.0")

        try await journal.recordFailure(
            .init(
                code: "package.invalid",
                redactedDetail: "password=hunter2 at /private/var/folders/aa/bb/T/download.pkg"
            ),
            transactionID: id
        )

        let bytes = try #require(await storage.lastEncoded)
        let text = try #require(String(bytes: bytes, encoding: .utf8))
        #expect(!text.localizedCaseInsensitiveContains("password"))
        #expect(!text.contains("hunter2"))
        #expect(!text.contains("/private/var/folders"))
        #expect(text.contains("<redacted>"))
    }

    @Test func `rejects event after terminal phase`() async throws {
        let storage = RecordingJournalStorage()
        let journal = LifecycleJournal(storage: storage)
        let id = try await journal.begin(kind: .install, targetVersion: "1.1.0")
        try await journal.recordIntent(.installPackage(digest: "digest"), transactionID: id)
        try await journal.recordApplied(.installPackage(digest: "digest"), transactionID: id)
        try await journal.commit(transactionID: id)

        await #expect(throws: LifecycleJournalError.transactionAlreadyTerminal(id)) {
            try await journal.recordFailure(.init(code: "late", redactedDetail: "late"), transactionID: id)
        }
    }

    @Test func `rollback may begin when service stop fails before install intent`() async throws {
        let storage = RecordingJournalStorage()
        let journal = LifecycleJournal(storage: storage)
        let id = try await journal.begin(kind: .upgrade, targetVersion: "1.1.0")

        try await journal.recordRollingBack(
            .restoreRollbackPoint(identifier: UUID()),
            transactionID: id
        )
        try await journal.recordRolledBack(transactionID: id)

        #expect(await storage.events.map(\.phase) == [.began, .rollingBack, .rolledBack])
    }

    @Test func `local storage creates private append only journal`() async throws {
        let fixture = try LocalJournalFixture()
        defer { fixture.cleanup() }
        let storage = JSONLineLifecycleJournalStorage(fileURL: fixture.journalURL)
        let journal = LifecycleJournal(storage: storage, now: { Date(timeIntervalSince1970: 1) })

        let id = try await journal.begin(kind: .upgrade, targetVersion: "1.2.0")
        try await journal.recordIntent(.stopServices(labels: ["com.apple.container"]), transactionID: id)

        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.journalURL.path)
        let permissions = try #require(attributes[.posixPermissions] as? Int)
        let lines = try String(contentsOf: fixture.journalURL, encoding: .utf8)
            .split(separator: "\n")
        #expect(permissions & 0o777 == 0o600)
        #expect(lines.count == 2)
        #expect(try await storage.load().map(\.sequence) == [1, 2])
    }

    @Test func `truncated final record is quarantined and fails closed`() async throws {
        let fixture = try LocalJournalFixture(contents: "{\"sequence\":1")
        defer { fixture.cleanup() }
        let storage = JSONLineLifecycleJournalStorage(fileURL: fixture.journalURL)
        let journal = LifecycleJournal(storage: storage)

        await #expect(throws: LifecycleJournalError.corruptJournal) {
            _ = try await journal.begin(kind: .install, targetVersion: "1.1.0")
        }

        #expect(!FileManager.default.fileExists(atPath: fixture.journalURL.path))
        let quarantined = try FileManager.default.contentsOfDirectory(atPath: fixture.quarantineURL.path)
        #expect(quarantined.count == 1)
    }

    @Test func `duplicate sequence is quarantined and fails closed`() async throws {
        let event = LifecycleEvent(
            sequence: 1,
            transactionID: UUID(),
            kind: .install,
            phase: .began,
            targetVersion: "1.1.0",
            action: nil,
            failure: nil,
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let line = try #require(String(bytes: encoder.encode(event), encoding: .utf8))
        let fixture = try LocalJournalFixture(contents: "\(line)\n\(line)\n")
        defer { fixture.cleanup() }
        let storage = JSONLineLifecycleJournalStorage(fileURL: fixture.journalURL)

        await #expect(throws: LifecycleJournalError.corruptJournal) {
            _ = try await storage.load()
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.journalURL.path))
    }

    @Test func `journal survives reopening after durable intent`() async throws {
        let fixture = try LocalJournalFixture()
        defer { fixture.cleanup() }
        let storage = JSONLineLifecycleJournalStorage(fileURL: fixture.journalURL)
        let first = LifecycleJournal(storage: storage)
        let id = try await first.begin(kind: .uninstall, targetVersion: nil)
        try await first.recordIntent(.removeReceipt(identifier: "com.apple.container-installer"), transactionID: id)

        let reopened = LifecycleJournal(storage: JSONLineLifecycleJournalStorage(fileURL: fixture.journalURL))
        let events = try await reopened.events(for: id)

        #expect(events.map(\.phase) == [.began, .intent])
        #expect(events.last?.action == .removeReceipt(identifier: "com.apple.container-installer"))
    }
}

private actor RecordingJournalStorage: LifecycleJournalStorage {
    private(set) var events: [LifecycleEvent] = []

    var lastEncoded: Data? {
        guard let last = events.last else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(last)
    }

    func load() -> [LifecycleEvent] {
        events
    }

    func append(_ event: LifecycleEvent) {
        events.append(event)
    }
}

private final class LocalJournalFixture: @unchecked Sendable {
    let root: URL
    let journalURL: URL
    let quarantineURL: URL

    init(contents: String? = nil) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainerLifecycleJournalTests-\(UUID().uuidString)", isDirectory: true)
        journalURL = root.appendingPathComponent("Lifecycle/journal.jsonl")
        quarantineURL = root.appendingPathComponent("Lifecycle/.quarantine", isDirectory: true)
        if let contents {
            try FileManager.default.createDirectory(
                at: journalURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(contents.utf8).write(to: journalURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journalURL.path)
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
