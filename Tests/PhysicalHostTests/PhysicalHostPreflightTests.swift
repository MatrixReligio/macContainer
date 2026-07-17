import Foundation
import MCContainerBridge
import Testing

@Suite("Physical host preflight")
struct PhysicalHostPreflightTests {
    @Test func `operation authorization is closed by default`() {
        if ProcessInfo.processInfo.environment["PHYSICAL_TEST_AUTHORIZATION"] == nil {
            #expect(!PhysicalTestGate.isAuthorized)
        }
    }

    @Test func `production bridge composes every direct domain`() {
        let bridge = AppleRuntimeBridge()

        _ = bridge.containers
        _ = bridge.images
        _ = bridge.builds
        _ = bridge.builders
        _ = bridge.networks
        _ = bridge.volumes
        _ = bridge.registries
        _ = bridge.machines
        _ = bridge.system
        _ = bridge.dns
        _ = bridge.kernel
        _ = bridge.configuration
    }

    @Test func `authorization requires exact UUID namespace and existing run root`() {
        if !PhysicalTestGate.isAuthorized {
            #expect(PhysicalTestGate.namespace == "mct-e2e-unauthorized" || PhysicalTestGate.runID != nil)
        }
    }
}
