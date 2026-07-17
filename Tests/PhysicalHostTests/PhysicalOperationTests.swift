import Foundation
import MCCompatibility
import MCContainerBridge
import MCModel
import MCSystemLifecycle
import Testing

@Suite(
    "Authorized physical runtime operations",
    .serialized,
    .enabled(
        if: PhysicalTestGate.isAuthorized && PhysicalTestGate.phase == "install-and-operations",
        "Exact operation authorization and phase are required"
    )
)
struct PhysicalOperationTests {
    @Test func `system and configuration domains use the production bridge`() async throws {
        let bridge = try PhysicalTestGate.productionBridge()
        let started = try await ensureRuntime(bridge: bridge)
        #expect(started.state == .running)
        try PhysicalTestGate.record("install.runtime", "install.first-status", "system.start")
        #expect(try await bridge.system.status().state == .running)
        try PhysicalTestGate.record("system.status")
        #expect(try await bridge.system.version().version == "1.1.0")
        try PhysicalTestGate.record("system.version")
        let logs = try await bridge.system.logs(.init(follow: false, tail: 10))
        for try await _ in logs {}
        try PhysicalTestGate.record("system.logs")
        _ = try await bridge.system.diskUsage()
        try PhysicalTestGate.record("system.df")

        let configuration = try await bridge.configuration.load()
        _ = try await bridge.configuration.preview(configuration)
        _ = try await bridge.configuration.save(configuration)
        _ = try await bridge.configuration.save(configuration)
        try PhysicalTestGate.record("system.configuration-read-write-restore")

        #expect(try await bridge.system.stop(.init(timeoutSeconds: 60)).state == .stopped)
        try PhysicalTestGate.record("system.stop")
        #expect(try await bridge.system.start(.init(healthTimeoutSeconds: 60)).state == .running)
    }

    @Test func `resource inventories are reachable without a command line subprocess`() async throws {
        let bridge = try PhysicalTestGate.productionBridge()
        _ = try await ensureRuntime(bridge: bridge)

        _ = try await bridge.containers.list()
        try PhysicalTestGate.record("inventory.containers")
        _ = try await bridge.images.list()
        try PhysicalTestGate.record("inventory.images")
        _ = try await bridge.builders.status()
        try PhysicalTestGate.record("inventory.builders")
        _ = try await bridge.networks.list()
        try PhysicalTestGate.record("inventory.networks")
        _ = try await bridge.volumes.list()
        try PhysicalTestGate.record("inventory.volumes")
        _ = try await bridge.registries.list()
        try PhysicalTestGate.record("inventory.registries")
        _ = try await bridge.machines.list()
        try PhysicalTestGate.record("inventory.machines")
        _ = try await bridge.dns.list()
        try PhysicalTestGate.record("inventory.dns")

        try await PhysicalSignedAppOperations.roundTripDNS()
        try PhysicalTestGate.record("dns.production-create-delete")

        let entry = try #require(try CompatibilityCatalog.bundled().entries.first)
        try await BridgeUpgradeProbeRunner(
            bridge: bridge,
            enabledCapabilityIDs: entry.capabilityIDs
        ).run(probes: entry.requiredProbeIDs, runtimeVersion: "1.1.0")
        try PhysicalTestGate.record("compatibility.all-domain-probes")
    }

    @Test func `run namespace is stable and non-global`() throws {
        let runID = try #require(PhysicalTestGate.runID)
        #expect(PhysicalTestGate.namespace == "mct-e2e-\(runID.uuidString.lowercased())")
        #expect(PhysicalTestGate.namespace != "mct-e2e")
    }

    private func ensureRuntime(bridge: AppleRuntimeBridge) async throws -> SystemSummary {
        do {
            _ = try await SystemInstalledReceiptVerifier().verify(expected: ReviewedRuntime110Manifest.package)
            try await SystemInstalledPayloadVerifier().verify(expected: ReviewedRuntime110Manifest.package)
        } catch {
            let package = try PhysicalTestGate.packageURL(version: "1.1.0")
            let verified = try await RuntimePackageVerifier.system.verify(
                packageAt: package,
                against: ReviewedRuntime110Manifest.package
            )
            try await PhysicalSignedAppInstallHelper().install(verified)
            _ = try await SystemInstalledReceiptVerifier().verify(expected: ReviewedRuntime110Manifest.package)
            try await SystemInstalledPayloadVerifier().verify(expected: ReviewedRuntime110Manifest.package)
        }
        return try await bridge.system.start(.init(healthTimeoutSeconds: 60))
    }
}
