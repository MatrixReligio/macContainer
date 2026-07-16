import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("System residue audit checker")
struct SystemResidueAuditCheckerTests {
    @Test func `checks exact filesystem inventory without treating shared directories as payload`() async throws {
        let fixture = try SystemResidueFixture()
        defer { fixture.cleanup() }
        let checker = SystemResidueAuditChecker(
            configuration: fixture.configuration,
            runtimeState: FixedRuntimeResidueQuery(),
            defaults: FixedDefaultsInspector(isPresent: false)
        )
        try FileManager.default.createDirectory(
            at: #require(fixture.configuration.userArtifacts.fileURLs[.applicationSupport]),
            withIntermediateDirectories: false
        )
        try FileManager.default.createDirectory(
            at: fixture.configuration.installRoot.appendingPathComponent("bin"),
            withIntermediateDirectories: true
        )

        #expect(try await checker.status(for: .applicationSupport) == .present)
        #expect(try await checker.status(for: .receiptPayload) == .absent)

        let payload = fixture.configuration.installRoot.appendingPathComponent("bin/container")
        try Data("payload".utf8).write(to: payload)
        #expect(try await checker.status(for: .receiptPayload) == .present)
    }

    @Test func `detects receipt resolver and nonempty runtime directory independently`() async throws {
        let fixture = try SystemResidueFixture()
        defer { fixture.cleanup() }
        let checker = SystemResidueAuditChecker(
            configuration: fixture.configuration,
            runtimeState: FixedRuntimeResidueQuery(),
            defaults: FixedDefaultsInspector(isPresent: false)
        )
        try FileManager.default.createDirectory(
            at: fixture.configuration.receiptDirectory,
            withIntermediateDirectories: true
        )
        try Data("receipt".utf8).write(
            to: fixture.configuration.receiptDirectory
                .appendingPathComponent("com.apple.container-installer.plist")
        )
        try FileManager.default.createDirectory(
            at: fixture.configuration.resolverDirectory,
            withIntermediateDirectories: true
        )
        try Data("resolver".utf8).write(
            to: fixture.configuration.resolverDirectory.appendingPathComponent("containerization.web.test")
        )
        let runtimeDirectory = fixture.configuration.runtimeOwnedDirectory
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)

        #expect(try await checker.status(for: .receipt) == .present)
        #expect(try await checker.status(for: .resolver) == .present)
        #expect(try await checker.status(for: .runtimeOwnedDirectory) == .absent)
        try Data("owned".utf8).write(to: runtimeDirectory.appendingPathComponent("item"))
        #expect(try await checker.status(for: .runtimeOwnedDirectory) == .present)
    }

    @Test func `delegates live state and defaults checks by exact kind`() async throws {
        let fixture = try SystemResidueFixture()
        defer { fixture.cleanup() }
        let checker = SystemResidueAuditChecker(
            configuration: fixture.configuration,
            runtimeState: FixedRuntimeResidueQuery(status: .present),
            defaults: FixedDefaultsInspector(isPresent: true)
        )

        for kind in [ResidueKind.launchService, .process, .registryCredential, .packetFilter] {
            #expect(try await checker.status(for: kind) == .present)
        }
        #expect(try await checker.status(for: .defaultsDomain) == .present)
    }
}

private struct SystemResidueFixture {
    let root: URL
    let configuration: SystemResidueAuditConfiguration

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainerSystemResidueTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let userRoot = root.appendingPathComponent("user", isDirectory: true)
        try FileManager.default.createDirectory(at: userRoot, withIntermediateDirectories: false)
        let locations = UninstallUserArtifactLocations(
            applicationSupport: userRoot.appendingPathComponent("application-support"),
            configuration: userRoot.appendingPathComponent("configuration"),
            downloadedPackage: userRoot.appendingPathComponent("packages"),
            rollbackPoint: userRoot.appendingPathComponent("rollback"),
            testFixture: userRoot.appendingPathComponent("tests"),
            downloadCache: userRoot.appendingPathComponent("cache"),
            defaultsDomain: "com.apple.container.defaults"
        )
        configuration = .init(
            userArtifacts: locations,
            receiptDirectory: root.appendingPathComponent("receipts", isDirectory: true),
            resolverDirectory: root.appendingPathComponent("resolver", isDirectory: true),
            installRoot: root.appendingPathComponent("install", isDirectory: true),
            runtimeOwnedDirectory: userRoot.appendingPathComponent("runtime-owned", isDirectory: true),
            manifest: ReviewedRuntime110Manifest.package
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private struct FixedRuntimeResidueQuery: RuntimeStateResidueQuerying {
    let status: ResidueStatus

    init(status: ResidueStatus = .absent) {
        self.status = status
    }

    func status(for _: ResidueKind) async throws -> ResidueStatus {
        status
    }
}

private struct FixedDefaultsInspector: DefaultsResidueInspecting {
    let isPresent: Bool

    func containsPersistentDomain(_: String) throws -> Bool {
        isPresent
    }
}
