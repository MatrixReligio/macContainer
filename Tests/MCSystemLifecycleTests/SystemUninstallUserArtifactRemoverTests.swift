import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("Exact user artifact removal")
struct SystemUninstallUserArtifactRemoverTests {
    @Test func `removes only exact configured runtime locations and defaults domain`() async throws {
        let fixture = try UserArtifactFixture()
        defer { fixture.cleanup() }
        let defaults = RecordingDefaultsRemover()
        let remover = SystemUninstallUserArtifactRemover(
            locations: fixture.locations,
            pathRemover: LocalOwnedArtifactRemover(requiredOwner: geteuid()),
            defaults: defaults
        )

        for kind in SystemUninstallUserArtifactRemover.fileArtifactKinds {
            try await remover.remove(kind)
        }
        try await remover.remove(.defaultsDomain)

        #expect(fixture.locations.fileURLs.values.allSatisfy {
            !FileManager.default.fileExists(atPath: $0.path)
        })
        #expect(defaults.removedDomains == ["com.apple.container.defaults"])
        #expect(try String(contentsOf: fixture.unrelated, encoding: .utf8) == "keep")
    }

    @Test func `symlink artifact removal never follows the target`() async throws {
        let fixture = try UserArtifactFixture(createArtifacts: false)
        defer { fixture.cleanup() }
        let link = try #require(fixture.locations.fileURLs[.configuration])
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.unrelated)
        let remover = SystemUninstallUserArtifactRemover(
            locations: fixture.locations,
            pathRemover: LocalOwnedArtifactRemover(requiredOwner: geteuid()),
            defaults: RecordingDefaultsRemover()
        )

        try await remover.remove(.configuration)

        #expect(!FileManager.default.fileExists(atPath: link.path))
        #expect(try String(contentsOf: fixture.unrelated, encoding: .utf8) == "keep")
    }

    @Test func `rejects a system or privileged artifact kind`() async throws {
        let fixture = try UserArtifactFixture(createArtifacts: false)
        defer { fixture.cleanup() }
        let remover = SystemUninstallUserArtifactRemover(
            locations: fixture.locations,
            pathRemover: LocalOwnedArtifactRemover(requiredOwner: geteuid()),
            defaults: RecordingDefaultsRemover()
        )

        await #expect(throws: UserArtifactRemovalError.unsupportedKind(.receipt)) {
            try await remover.remove(.receipt)
        }
    }
}

private struct UserArtifactFixture {
    let root: URL
    let unrelated: URL
    let locations: UninstallUserArtifactLocations

    init(createArtifacts: Bool = true) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainerUserArtifactTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        unrelated = root.appendingPathComponent("unrelated.txt")
        try Data("keep".utf8).write(to: unrelated)
        let artifactRoot = root.appendingPathComponent("owned", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: false)
        locations = .init(
            applicationSupport: artifactRoot.appendingPathComponent("application-support"),
            configuration: artifactRoot.appendingPathComponent("configuration"),
            downloadedPackage: artifactRoot.appendingPathComponent("packages"),
            rollbackPoint: artifactRoot.appendingPathComponent("rollback"),
            testFixture: artifactRoot.appendingPathComponent("tests"),
            downloadCache: artifactRoot.appendingPathComponent("cache"),
            defaultsDomain: "com.apple.container.defaults"
        )
        if createArtifacts {
            for url in locations.fileURLs.values {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                try Data("owned".utf8).write(to: url.appendingPathComponent("item"))
            }
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class RecordingDefaultsRemover: UninstallDefaultsRemoving, @unchecked Sendable {
    private(set) var removedDomains: [String] = []

    func removePersistentDomain(_ domain: String) throws {
        removedDomains.append(domain)
    }
}
