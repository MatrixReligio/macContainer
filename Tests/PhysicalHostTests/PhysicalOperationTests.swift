import Foundation
import MCContainerBridge
import MCModel
import Testing

@Suite(
    "Authorized physical runtime operations",
    .serialized,
    .enabled(if: PhysicalTestGate.isAuthorized, "PHYSICAL_TEST_AUTHORIZATION missing or mismatched")
)
struct PhysicalOperationTests {
    @Test func `system and configuration domains use the production bridge`() async throws {
        let bridge = try PhysicalTestGate.productionBridge()
        let started = try await bridge.system.start(.init(healthTimeoutSeconds: 60))
        #expect(started.state == .running)
        #expect(try await bridge.system.status().state == .running)
        #expect(try await bridge.system.version().version == "1.1.0")
        _ = try await bridge.system.diskUsage()
        _ = try await bridge.configuration.load()
    }

    @Test func `resource inventories are reachable without a command line subprocess`() async throws {
        let bridge = try PhysicalTestGate.productionBridge()

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
}
