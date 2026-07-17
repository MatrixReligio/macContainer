@testable import MCAppCore
import MCContracts
import MCModel
import Testing

@MainActor
@Suite("Operation executor")
struct OperationExecutorTests {
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
