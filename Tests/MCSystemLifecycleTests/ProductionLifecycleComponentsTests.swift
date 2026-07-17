import Foundation
import MCCompatibility
import MCContainerBridge
import MCModel
@testable import MCSystemLifecycle
import Testing
import TestSupport

@Suite("Production lifecycle components")
struct ProductionLifecycleComponentsTests {
    @Test func `release metadata selects only the exact signed package`() async throws {
        let url = try #require(URL(string: "https://api.github.com/repos/apple/container/releases/tags/1.1.0"))
        let body = Data(
            #"""
            {"assets":[
              {"name":"notes.txt","browser_download_url":"https://github.com/notes.txt"},
              {
                "name":"container-1.1.0-installer-signed.pkg",
                "browser_download_url":"https://github.com/apple/container/releases/download/1.1.0/container-1.1.0-installer-signed.pkg"
              }
            ]}
            """#.utf8
        )
        let fetcher = SystemRuntimeReleaseMetadataFetcher(
            loader: FixtureReleaseLoader(response: .init(statusCode: 200, finalURL: url, body: body))
        )

        let metadata = try await fetcher.fetchRelease(at: url)
        #expect(metadata.asset.name == "container-1.1.0-installer-signed.pkg")
        #expect(metadata.asset.downloadURL.lastPathComponent == metadata.asset.name)
    }

    @Test func `release metadata fails closed for redirects duplicates and oversized bodies`() async throws {
        let url = try #require(URL(string: "https://api.github.com/repos/apple/container/releases/tags/1.1.0"))
        let redirected = try SystemRuntimeReleaseMetadataFetcher(
            loader: FixtureReleaseLoader(response: .init(
                statusCode: 200,
                finalURL: #require(URL(string: "https://example.com/release")),
                body: Data(#"{"assets":[]}"#.utf8)
            ))
        )
        await #expect(throws: ProductionLifecycleComponentError.untrustedReleaseResponse) {
            try await redirected.fetchRelease(at: url)
        }

        let duplicateBody = Data(
            #"""
            {"assets":[
              {"name":"container-1.1.0-installer-signed.pkg","browser_download_url":"https://github.com/a.pkg"},
              {"name":"container-1.1.0-installer-signed.pkg","browser_download_url":"https://github.com/b.pkg"}
            ]}
            """#.utf8
        )
        let duplicate = SystemRuntimeReleaseMetadataFetcher(
            loader: FixtureReleaseLoader(response: .init(statusCode: 200, finalURL: url, body: duplicateBody))
        )
        await #expect(throws: ProductionLifecycleComponentError.invalidReleaseMetadata) {
            try await duplicate.fetchRelease(at: url)
        }

        let oversized = SystemRuntimeReleaseMetadataFetcher(
            loader: FixtureReleaseLoader(response: .init(
                statusCode: 200,
                finalURL: url,
                body: Data(repeating: 0x20, count: 2_000_001)
            ))
        )
        await #expect(throws: ProductionLifecycleComponentError.releaseMetadataTooLarge) {
            try await oversized.fetchRelease(at: url)
        }
    }

    @Test func `receipt backend parses only the requested trusted receipt`() async throws {
        let plist: [String: Any] = [
            "pkgid": "com.apple.container-installer",
            "pkg-version": "1.1.0",
            "install-location": "/usr/local"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let backend = SystemPackageReceiptBackend(
            command: FixtureReceiptCommand(result: .init(exitStatus: 0, output: data))
        )

        #expect(try await backend.receipt(identifier: "com.apple.container-installer") == .init(
            identifier: "com.apple.container-installer",
            version: "1.1.0",
            installLocation: "/usr/local"
        ))
    }

    @Test func `installed payload verifier detects altered bytes`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mc-installed-payload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: false)
        let executable = bin.appendingPathComponent("container")
        try Data("hello".utf8).write(to: executable)
        let manifest = RuntimePackageManifest(
            runtimeVersion: "1.1.0",
            assetName: "container-1.1.0-installer-signed.pkg",
            sha256: String(repeating: "a", count: 64),
            installerTeamID: "UPBK2H6LZM",
            signerCommonName: "Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)",
            receiptIdentifier: "com.apple.container-installer",
            installLocation: "/usr/local",
            payload: [
                .init(relativePath: "bin", kind: .directory),
                .init(
                    relativePath: "bin/container",
                    kind: .file,
                    sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
                )
            ]
        )
        let verifier = SystemInstalledPayloadVerifier(installRoot: root)

        try await verifier.verify(expected: manifest)
        try Data("altered".utf8).write(to: executable)
        await #expect(throws: ProductionLifecycleComponentError.payloadMismatch("bin/container")) {
            try await verifier.verify(expected: manifest)
        }
    }

    @Test func `package downloader creates one private regular destination`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mc-package-download-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("container-1.1.0-installer-signed.pkg")
        let backend = FixturePackageDownloader()
        let downloader = SystemRuntimePackageDownloader(backend: backend)
        let asset = try RuntimeReleaseAsset(
            name: destination.lastPathComponent,
            downloadURL: #require(URL(string: "https://github.com/apple/container/releases/download/1.1.0/\(destination.lastPathComponent)"))
        )

        try await downloader.download(asset, to: destination)
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
        #expect(try Data(contentsOf: destination) == Data("signed-package".utf8))

        await #expect(throws: ProductionLifecycleComponentError.unsafePackageDestination) {
            try await downloader.download(asset, to: destination)
        }
        #expect(backend.calls == 1)
    }

    @Test func `platform preflight is fail closed and reports an existing reviewed receipt`() async throws {
        let receipt = InstalledPackageReceipt(
            identifier: "com.apple.container-installer",
            version: "1.0.0",
            installLocation: "/usr/local"
        )
        let supported = SystemInstallPlatformChecker(
            host: FixtureInstallHost(macOSMajor: 26, isAppleSilicon: true),
            receipts: PackageReceiptReader(backend: FixtureReceiptBackend(receipt: receipt))
        )
        #expect(try await supported.preflight(for: .appleContainer110) == .init(
            installedRuntimeVersion: "1.0.0"
        ))

        let unsupported = SystemInstallPlatformChecker(
            host: FixtureInstallHost(macOSMajor: 25, isAppleSilicon: true),
            receipts: PackageReceiptReader(backend: FixtureReceiptBackend(receipt: nil))
        )
        await #expect(throws: ProductionLifecycleComponentError.unsupportedHost) {
            try await unsupported.preflight(for: .appleContainer110)
        }
    }

    @Test func `installed receipt verifier requires the exact manifest identity`() async throws {
        let expected = ReviewedRuntime110Manifest.package
        let exact = SystemInstalledReceiptVerifier(
            receipts: PackageReceiptReader(backend: FixtureReceiptBackend(receipt: .init(
                identifier: expected.receiptIdentifier,
                version: expected.runtimeVersion,
                installLocation: expected.installLocation
            )))
        )
        #expect(try await exact.verify(expected: expected).version == "1.1.0")

        let missing = SystemInstalledReceiptVerifier(
            receipts: PackageReceiptReader(backend: FixtureReceiptBackend(receipt: nil))
        )
        await #expect(throws: ProductionLifecycleComponentError.receiptMissing) {
            try await missing.verify(expected: expected)
        }
    }

    @Test func `bridge install postflight starts service installs kernel and runs every baseline probe`() async throws {
        let fake = FakeRuntimeBridge()
        let bridge = FixtureRunningBridge(base: fake)
        try await BridgeInstallServiceController(bridge: bridge).startRuntime()
        try await BridgeInstallKernelEnsurer(bridge: bridge).ensureKernel(for: .appleContainer110)
        let capabilities = try #require(try CompatibilityCatalog.bundled().entries.first).capabilityIDs
        try await BridgeInstallProbeRunner(
            bridge: bridge,
            expectedRuntimeVersion: "1.1.0",
            enabledCapabilityIDs: capabilities
        ).run(probes: ProbeID.baselineAllCases.map(\.rawValue))

        let operations = await fake.recordedInvocations().map(\.operationID)
        #expect(operations.contains("system.start"))
        #expect(operations.contains("kernel.set"))
        #expect(operations.contains("containers.list"))
        #expect(operations.contains("configuration.validate"))
    }

    @Test func `production lifecycle stops before download when helper still requires approval`() async {
        let registrar = FixtureHelperRegistrar(status: .requiresApproval)
        let lifecycle = ProductionRuntimeLifecycle(
            registrar: registrar,
            bridge: FakeRuntimeBridge()
        )

        await #expect(throws: RuntimeLifecycleServiceError.helperApprovalRequired) {
            try await lifecycle.installReviewedRuntime()
        }
        #expect(registrar.ensureCalls == 1)
    }

    @Test func `uninstall inventory is fresh complete and bound to reviewed runtime`() async throws {
        let receipt = InstalledPackageReceipt(
            identifier: "com.apple.container-installer",
            version: "1.1.0",
            installLocation: "/usr/local"
        )
        let refresher = SystemUninstallInventoryRefresher(
            target: .reviewedRuntime110,
            receipts: PackageReceiptReader(backend: FixtureReceiptBackend(receipt: receipt)),
            bridge: FakeRuntimeBridge(),
            services: FixtureServiceManager(labels: ["com.apple.container.apiserver"]),
            resolvers: FixtureResolverInventory(names: ["mct.example"]),
            residue: FixtureResidueChecker(present: [.receipt, .receiptPayload, .launchService])
        )

        let inventory = try await refresher.refresh(mode: .complete)
        #expect(inventory.runtimeVersion == "1.1.0")
        #expect(inventory.serviceLabels == ["com.apple.container.apiserver"])
        #expect(inventory.resolverNames == ["mct.example"])
        #expect(inventory.artifactKinds == [.receipt, .receiptPayload, .launchService])
        #expect(inventory.fingerprint.count == 64)
    }

    @Test func `uninstall target resolver accepts only exact reviewed receipt versions`() async throws {
        let version100 = SystemInstalledRuntimeTargetResolver(
            receipts: PackageReceiptReader(backend: FixtureReceiptBackend(receipt: .init(
                identifier: ReviewedRuntime100Manifest.package.receiptIdentifier,
                version: "1.0.0",
                installLocation: ReviewedRuntime100Manifest.package.installLocation
            )))
        )
        #expect(try await version100.resolve() == .reviewedRuntime100)

        let unknown = SystemInstalledRuntimeTargetResolver(
            receipts: PackageReceiptReader(backend: FixtureReceiptBackend(receipt: .init(
                identifier: ReviewedRuntime110Manifest.package.receiptIdentifier,
                version: "9.9.9",
                installLocation: ReviewedRuntime110Manifest.package.installLocation
            )))
        )
        await #expect(throws: ProductionUninstallComponentError.unreviewedRuntime) {
            try await unknown.resolve()
        }
    }
}

private struct FixtureReleaseLoader: RuntimeReleaseDataLoading {
    let response: RuntimeReleaseHTTPResponse

    func load(_: URL) async throws -> RuntimeReleaseHTTPResponse {
        response
    }
}

private struct FixtureReceiptCommand: PackageReceiptCommandRunning {
    let result: PackageReceiptCommandResult

    func packageInfo(identifier _: String) throws -> PackageReceiptCommandResult {
        result
    }
}

private final class FixturePackageDownloader: KernelDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0

    var calls: Int {
        lock.withLock { callCount }
    }

    func download(from _: URL, to destination: URL, allowedHosts: Set<String>) async throws {
        #expect(allowedHosts == ["github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"])
        lock.withLock { callCount += 1 }
        try Data("signed-package".utf8).write(to: destination, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}

private struct FixtureInstallHost: InstallHostInspecting {
    let macOSMajor: Int
    let isAppleSilicon: Bool
}

private struct FixtureReceiptBackend: PackageReceiptReading {
    let receipt: InstalledPackageReceipt?

    func receipt(identifier _: String) async throws -> InstalledPackageReceipt? {
        receipt
    }
}

private struct FixtureRunningBridge: RuntimeBridge {
    let containers: any ContainerOperations
    let images: any ImageOperations
    let builds: any BuildOperations
    let builders: any BuilderOperations
    let networks: any NetworkOperations
    let volumes: any VolumeOperations
    let registries: any RegistryOperations
    let machines: any MachineOperations
    let system: any SystemOperations
    let dns: any DNSOperations
    let kernel: any KernelOperations
    let configuration: any ConfigurationOperations

    init(base: FakeRuntimeBridge) {
        containers = base.containers
        images = base.images
        builds = base.builds
        builders = base.builders
        networks = base.networks
        volumes = base.volumes
        registries = base.registries
        machines = base.machines
        system = FixtureRunningSystem(base: base.system)
        dns = base.dns
        kernel = base.kernel
        configuration = base.configuration
    }
}

private struct FixtureRunningSystem: SystemOperations {
    let base: any SystemOperations

    func start(_ request: SystemStartRequest) async throws -> SystemSummary {
        try await base.start(request)
    }

    func stop(_ request: SystemStopRequest) async throws -> SystemSummary {
        try await base.stop(request)
    }

    func status() async throws -> SystemSummary {
        _ = try await base.status()
        return .init(state: .running)
    }

    func version() async throws -> RuntimeVersionSummary {
        try await base.version()
    }

    func logs(_ options: LogOptions) async throws -> AsyncThrowingStream<LogRecord, any Error> {
        try await base.logs(options)
    }

    func diskUsage() async throws -> DiskUsageSummary {
        try await base.diskUsage()
    }
}

private final class FixtureHelperRegistrar: PrivilegedHelperRegistering, @unchecked Sendable {
    private let lock = NSLock()
    private let storedStatus: PrivilegedHelperRegistrationStatus
    private var storedEnsureCalls = 0

    init(status: PrivilegedHelperRegistrationStatus) {
        storedStatus = status
    }

    var ensureCalls: Int {
        lock.withLock { storedEnsureCalls }
    }

    func status() async -> PrivilegedHelperRegistrationStatus {
        storedStatus
    }

    func ensureAvailable() async throws -> PrivilegedHelperRegistrationStatus {
        lock.withLock { storedEnsureCalls += 1 }
        return storedStatus
    }

    func unregister() async throws {}

    func openApprovalSettings() {}
}

private struct FixtureResolverInventory: ResolverNameInventorying {
    let storedNames: [String]

    init(names: [String]) {
        storedNames = names
    }

    func names() throws -> [String] {
        storedNames
    }
}

private struct FixtureResidueChecker: ResidueAuditChecking {
    let present: Set<ResidueKind>

    func status(for kind: ResidueKind) async throws -> ResidueStatus {
        present.contains(kind) ? .present : .absent
    }
}

private struct FixtureServiceManager: ServiceManaging {
    let storedLabels: [String]

    init(labels: [String]) {
        storedLabels = labels
    }

    func register(_: ServiceDefinition) async throws {}
    func deregister(label _: String) async throws {}
    func isRegistered(label: String) async throws -> Bool {
        storedLabels.contains(label)
    }

    func labels(prefix: String) async throws -> [String] {
        storedLabels.filter { $0.hasPrefix(prefix) }
    }
}
