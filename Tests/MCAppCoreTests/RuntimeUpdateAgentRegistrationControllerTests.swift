@testable import MCAppCore
import MCSystemLifecycle
import Testing

@MainActor
@Suite("Runtime update agent registration controller")
struct UpdateAgentRegistrationControllerTests {
    @Test func `publishes approval requirement after enabling checks`() async {
        let service = RecordingRuntimeUpdateAgentRegistrar(result: .requiresApproval)
        let controller = RuntimeUpdateAgentRegistrationController(service: service)

        await controller.reconcile(enabled: true)

        #expect(controller.status == .requiresApproval)
        #expect(!controller.isReconciling)
        #expect(service.enabledValues == [true])
    }

    @Test func `registration failure is redacted and does not claim enabled`() async {
        let service = RecordingRuntimeUpdateAgentRegistrar(result: .enabled, fails: true)
        let controller = RuntimeUpdateAgentRegistrationController(service: service)

        await controller.reconcile(enabled: true)

        #expect(controller.status == .unknown)
        #expect(controller.errorCode == "update-agent.registration-failed")
    }
}

private final class RecordingRuntimeUpdateAgentRegistrar: RuntimeUpdateAgentRegistering, @unchecked Sendable {
    let result: RuntimeUpdateAgentRegistrationStatus
    let fails: Bool
    private(set) var enabledValues: [Bool] = []

    init(result: RuntimeUpdateAgentRegistrationStatus, fails: Bool = false) {
        self.result = result
        self.fails = fails
    }

    func status() async -> RuntimeUpdateAgentRegistrationStatus {
        result
    }

    func reconcile(enabled: Bool) async throws -> RuntimeUpdateAgentRegistrationStatus {
        enabledValues.append(enabled)
        if fails {
            throw RecordingUpdateAgentError.failed
        }
        return result
    }

    func openApprovalSettings() {}
}

private enum RecordingUpdateAgentError: Error {
    case failed
}
