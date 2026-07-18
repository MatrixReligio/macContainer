import Foundation
@testable import MCAppCore
import MCModel
import Testing

@MainActor
@Suite("Machine terminal opening")
struct MachineTerminalOpenerTests {
    @Test func `app state opens the selected existing machine without creating another machine`() async throws {
        let opener = RecordingMachineTerminalOpener()
        let state = AppState(environment: AppEnvironment(
            mode: .fakeRuntime,
            machineTerminalOpener: opener
        ))

        _ = try await state.openMachineTerminal(machineID: "machine-alpine")

        #expect(await opener.openedMachineIDs == ["machine-alpine"])
    }

    @Test func `built in machine image is prepared before machine creation`() async throws {
        let preparer = RecordingMachineImagePreparer()
        let dispatcher = RecordingOperationDispatcher()
        let state = AppState(environment: AppEnvironment(
            mode: .fakeRuntime,
            operationDispatcher: dispatcher,
            machineImagePreparer: preparer
        ))
        let draft = OperationDraft(
            operationID: "machines.create",
            fields: [
                "image": DraftField(value: .string(MachineImageDefaults.reference), source: .scenarioRule),
                "name": DraftField(value: .string("test-machine"), source: .userOverride),
                "cpus": DraftField(value: .integer(2), source: .hostRecommendation),
                "memory": DraftField(value: .bytes(1_073_741_824), source: .hostRecommendation),
                "homeMount": DraftField(value: .string("none"), source: .scenarioRule),
                "nestedVirtualization": DraftField(value: .bool(false), source: .scenarioRule),
                "noBoot": DraftField(value: .bool(false), source: .scenarioRule)
            ]
        )

        _ = try await state.executeOperation(draft)

        #expect(await preparer.references == [MachineImageDefaults.reference])
        #expect(await dispatcher.operationIDs == ["machines.create"])
    }

    @Test func `built in machine definition contains the bootable Alpine init system`() throws {
        let url = try #require(MachineImageDefaults.bundledContainerfileURL())
        let definition = try String(contentsOf: url, encoding: .utf8)

        #expect(definition.contains("FROM alpine:3.22"))
        #expect(definition.contains("apk add --no-cache alpine-base"))
        #expect(definition.contains("CMD [\"/sbin/init\"]"))
    }
}

private actor RecordingMachineTerminalOpener: MachineTerminalOpening {
    private(set) var openedMachineIDs: [String] = []

    func open(machineID: String) async throws -> any ProcessSession {
        openedMachineIDs.append(machineID)
        return EmptyProcessSession()
    }
}

private actor EmptyProcessSession: ProcessSession {
    nonisolated let id = "test-machine-terminal"
    nonisolated let output = AsyncThrowingStream<ProcessOutputChunk, any Error> { continuation in
        continuation.finish()
    }

    func send(_: Data) async throws {}
    func resize(columns _: Int, rows _: Int) async throws {}
    func wait() async throws -> ProcessExit {
        .init(code: 0)
    }

    func detach() async throws {}
    func terminate(signal _: String) async throws {}
}

private actor RecordingMachineImagePreparer: MachineImagePreparing {
    private(set) var references: [String] = []

    func prepareIfNeeded(imageReference: String) async throws {
        references.append(imageReference)
    }
}

private actor RecordingOperationDispatcher: OperationDispatching {
    private(set) var operationIDs: [String] = []

    func dispatch(_ draft: OperationDraft) async throws -> OperationDispatchResult {
        operationIDs.append(draft.operationID)
        return .init(summary: "done")
    }
}
