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
}
