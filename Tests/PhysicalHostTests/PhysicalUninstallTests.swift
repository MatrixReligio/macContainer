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
        let result = try await PhysicalSignedAppOperations.completeUninstall()

        #expect(result.completion == "complete")
        #expect(result.auditEmpty == true)
        #expect(result.auditComplete == true)
        #expect(result.preservedCount == 0)
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
