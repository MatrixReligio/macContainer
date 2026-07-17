import Foundation
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
        #expect(try await bridge.system.status().state == .running)
        #expect(try await bridge.system.version().version == "1.1.0")
        _ = try await bridge.system.diskUsage()
        _ = try await bridge.configuration.load()
    }

    @Test func `resource inventories are reachable without a command line subprocess`() async throws {
        let bridge = try PhysicalTestGate.productionBridge()
        _ = try await ensureRuntime(bridge: bridge)

        _ = try await bridge.containers.list()
        _ = try await bridge.images.list()
        _ = try await bridge.builders.status()
        _ = try await bridge.networks.list()
        _ = try await bridge.volumes.list()
        _ = try await bridge.registries.list()
        _ = try await bridge.machines.list()
        _ = try await bridge.dns.list()
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
            _ = try await HelperClient().install(verified)
            _ = try await SystemInstalledReceiptVerifier().verify(expected: ReviewedRuntime110Manifest.package)
            try await SystemInstalledPayloadVerifier().verify(expected: ReviewedRuntime110Manifest.package)
        }
        return try await bridge.system.start(.init(healthTimeoutSeconds: 60))
    }
}
