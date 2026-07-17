import Foundation
@testable import MCContainerBridge
import MCModel
import Testing
import TestSupport

@Suite("Runtime bridge contracts")
struct RuntimeBridgeContractTests {
    @Test func `production bridge defers upstream clients until an operation needs them`() {
        let counter = RuntimeClientConstructionCounter()
        let factories = AppleRuntimeClientFactories(
            container: {
                counter.increment()
                return .init()
            },
            machine: {
                counter.increment()
                return .init()
            },
            network: {
                counter.increment()
                return .init()
            }
        )

        _ = AppleRuntimeBridge(clientFactories: factories)

        #expect(counter.value == 0)
    }

    @Test func `fake bridge can represent every domain`() async throws {
        let bridge = FakeRuntimeBridge()

        #expect(try await bridge.containers.list().isEmpty)
        #expect(try await bridge.images.list().isEmpty)
        #expect(try await bridge.builders.status().state == .stopped)
        #expect(try await bridge.networks.list().isEmpty)
        #expect(try await bridge.volumes.list().isEmpty)
        #expect(try await bridge.registries.list().isEmpty)
        #expect(try await bridge.machines.list().isEmpty)
        #expect(try await bridge.system.status().state == .stopped)
        #expect(try await bridge.dns.list().isEmpty)
        #expect(try await bridge.configuration.load() == .empty)

        #expect(await bridge.recordedInvocations().map(\.operationID) == [
            "containers.list",
            "images.list",
            "builder.status",
            "networks.list",
            "volumes.list",
            "registries.list",
            "machines.list",
            "system.status",
            "dns.list",
            "configuration.load"
        ])
    }

    @Test func `recorded invocations reject secret material`() {
        #expect(throws: RecordedInvocationError.sensitiveArgument("password")) {
            try RecordedInvocation(
                operationID: "registries.login",
                resourceIDs: ["registry.example.com"],
                redactedArguments: ["password": "must-not-be-recorded"]
            )
        }
        #expect(throws: RecordedInvocationError.sensitiveArgument("headers")) {
            try RecordedInvocation(
                operationID: "images.pull",
                resourceIDs: ["example:latest"],
                redactedArguments: ["headers": "Authorization: Bearer credential"]
            )
        }
    }

    @Test func `app owned values have stable codable round trips`() throws {
        let summary = ContainerSummary(
            id: "container-id",
            name: "example",
            imageReference: "alpine:latest",
            state: .running,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let request = ContainerCreateRequest(
            name: "example",
            imageReference: "alpine:latest",
            resources: RuntimeResources(cpuCount: 2, memoryBytes: 2_147_483_648)
        )

        #expect(try roundTrip(summary) == summary)
        #expect(try roundTrip(request) == request)
    }

    private func roundTrip<Value: Codable>(_ value: Value) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
    }
}

private final class RuntimeClientConstructionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
