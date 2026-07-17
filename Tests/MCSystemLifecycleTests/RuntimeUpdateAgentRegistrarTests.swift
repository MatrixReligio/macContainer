@testable import MCSystemLifecycle
import Testing

@Suite("Runtime update agent registration")
struct RuntimeUpdateAgentRegistrarTests {
    @Test func `enabling registers packaged launch agent and verifies status`() async throws {
        let backend = RecordingUpdateAgentBackend(status: .notRegistered)
        let registrar = RuntimeUpdateAgentRegistrar(backend: backend)

        let status = try await registrar.reconcile(enabled: true)

        #expect(status == .enabled)
        #expect(backend.registerCalls == 1)
    }

    @Test func `pending system approval is a stable status rather than a failed toggle`() async throws {
        let backend = RecordingUpdateAgentBackend(status: .notRegistered, approvalRequired: true)
        let registrar = RuntimeUpdateAgentRegistrar(backend: backend)

        let status = try await registrar.reconcile(enabled: true)

        #expect(status == .requiresApproval)
        #expect(backend.registerCalls == 1)
    }

    @Test func `disabling unregisters even when approval is pending`() async throws {
        let backend = RecordingUpdateAgentBackend(status: .requiresApproval)
        let registrar = RuntimeUpdateAgentRegistrar(backend: backend)

        let status = try await registrar.reconcile(enabled: false)

        #expect(status == .notRegistered)
        #expect(backend.unregisterCalls == 1)
    }
}

private final class RecordingUpdateAgentBackend: RuntimeUpdateAgentRegistrationBackend, @unchecked Sendable {
    private var storedStatus: RuntimeUpdateAgentRegistrationStatus
    private let approvalRequired: Bool
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0

    init(status: RuntimeUpdateAgentRegistrationStatus, approvalRequired: Bool = false) {
        storedStatus = status
        self.approvalRequired = approvalRequired
    }

    func status() -> RuntimeUpdateAgentRegistrationStatus { storedStatus }

    func register() throws {
        registerCalls += 1
        storedStatus = approvalRequired ? .requiresApproval : .enabled
        if approvalRequired { throw RecordingUpdateAgentError.approvalRequired }
    }

    func unregister() throws {
        unregisterCalls += 1
        storedStatus = .notRegistered
    }
}

private enum RecordingUpdateAgentError: Error {
    case approvalRequired
}
