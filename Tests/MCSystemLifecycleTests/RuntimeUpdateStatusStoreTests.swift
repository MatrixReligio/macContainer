import Darwin
import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("Runtime update status store")
struct RuntimeUpdateStatusStoreTests {
    @Test func `round trips private status and timestamp`() async throws {
        let fixture = try StatusStoreFixture()
        defer { fixture.cleanup() }
        let store = RuntimeUpdateStatusStore(fileURL: fixture.fileURL)
        let status = PersistedRuntimeUpdateStatus(
            state: .available(version: "1.1.0"),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        try await store.save(status)

        #expect(try await store.load() == status)
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.fileURL.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
    }

    @Test func `missing status is empty and symbolic link is rejected`() async throws {
        let fixture = try StatusStoreFixture()
        defer { fixture.cleanup() }
        let store = RuntimeUpdateStatusStore(fileURL: fixture.fileURL)
        #expect(try await store.load() == nil)

        let target = fixture.root.appendingPathComponent("redirected")
        try FileManager.default.createDirectory(
            at: fixture.root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.createDirectory(
            at: fixture.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try Data("protected".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: fixture.fileURL, withDestinationURL: target)

        await #expect(throws: RuntimeUpdateStatusStoreError.unsafeStorage) {
            try await store.save(.init(state: .checking, updatedAt: .distantPast))
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == "protected")
    }

    @Test func `state sink persists the latest coordinator state`() async throws {
        let fixture = try StatusStoreFixture()
        defer { fixture.cleanup() }
        let store = RuntimeUpdateStatusStore(
            fileURL: fixture.fileURL,
            now: { Date(timeIntervalSince1970: 200) }
        )

        await store.publish(.pending(.workActive))

        #expect(try await store.load() == .init(
            state: .pending(.workActive),
            updatedAt: Date(timeIntervalSince1970: 200)
        ))
    }
}

private struct StatusStoreFixture {
    let root: URL
    let fileURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-update-status-\(UUID().uuidString)", isDirectory: true)
        fileURL = root
            .appendingPathComponent("Updates", isDirectory: true)
            .appendingPathComponent("status.json", isDirectory: false)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
