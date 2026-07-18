import Foundation
@testable import MCAppCore
import MCContracts
import MCModel
import Testing

@MainActor
@Suite("Operation executor")
struct OperationExecutorTests {
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["MACCONTAINER_PHYSICAL_MACHINE_TEST"] == "1",
            "Explicit physical machine authorization is required"
        )
    )
    func `physical machine template creates a machine visible to the production resource provider`() async throws {
        let name = "mct-machine-e2e-\(UUID().uuidString.lowercased())"
        let contract = try ContractRepository.bundled(version: .init(major: 1, minor: 1, patch: 0))
        let activities = ActivityCenter()
        let executor = OperationExecutor(
            contract: contract,
            capabilities: Set(contract.operations.map(\.id)),
            dispatcher: BridgeOperationDispatcher(),
            activities: activities
        )
        let provider = ProductionRuntimeResourceProvider()
        let draft = machineCreateDraft(name: name)

        do {
            _ = try await executor.execute(draft)
            let machines = try await provider.load(.machines)
            #expect(machines.contains { $0.id == name && $0.status == "Running" })
            _ = try await provider.stop(.machines, ids: [name])
            _ = try await provider.delete(.machines, ids: [name])
        } catch {
            _ = try? await provider.stop(.machines, ids: [name])
            _ = try? await provider.delete(.machines, ids: [name])
            throw error
        }
    }

    @Test
    func `exposes every embedded operation exactly once`() throws {
        let contract = try ContractRepository.bundled(version: .init(major: 1, minor: 1, patch: 0))
        let executor = OperationExecutor(
            contract: contract,
            capabilities: Set(contract.operations.map(\.id)),
            dispatcher: RecordingDispatcher(),
            activities: ActivityCenter()
        )

        #expect(executor.supportedOperationIDs == Set(contract.operations.map(\.id)))
        #expect(executor.supportedOperationIDs.count == 61)
    }

    @Test
    func `draft factory materializes every affecting parameter`() throws {
        let contract = try ContractRepository.bundled(version: .init(major: 1, minor: 1, patch: 0))
        let factory = OperationDraftFactory()
        var fieldCount = 0

        for operation in contract.operations {
            let draft = factory.makeDraft(for: operation)
            #expect(draft.operationID == operation.id)
            #expect(Set(draft.fields.keys) == Set(operation.parameters.map(\.id)))
            fieldCount += draft.fields.count
        }

        #expect(fieldCount == 352)
    }

    @Test
    func `rejects unknown and unavailable operations before dispatch`() async throws {
        let contract = try ContractRepository.bundled(version: .init(major: 1, minor: 1, patch: 0))
        let dispatcher = RecordingDispatcher()
        let executor = OperationExecutor(
            contract: contract,
            capabilities: [],
            dispatcher: dispatcher,
            activities: ActivityCenter()
        )

        await #expect(throws: OperationExecutorError.unknownOperation("not.real")) {
            try await executor.execute(OperationDraft(operationID: "not.real", fields: [:]))
        }
        await #expect(throws: OperationExecutorError.capabilityUnavailable("system.status")) {
            try await executor.execute(OperationDraft(operationID: "system.status", fields: [:]))
        }
        #expect(await dispatcher.operationIDs().isEmpty)
    }

    @Test
    func `validation failure never reaches runtime`() async throws {
        let contract = try ContractRepository.bundled(version: .init(major: 1, minor: 1, patch: 0))
        let dispatcher = RecordingDispatcher()
        let executor = OperationExecutor(
            contract: contract,
            capabilities: ["core.run"],
            dispatcher: dispatcher,
            activities: ActivityCenter()
        )

        await #expect(throws: (any Error).self) {
            try await executor.execute(OperationDraft(operationID: "core.run", fields: [:]))
        }
        #expect(await dispatcher.operationIDs().isEmpty)
    }

    @Test
    func `successful dispatch is reflected in activity center`() async throws {
        let contract = try ContractRepository.bundled(version: .init(major: 1, minor: 1, patch: 0))
        let activities = ActivityCenter()
        let dispatcher = RecordingDispatcher()
        let executor = OperationExecutor(
            contract: contract,
            capabilities: ["system.status"],
            dispatcher: dispatcher,
            activities: activities
        )

        let result = try await executor.execute(OperationDraft(operationID: "system.status", fields: [:]))

        #expect(result.operationID == "system.status")
        #expect(await dispatcher.operationIDs() == ["system.status"])
        let activity = try #require(activities.activities[result.activityID])
        #expect(activity.outcome == .succeeded)
        #expect(activity.phaseKey == "activity.phase.completed")
    }

    @Test
    func `fake application environment executes through its injected dispatcher`() async throws {
        let dispatcher = RecordingDispatcher()
        let state = AppState(environment: AppEnvironment(
            mode: .fakeRuntime,
            operationDispatcher: dispatcher
        ))

        let result = try await state.operationExecutor.execute(
            OperationDraft(operationID: "system.status", fields: [:])
        )

        #expect(result.summary == "ok")
        #expect(await dispatcher.operationIDs() == ["system.status"])
        #expect(state.activities.activities[result.activityID]?.outcome == .succeeded)
    }

    @Test
    func `successful machine creation refreshes the machine inventory`() async throws {
        let state = AppState(environment: AppEnvironment(mode: .fakeRuntime))
        #expect(state.resourceBrowser.resources(for: .machines).isEmpty)
        let draft = machineCreateDraft(name: "machine-test")

        _ = try await state.executeOperation(draft)

        #expect(state.resourceBrowser.resources(for: .machines).isEmpty == false)
    }

    @Test
    func `failed dispatch preserves a redacted diagnostic in the activity record`() async throws {
        let contract = try ContractRepository.bundled(version: .init(major: 1, minor: 1, patch: 0))
        let activities = ActivityCenter()
        let executor = OperationExecutor(
            contract: contract,
            capabilities: ["system.status"],
            dispatcher: FailingDispatcher(),
            activities: activities
        )

        await #expect(throws: DiagnosticFailure.self) {
            try await executor.execute(OperationDraft(operationID: "system.status", fields: [:]))
        }

        let activity = try #require(activities.activities.values.first)
        #expect(activity.error?.domain == .system)
        #expect(activity.error?.diagnosticDetail.contains("machine backend failed") == true)
    }
}

private func machineCreateDraft(name: String) -> OperationDraft {
    OperationDraft(operationID: "machines.create", fields: [
        "image": DraftField(value: .string("alpine:latest"), source: .userOverride),
        "name": DraftField(value: .string(name), source: .scenarioRule),
        "cpus": DraftField(value: .integer(2), source: .hostRecommendation),
        "memory": DraftField(value: .bytes(2_147_483_648), source: .hostRecommendation),
        "homeMount": DraftField(value: .string("none"), source: .scenarioRule),
        "nestedVirtualization": DraftField(value: .bool(false), source: .scenarioRule),
        "noBoot": DraftField(value: .bool(false), source: .scenarioRule)
    ])
}

private actor RecordingDispatcher: OperationDispatching {
    private var recordedOperationIDs: [String] = []

    func dispatch(_ draft: OperationDraft) async throws -> OperationDispatchResult {
        recordedOperationIDs.append(draft.operationID)
        return OperationDispatchResult(summary: "ok")
    }

    func operationIDs() -> [String] {
        recordedOperationIDs
    }
}

private enum DiagnosticFailure: Error {
    case message(String)
}

private struct FailingDispatcher: OperationDispatching {
    func dispatch(_: OperationDraft) async throws -> OperationDispatchResult {
        throw DiagnosticFailure.message("machine backend failed")
    }
}
