import Foundation
import MCAppCore
import MCSystemLifecycle
import Testing

@MainActor
@Suite("Runtime lifecycle controller")
struct RuntimeLifecycleControllerTests {
    @Test func `helper approval is shown before installation can begin`() async {
        let service = FixtureLifecycleService(
            installError: RuntimeLifecycleServiceError.helperApprovalRequired
        )
        let controller = RuntimeLifecycleController(service: service)

        await controller.install()

        #expect(controller.state == .helperApprovalRequired)
        #expect(service.installCalls == 1)
    }

    @Test func `successful install publishes reviewed runtime identity`() async {
        let service = FixtureLifecycleService()
        let controller = RuntimeLifecycleController(service: service)

        await controller.install()

        #expect(controller.state == .installed(version: "1.1.0"))
    }

    @Test func `installed runtime cannot be installed a second time`() async {
        let service = FixtureLifecycleService()
        let controller = RuntimeLifecycleController(service: service)

        await controller.install()
        await controller.install()

        #expect(controller.state == .installed(version: "1.1.0"))
        #expect(service.installCalls == 1)
    }

    @Test func `refresh recognizes an already installed reviewed runtime`() async {
        let service = FixtureLifecycleService(installedVersion: "1.1.0")
        let controller = RuntimeLifecycleController(service: service)

        await controller.refreshInstallationStatus()
        await controller.install()

        #expect(controller.state == .installed(version: "1.1.0"))
        #expect(service.installCalls == 0)
    }

    @Test func `install failure preserves the safe failing stage code`() async {
        let service = FixtureLifecycleService(
            installError: InstallError.postflightFailed(stage: .kernelEnsure)
        )
        let controller = RuntimeLifecycleController(service: service)

        await controller.install()

        #expect(controller.state == .failed(code: "lifecycle.install.kernel.ensure"))
    }

    @Test func `complete uninstall uses the fresh inventory fingerprint`() async throws {
        let service = FixtureLifecycleService()
        let controller = RuntimeLifecycleController(service: service)

        await controller.prepareUninstall(mode: .complete)
        let inventory = try #require(controller.preparedInventory)
        await controller.uninstall(
            mode: .complete,
            inventory: inventory,
            acknowledgesIrreversibleDeletion: true
        )

        #expect(controller.state == .uninstalled(.complete))
        #expect(service.uninstallFingerprint == inventory.fingerprint)
    }
}

private final class FixtureLifecycleService: RuntimeLifecycleServicing, @unchecked Sendable {
    private let lock = NSLock()
    private let installError: (any Error)?
    private let installedVersion: String?
    private var storedInstallCalls = 0
    private var storedUninstallFingerprint: String?

    init(installError: (any Error)? = nil, installedVersion: String? = nil) {
        self.installError = installError
        self.installedVersion = installedVersion
    }

    var installCalls: Int {
        lock.withLock { storedInstallCalls }
    }

    var uninstallFingerprint: String? {
        lock.withLock { storedUninstallFingerprint }
    }

    func helperStatus() async -> PrivilegedHelperRegistrationStatus {
        .enabled
    }

    func installedReviewedRuntimeVersion() async throws -> String? {
        installedVersion
    }

    func requestHelperAvailability() async throws -> PrivilegedHelperRegistrationStatus {
        .enabled
    }

    func openHelperApprovalSettings() async {}

    func installReviewedRuntime() async throws -> InstallReport {
        lock.withLock { storedInstallCalls += 1 }
        if let installError {
            throw installError
        }
        return .init(
            runtimeVersion: "1.1.0",
            packageSHA256: String(repeating: "a", count: 64),
            receipt: .init(
                identifier: "com.apple.container-installer",
                version: "1.1.0",
                installLocation: "/usr/local"
            )
        )
    }

    func prepareUninstall(mode: UninstallMode) async throws -> UninstallInventory {
        .init(
            runtimeVersion: "1.1.0",
            activeWork: [],
            serviceLabels: ["com.apple.container.apiserver"],
            resolverNames: [],
            artifactKinds: [.receipt, .receiptPayload],
            estimatedBytes: 1,
            mode: mode
        )
    }

    func uninstall(
        mode: UninstallMode,
        inventoryFingerprint: String,
        acknowledgesIrreversibleDeletion _: Bool
    ) async throws -> UninstallResult {
        lock.withLock { storedUninstallFingerprint = inventoryFingerprint }
        let items = ResidueInventory.expectations.map {
            ResidueItem(
                kind: $0.kind,
                redactedLocation: $0.redactedLocation,
                status: .absent,
                recoveryKey: $0.recoveryKey
            )
        }
        return .init(
            completion: mode == .complete ? .complete : .dataPreserved,
            audit: .init(items: items),
            preservedKinds: []
        )
    }

    func unregisterHelper() async throws {}
}
