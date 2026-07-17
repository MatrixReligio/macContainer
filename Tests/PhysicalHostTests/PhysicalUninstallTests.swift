import MCContainerBridge
import MCSystemLifecycle
import Testing

@Suite(
    "Authorized physical complete uninstall",
    .serialized,
    .enabled(
        if: PhysicalTestGate.isAuthorized && PhysicalTestGate.phase == "complete-uninstall-and-restore",
        "Exact uninstall authorization and phase are required"
    )
)
struct PhysicalUninstallTests {
    @Test func `production transaction removes the runtime and independently reports no residue`() async throws {
        let lifecycle = try ProductionRuntimeLifecycle(
            registrar: PhysicalEnabledRegistrar(),
            bridge: PhysicalTestGate.productionBridge()
        )
        let inventory = try await lifecycle.prepareUninstall(mode: .complete)
        let result = try await lifecycle.uninstall(
            mode: .complete,
            inventoryFingerprint: inventory.fingerprint,
            acknowledgesIrreversibleDeletion: true
        )

        #expect(result.completion == .complete)
        #expect(result.audit.isEmpty)
        #expect(result.audit.hasCompleteInventory)
        #expect(result.preservedKinds.isEmpty)
        try PhysicalTestGate.record(
            "uninstall.production-transaction",
            "uninstall.launch-services",
            "uninstall.processes",
            "uninstall.receipt",
            "uninstall.payload",
            "uninstall.application-support",
            "uninstall.configuration-defaults",
            "uninstall.credentials",
            "uninstall.resolver-pf",
            "uninstall.packages-rollback-caches",
            "cleanup.independent-residue-audit"
        )
    }
}

private struct PhysicalEnabledRegistrar: PrivilegedHelperRegistering {
    func status() async -> PrivilegedHelperRegistrationStatus {
        .enabled
    }

    func ensureAvailable() async throws -> PrivilegedHelperRegistrationStatus {
        .enabled
    }

    func unregister() async throws {}

    func openApprovalSettings() {}
}
