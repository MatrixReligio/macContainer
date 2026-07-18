@testable import MCAppCore
import MCContracts
import MCModel
import Testing
import TestSupport

@Suite("Bridge operation dispatcher")
struct BridgeOperationDispatcherTests {
    @Test func `dispatcher covers every reviewed contract operation`() throws {
        let contract = try ContractRepository.bundled(
            version: RuntimeVersion(major: 1, minor: 1, patch: 0)
        )

        #expect(BridgeOperationDispatcher.supportedOperationIDs == Set(contract.operations.map(\.id)))
    }

    @Test func `representative domains invoke direct bridge without shell`() async throws {
        let bridge = FakeRuntimeBridge()
        let dispatcher = BridgeOperationDispatcher(bridge: bridge)

        _ = try await dispatcher.dispatch(.init(operationID: "containers.stop", fields: [
            "containerIDs": .init(value: .strings(["one", "two"]), source: .userOverride),
            "timeoutSeconds": .init(value: .integer(15), source: .userOverride)
        ]))
        _ = try await dispatcher.dispatch(.init(operationID: "images.list", fields: [:]))
        _ = try await dispatcher.dispatch(.init(operationID: "system.version", fields: [:]))
        _ = try await dispatcher.dispatch(.init(operationID: "dns.list", fields: [:]))
        _ = try await dispatcher.dispatch(.init(operationID: "configuration.manage", fields: [:]))

        #expect(await bridge.recordedInvocations().map(\.operationID) == [
            "containers.stop", "images.list", "system.version", "dns.list",
            "configuration.load", "configuration.preview"
        ])
    }

    @Test func `registry credential never appears in result summary`() async throws {
        let dispatcher = BridgeOperationDispatcher(bridge: FakeRuntimeBridge())
        let draft = OperationDraft(operationID: "registries.login", fields: [
            "server": .init(value: .string("registry.example"), source: .userOverride),
            "username": .init(value: .string("user"), source: .userOverride),
            "password": .init(value: .secret("super-secret"), source: .userOverride)
        ])

        let result = try await dispatcher.dispatch(draft)

        #expect(!result.summary.contains("super-secret"))
        #expect(result.summary == "Signed in to registry.example")
    }

    @Test func `machine create boots by default and honors no boot`() async throws {
        let bootingBridge = FakeRuntimeBridge()
        let bootingDispatcher = BridgeOperationDispatcher(bridge: bootingBridge)
        _ = try await bootingDispatcher.dispatch(machineCreateDraft(name: "booted", noBoot: false))

        #expect(await bootingBridge.recordedInvocations().map(\.operationID) == [
            "machines.create", "machines.start"
        ])

        let stoppedBridge = FakeRuntimeBridge()
        let stoppedDispatcher = BridgeOperationDispatcher(bridge: stoppedBridge)
        _ = try await stoppedDispatcher.dispatch(machineCreateDraft(name: "stopped", noBoot: true))

        #expect(await stoppedBridge.recordedInvocations().map(\.operationID) == ["machines.create"])
    }

    @Test func `network and volume creation preserve every native setting`() async throws {
        let bridge = FakeRuntimeBridge()
        let dispatcher = BridgeOperationDispatcher(bridge: bridge)

        _ = try await dispatcher.dispatch(.init(operationID: "networks.create", fields: [
            "name": .init(value: .string("private-net"), source: .userOverride),
            "internal": .init(value: .bool(true), source: .userOverride),
            "ipv4Subnet": .init(value: .string("10.44.0.0/24"), source: .userOverride),
            "ipv6Subnet": .init(value: .string("fd44::/64"), source: .userOverride),
            "plugin": .init(value: .string("container-network-vmnet"), source: .upstreamDefault),
            "options": .init(value: .keyValues([.init(key: "mtu", value: "1400")]), source: .userOverride)
        ]))
        _ = try await dispatcher.dispatch(.init(operationID: "volumes.create", fields: [
            "name": .init(value: .string("data"), source: .userOverride),
            "size": .init(value: .bytes(1_073_741_824), source: .userOverride),
            "driverOptions": .init(value: .keyValues([.init(key: "format", value: "ext4")]), source: .userOverride)
        ]))

        let invocations = await bridge.recordedInvocations()
        #expect(invocations[0].redactedArguments["subnet"] == "10.44.0.0/24")
        #expect(invocations[0].redactedArguments["ipv6Subnet"] == "fd44::/64")
        #expect(invocations[0].redactedArguments["hostOnly"] == "true")
        #expect(invocations[0].redactedArguments["options"] == "mtu=1400")
        #expect(invocations[1].redactedArguments["sizeBytes"] == "1073741824")
        #expect(invocations[1].redactedArguments["driverOptions"] == "format=ext4")
    }

    private func machineCreateDraft(name: String, noBoot: Bool) -> OperationDraft {
        OperationDraft(operationID: "machines.create", fields: [
            "image": .init(value: .string("ghcr.io/example/machine:1"), source: .userOverride),
            "name": .init(value: .string(name), source: .userOverride),
            "cpus": .init(value: .integer(2), source: .hostRecommendation),
            "memory": .init(value: .bytes(2_147_483_648), source: .hostRecommendation),
            "noBoot": .init(value: .bool(noBoot), source: .scenarioRule)
        ])
    }
}
