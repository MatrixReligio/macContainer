import Darwin
import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("APFS rollback store")
struct RollbackStoreTests {
    @Test func `records all planned items before cloning and always captures configuration`() async throws {
        let fileSystem = RecordingRollbackFileSystem(availableBytes: 10000)
        let request = RollbackCaptureRequest.fixture(requiresFullData: false)
        let store = RollbackStore(
            rootDirectory: URL(fileURLWithPath: "/rollback"),
            fileSystem: fileSystem,
            packageVerifier: RecordingRollbackPackageVerifier(),
            sourcePolicy: .allowing(request)
        )

        let point = try await store.createPoint(
            request,
            verifiedPrevious: .fixture(manifest: request.previousManifest)
        )

        let manifestIndex = fileSystem.events.firstIndex(of: "manifest.create")
        let firstCloneIndex = fileSystem.events.firstIndex { $0.hasPrefix("clone:") }
        #expect(manifestIndex != nil && firstCloneIndex != nil && manifestIndex! < firstCloneIndex!)
        #expect(point.manifest.items.map(\.kind) == [.previousPackage, .configurationAndMetadata])
        #expect(!point.manifest.items.contains { $0.kind == .fullData })
        #expect(point.manifest.items.allSatisfy { $0.state == .created })
    }

    @Test func `captures full data only when compatibility requires it`() async throws {
        let fileSystem = RecordingRollbackFileSystem(availableBytes: 10000)
        let request = RollbackCaptureRequest.fixture(requiresFullData: true)
        let store = RollbackStore(
            rootDirectory: URL(fileURLWithPath: "/rollback"),
            fileSystem: fileSystem,
            packageVerifier: RecordingRollbackPackageVerifier(),
            sourcePolicy: .allowing(request)
        )

        let point = try await store.createPoint(
            request,
            verifiedPrevious: .fixture(manifest: request.previousManifest)
        )

        #expect(point.manifest.items.map(\.kind) == [
            .previousPackage, .configurationAndMetadata, .fullData
        ])
    }

    @Test func `space preflight includes twenty percent headroom before mutation`() async throws {
        let fileSystem = RecordingRollbackFileSystem(availableBytes: 359)
        let request = RollbackCaptureRequest.fixture(requiresFullData: true)
        let store = RollbackStore(
            rootDirectory: URL(fileURLWithPath: "/rollback"),
            fileSystem: fileSystem,
            packageVerifier: RecordingRollbackPackageVerifier(),
            sourcePolicy: .allowing(request)
        )

        await #expect(throws: RollbackStoreError.insufficientSpace(required: 360, available: 359)) {
            _ = try await store.createPoint(
                request,
                verifiedPrevious: .fixture(manifest: request.previousManifest)
            )
        }
        #expect(fileSystem.events.isEmpty)
    }

    @Test func `local store writes private manifest clones data and discards safely`() async throws {
        let fixture = try LocalRollbackFixture()
        defer { fixture.cleanup() }
        let store = RollbackStore(
            rootDirectory: fixture.rollbackRoot,
            packageVerifier: PassthroughRollbackPackageVerifier(),
            sourcePolicy: .allowing(fixture.request)
        )
        let request = fixture.request

        let point = try await store.createPoint(
            request,
            verifiedPrevious: .fixture(
                manifest: request.previousManifest,
                sourceURL: fixture.package
            )
        )

        var status = stat()
        #expect(Darwin.lstat(point.manifestURL.path, &status) == 0)
        #expect(status.st_mode & 0o777 == 0o600)
        #expect(try String(contentsOf: point.previousPackageURL, encoding: .utf8) == "package")
        #expect(try String(contentsOf: point.rootURL.appendingPathComponent("01-config"), encoding: .utf8) == "config")
        try await store.discard(point)
        #expect(Darwin.lstat(point.rootURL.path, &status) != 0 && errno == ENOENT)
    }

    @Test func `rollback restores an initially absent configuration to absence`() async throws {
        let fixture = try LocalRollbackFixture(configurationExists: false)
        defer { fixture.cleanup() }
        let store = RollbackStore(
            rootDirectory: fixture.rollbackRoot,
            packageVerifier: PassthroughRollbackPackageVerifier(),
            sourcePolicy: .allowing(fixture.request)
        )

        let point = try await store.createPoint(
            fixture.request,
            verifiedPrevious: .fixture(
                manifest: fixture.request.previousManifest,
                sourceURL: fixture.package
            )
        )
        let configurationItem = try #require(
            point.manifest.items.first { $0.kind == .configurationAndMetadata }
        )
        #expect(configurationItem.sourceWasPresent == false)
        #expect(configurationItem.logicalBytes == 0)

        try FileManager.default.createDirectory(
            at: fixture.config,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try Data("generated-by-target".utf8).write(
            to: fixture.config.appendingPathComponent("config.json")
        )
        try await store.restore(point)

        var status = stat()
        #expect(Darwin.lstat(fixture.config.path, &status) != 0 && errno == ENOENT)
    }

    @Test func `rollback refuses to restore absence across a symbolic link`() async throws {
        let fixture = try LocalRollbackFixture(configurationExists: false)
        defer { fixture.cleanup() }
        let store = RollbackStore(
            rootDirectory: fixture.rollbackRoot,
            packageVerifier: PassthroughRollbackPackageVerifier(),
            sourcePolicy: .allowing(fixture.request)
        )
        let point = try await store.createPoint(
            fixture.request,
            verifiedPrevious: .fixture(
                manifest: fixture.request.previousManifest,
                sourceURL: fixture.package
            )
        )
        let unrelated = fixture.root.appendingPathComponent("unrelated")
        try Data("keep".utf8).write(to: unrelated)
        try FileManager.default.createSymbolicLink(at: fixture.config, withDestinationURL: unrelated)

        await #expect(throws: RollbackStoreError.unsafeFileSystemItem) {
            try await store.restore(point)
        }
        #expect(try String(contentsOf: unrelated, encoding: .utf8) == "keep")
    }

    @Test func `legacy rollback items decode as an existing source`() throws {
        let data = Data("""
        {
          "kind":"configurationAndMetadata",
          "sourcePath":"/source/config",
          "backupName":"01-config",
          "logicalBytes":7,
          "state":"created"
        }
        """.utf8)

        let item = try JSONDecoder().decode(RollbackItem.self, from: data)

        #expect(item.sourceWasPresent)
    }

    @Test func `clone failure removes the partial rollback point`() async throws {
        let fileSystem = RecordingRollbackFileSystem(
            availableBytes: 10000,
            failingCloneName: "config"
        )
        let request = RollbackCaptureRequest.fixture(requiresFullData: false)
        let store = RollbackStore(
            rootDirectory: URL(fileURLWithPath: "/rollback"),
            fileSystem: fileSystem,
            packageVerifier: RecordingRollbackPackageVerifier(),
            sourcePolicy: .allowing(request)
        )

        await #expect(throws: RollbackFixtureError.injected) {
            _ = try await store.createPoint(
                request,
                verifiedPrevious: .fixture(manifest: request.previousManifest)
            )
        }
        #expect(fileSystem.events.last == "remove")
    }

    @Test func `local store rejects a symlink source before creating a point`() async throws {
        let fixture = try LocalRollbackFixture()
        defer { fixture.cleanup() }
        let symlink = fixture.root.appendingPathComponent("config-link")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: fixture.config)
        let request = RollbackCaptureRequest(
            previousPackageURL: fixture.package,
            previousManifest: .rollbackFixture,
            configurationAndMetadata: [symlink],
            fullData: [],
            requiresFullData: false
        )
        let store = RollbackStore(
            rootDirectory: fixture.rollbackRoot,
            packageVerifier: PassthroughRollbackPackageVerifier(),
            sourcePolicy: .allowing(request)
        )

        await #expect(throws: RollbackStoreError.unsafeFileSystemItem) {
            _ = try await store.createPoint(
                request,
                verifiedPrevious: .fixture(
                    manifest: request.previousManifest,
                    sourceURL: fixture.package
                )
            )
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.rollbackRoot.path))
    }

    @Test func `local store rejects a redirected rollback root before writing`() async throws {
        let fixture = try LocalRollbackFixture()
        defer { fixture.cleanup() }
        let redirected = fixture.root.appendingPathComponent("redirected", isDirectory: true)
        try FileManager.default.createDirectory(at: redirected, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            at: fixture.rollbackRoot,
            withDestinationURL: redirected
        )
        let store = RollbackStore(
            rootDirectory: fixture.rollbackRoot,
            packageVerifier: PassthroughRollbackPackageVerifier(),
            sourcePolicy: .allowing(fixture.request)
        )

        await #expect(throws: RollbackStoreError.unsafePoint) {
            _ = try await store.createPoint(
                fixture.request,
                verifiedPrevious: .fixture(
                    manifest: fixture.request.previousManifest,
                    sourceURL: fixture.package
                )
            )
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: redirected.path).isEmpty)
    }

    @Test func `new store instance securely reopens a completed rollback point`() async throws {
        let fixture = try LocalRollbackFixture()
        defer { fixture.cleanup() }
        let first = RollbackStore(
            rootDirectory: fixture.rollbackRoot,
            packageVerifier: PassthroughRollbackPackageVerifier(),
            sourcePolicy: .allowing(fixture.request)
        )
        let point = try await first.createPoint(
            fixture.request,
            verifiedPrevious: .fixture(
                manifest: fixture.request.previousManifest,
                sourceURL: fixture.package
            )
        )
        let reopenedStore = RollbackStore(
            rootDirectory: fixture.rollbackRoot,
            packageVerifier: PassthroughRollbackPackageVerifier(),
            sourcePolicy: .allowing(fixture.request)
        )

        let reopened = try await reopenedStore.loadPoint(id: point.id)
        let package = try await reopenedStore.openPreviousPackage(in: reopened)

        #expect(reopened.manifest == point.manifest)
        #expect(package.runtimeVersion == fixture.request.previousManifest.runtimeVersion)
    }

    @Test func `reopen rejects a rollback point with incomplete manifest items`() async throws {
        let fixture = try LocalRollbackFixture()
        defer { fixture.cleanup() }
        let store = RollbackStore(
            rootDirectory: fixture.rollbackRoot,
            packageVerifier: PassthroughRollbackPackageVerifier(),
            sourcePolicy: .allowing(fixture.request)
        )
        let point = try await store.createPoint(
            fixture.request,
            verifiedPrevious: .fixture(
                manifest: fixture.request.previousManifest,
                sourceURL: fixture.package
            )
        )
        var items = point.manifest.items
        items[0].state = .planned
        let incomplete = RollbackPointManifest(
            pointID: point.id,
            previousManifest: point.manifest.previousManifest,
            requiresFullData: point.manifest.requiresFullData,
            items: items
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try LocalRollbackStoreFileSystem().replaceManifest(
            encoder.encode(incomplete),
            at: point.manifestURL
        )
        let reopenedStore = RollbackStore(
            rootDirectory: fixture.rollbackRoot,
            packageVerifier: PassthroughRollbackPackageVerifier(),
            sourcePolicy: .allowing(fixture.request)
        )

        await #expect(throws: RollbackStoreError.unsafePoint) {
            _ = try await reopenedStore.loadPoint(id: point.id)
        }
    }

    @Test func `reopen rejects a tampered restore destination outside the source policy`() async throws {
        let fixture = try LocalRollbackFixture()
        defer { fixture.cleanup() }
        let store = RollbackStore(
            rootDirectory: fixture.rollbackRoot,
            packageVerifier: PassthroughRollbackPackageVerifier(),
            sourcePolicy: .allowing(fixture.request)
        )
        let point = try await store.createPoint(
            fixture.request,
            verifiedPrevious: .fixture(
                manifest: fixture.request.previousManifest,
                sourceURL: fixture.package
            )
        )
        var items = point.manifest.items
        let index = try #require(items.firstIndex { $0.kind == .configurationAndMetadata })
        let original = items[index]
        items[index] = RollbackItem(
            kind: original.kind,
            sourcePath: fixture.root.appendingPathComponent("unrelated-user-document").path,
            backupName: original.backupName,
            logicalBytes: original.logicalBytes,
            state: original.state
        )
        let tampered = RollbackPointManifest(
            pointID: point.id,
            previousManifest: point.manifest.previousManifest,
            requiresFullData: point.manifest.requiresFullData,
            items: items
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try LocalRollbackStoreFileSystem().replaceManifest(
            encoder.encode(tampered),
            at: point.manifestURL
        )

        let reopenedStore = RollbackStore(
            rootDirectory: fixture.rollbackRoot,
            packageVerifier: PassthroughRollbackPackageVerifier(),
            sourcePolicy: .allowing(fixture.request)
        )
        await #expect(throws: RollbackStoreError.unsafePoint) {
            _ = try await reopenedStore.loadPoint(id: point.id)
        }
    }
}

private final class RecordingRollbackFileSystem: RollbackStoreFileSystem, @unchecked Sendable {
    let availableBytes: UInt64
    let failingCloneName: String?
    private(set) var events: [String] = []

    init(availableBytes: UInt64, failingCloneName: String? = nil) {
        self.availableBytes = availableBytes
        self.failingCloneName = failingCloneName
    }

    func itemExists(at _: URL) -> Bool {
        true
    }

    func logicalSize(of url: URL) throws -> UInt64 {
        switch url.lastPathComponent {
        case "previous.pkg": 100
        case "config": 100
        case "data": 100
        default: 0
        }
    }

    func availableCapacity(at _: URL) throws -> UInt64 {
        availableBytes
    }

    func createPrivateDirectory(at _: URL) throws {
        events.append("directory.create")
    }

    func createManifest(_ data: Data, at _: URL) throws {
        _ = data
        events.append("manifest.create")
    }

    func replaceManifest(_ data: Data, at _: URL) throws {
        _ = data
        events.append("manifest.replace")
    }

    func readManifest(at _: URL) throws -> Data {
        throw RollbackFixtureError.injected
    }

    func clonePackage(from _: OpenRuntimePackageFile, to _: URL) throws {
        events.append("clone:previous.pkg")
    }

    func cloneItem(from source: URL, to _: URL) throws {
        events.append("clone:\(source.lastPathComponent)")
        if source.lastPathComponent == failingCloneName {
            throw RollbackFixtureError.injected
        }
    }

    func restoreItem(from _: URL, to _: URL) throws {
        events.append("restore")
    }

    func restoreAbsence(at _: URL) throws {
        events.append("restore.absence")
    }

    func removePoint(at _: URL, identity _: RollbackDirectoryIdentity) throws {
        events.append("remove")
    }

    func directoryIdentity(at _: URL) throws -> RollbackDirectoryIdentity {
        .init(device: 1, inode: 1, owner: getuid())
    }
}

private enum RollbackFixtureError: Error {
    case injected
}

private struct RecordingRollbackPackageVerifier: InstallRuntimePackageVerifying {
    func verify(
        packageAt url: URL,
        against manifest: RuntimePackageManifest
    ) async throws -> VerifiedRuntimePackage {
        .fixture(manifest: manifest, sourceURL: url)
    }
}

private struct PassthroughRollbackPackageVerifier: InstallRuntimePackageVerifying {
    func verify(
        packageAt url: URL,
        against manifest: RuntimePackageManifest
    ) async throws -> VerifiedRuntimePackage {
        .fixture(manifest: manifest, sourceURL: url)
    }
}

private struct LocalRollbackFixture {
    let root: URL
    let rollbackRoot: URL
    let package: URL
    let config: URL
    let data: URL
    let request: RollbackCaptureRequest

    init(configurationExists: Bool = true) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainerRollbackTests-\(UUID().uuidString)", isDirectory: true)
        rollbackRoot = root.appendingPathComponent("rollback", isDirectory: true)
        package = root.appendingPathComponent("previous.pkg")
        config = root.appendingPathComponent("config")
        data = root.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("package".utf8).write(to: package)
        if configurationExists {
            try Data("config".utf8).write(to: config)
        }
        try Data("data".utf8).write(to: data)
        for url in [package, data] + (configurationExists ? [config] : []) {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        request = .init(
            previousPackageURL: package,
            previousManifest: .rollbackFixture,
            configurationAndMetadata: [config],
            fullData: [data],
            requiresFullData: false
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private extension RollbackCaptureRequest {
    static func fixture(requiresFullData: Bool) -> Self {
        .init(
            previousPackageURL: URL(fileURLWithPath: "/source/previous.pkg"),
            previousManifest: .rollbackFixture,
            configurationAndMetadata: [URL(fileURLWithPath: "/source/config")],
            fullData: [URL(fileURLWithPath: "/source/data")],
            requiresFullData: requiresFullData
        )
    }
}

private extension RollbackSourcePolicy {
    static func allowing(_ request: RollbackCaptureRequest) -> Self {
        Self(
            previousPackageRoots: [request.previousPackageURL.deletingLastPathComponent()],
            configurationAndMetadataPaths: request.configurationAndMetadata,
            fullDataPaths: request.fullData
        )
    }
}

private extension RuntimePackageManifest {
    static let rollbackFixture = Self(
        runtimeVersion: "1.0.0",
        assetName: "previous.pkg",
        sha256: String(repeating: "a", count: 64),
        installerTeamID: "UPBK2H6LZM",
        signerCommonName: "Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)",
        receiptIdentifier: "com.apple.container-installer",
        installLocation: "/usr/local",
        payload: [
            .init(relativePath: "bin", kind: .directory),
            .init(relativePath: "bin/container", kind: .file, sha256: String(repeating: "a", count: 64))
        ]
    )
}

private extension VerifiedRuntimePackage {
    static func fixture(
        manifest: RuntimePackageManifest,
        sourceURL: URL? = nil
    ) -> Self {
        let url = sourceURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { preconditionFailure("Fixture package must be readable") }
        defer { Darwin.close(descriptor) }
        do {
            return try Self(
                runtimeVersion: manifest.runtimeVersion,
                sha256: manifest.sha256,
                installerTeamID: manifest.installerTeamID,
                signerCommonName: manifest.signerCommonName,
                receiptIdentifier: manifest.receiptIdentifier,
                installLocation: manifest.installLocation,
                payload: manifest.payload,
                openFile: OpenRuntimePackageFile(duplicating: descriptor)
            )
        } catch {
            preconditionFailure("Fixture package must satisfy descriptor policy")
        }
    }
}
