import Darwin
import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("Runtime update preferences")
struct RuntimeUpdatePreferencesStoreTests {
    @Test func `missing file loads safe opt-in defaults`() throws {
        let fixture = PreferencesFixture()
        defer { fixture.cleanup() }

        let loaded = try RuntimeUpdatePreferencesStore(fileURL: fixture.fileURL).load()

        #expect(loaded == .safeDefaults)
        #expect(loaded.automaticallyChecks)
        #expect(loaded.mode == .checkOnly)
        #expect(loaded.consentVersion == nil)
    }

    @Test func `round trips automatic consent in private storage`() throws {
        let fixture = PreferencesFixture()
        defer { fixture.cleanup() }
        let store = RuntimeUpdatePreferencesStore(fileURL: fixture.fileURL)
        let preferences = RuntimeUpdatePreferences(
            automaticallyChecks: true,
            mode: .automaticWhenIdle,
            consentVersion: RuntimeUpdatePolicy.currentConsentVersion
        )

        try store.save(preferences)

        #expect(try store.load() == preferences)
        #expect(permissions(fixture.fileURL.deletingLastPathComponent()) == 0o700)
        #expect(permissions(fixture.fileURL) == 0o600)
    }

    @Test func `rejects symbolic link storage without changing target`() throws {
        let fixture = PreferencesFixture()
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(
            at: fixture.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let protected = fixture.root.appendingPathComponent("protected")
        try Data("keep".utf8).write(to: protected)
        try FileManager.default.createSymbolicLink(at: fixture.fileURL, withDestinationURL: protected)
        let store = RuntimeUpdatePreferencesStore(fileURL: fixture.fileURL)

        #expect(throws: RuntimeUpdatePreferencesStoreError.unsafeStorage) {
            try store.save(.safeDefaults)
        }
        #expect(try String(contentsOf: protected, encoding: .utf8) == "keep")
    }

    private func permissions(_ url: URL) -> mode_t {
        var status = stat()
        guard Darwin.lstat(url.path, &status) == 0 else { return 0 }
        return status.st_mode & 0o777
    }
}

private final class PreferencesFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacContainerUpdatePreferencesTests-\(UUID().uuidString)", isDirectory: true)
    var fileURL: URL {
        root.appendingPathComponent("Updates", isDirectory: true)
            .appendingPathComponent("preferences.json")
    }

    init() {
        try? FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
