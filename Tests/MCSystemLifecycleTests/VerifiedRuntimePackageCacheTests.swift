import Darwin
import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("Verified runtime package cache")
struct VerifiedRuntimePackageCacheTests {
    @Test func `retains verified descriptor privately after staging file is removed`() async throws {
        let fixture = try CacheFixture()
        defer { fixture.cleanup() }
        let package = try fixture.package(contents: "reviewed-runtime")
        let cache = VerifiedRuntimePackageCache(rootDirectory: fixture.cacheRoot)

        let retained = try await cache.retain(
            package,
            assetName: "container-1.1.0-installer-signed.pkg"
        )
        try FileManager.default.removeItem(at: fixture.sourceURL)

        #expect(retained.url == fixture.cacheRoot.appendingPathComponent(
            "container-1.1.0-installer-signed.pkg"
        ))
        #expect(retained.runtimeVersion == "1.1.0")
        #expect(retained.sha256 == String(repeating: "a", count: 64))
        #expect(try String(contentsOf: retained.url, encoding: .utf8) == "reviewed-runtime")
        #expect(permissions(fixture.cacheRoot) == 0o700)
        #expect(permissions(retained.url) == 0o600)
    }

    @Test func `rejects unsafe asset name without creating cache`() async throws {
        let fixture = try CacheFixture()
        defer { fixture.cleanup() }
        let package = try fixture.package(contents: "reviewed-runtime")
        let cache = VerifiedRuntimePackageCache(rootDirectory: fixture.cacheRoot)

        await #expect(throws: VerifiedRuntimePackageCacheError.unsafeAssetName) {
            _ = try await cache.retain(package, assetName: "../runtime.pkg")
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.cacheRoot.path))
    }

    @Test func `rejects symlink cache root and preserves its target`() async throws {
        let fixture = try CacheFixture()
        defer { fixture.cleanup() }
        let package = try fixture.package(contents: "reviewed-runtime")
        let protected = fixture.root.appendingPathComponent("protected", isDirectory: true)
        try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            at: fixture.cacheRoot,
            withDestinationURL: protected
        )
        let cache = VerifiedRuntimePackageCache(rootDirectory: fixture.cacheRoot)

        await #expect(throws: VerifiedRuntimePackageCacheError.unsafeCacheRoot) {
            _ = try await cache.retain(
                package,
                assetName: "container-1.1.0-installer-signed.pkg"
            )
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: protected.path).isEmpty)
    }

    private func permissions(_ url: URL) -> mode_t {
        var status = stat()
        guard Darwin.lstat(url.path, &status) == 0 else { return 0 }
        return status.st_mode & 0o777
    }
}

private final class CacheFixture {
    let root: URL
    let cacheRoot: URL
    let sourceURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainerPackageCacheTests-\(UUID().uuidString)", isDirectory: true)
        cacheRoot = root.appendingPathComponent("RuntimePackages", isDirectory: true)
        sourceURL = root.appendingPathComponent("source.pkg")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
    }

    func package(contents: String) throws -> VerifiedRuntimePackage {
        try Data(contents.utf8).write(to: sourceURL, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sourceURL.path)
        let handle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? handle.close() }
        return VerifiedRuntimePackage(
            runtimeVersion: "1.1.0",
            sha256: String(repeating: "a", count: 64),
            installerTeamID: "TESTTEAM",
            signerCommonName: "Test Signer",
            receiptIdentifier: "com.example.runtime",
            installLocation: "/usr/local",
            payload: [],
            openFile: try OpenRuntimePackageFile(duplicating: handle.fileDescriptor)
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
