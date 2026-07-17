import MCSystemLifecycle
import Observation

@MainActor
@Observable
public final class RuntimeUpdateAgentRegistrationController {
    public private(set) var status: RuntimeUpdateAgentRegistrationStatus = .notRegistered
    public private(set) var isReconciling = false
    public private(set) var errorCode: String?

    @ObservationIgnored private let service: any RuntimeUpdateAgentRegistering

    public init(service: any RuntimeUpdateAgentRegistering) {
        self.service = service
    }

    public func reconcile(enabled: Bool) async {
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }
        do {
            status = try await service.reconcile(enabled: enabled)
            errorCode = nil
        } catch is CancellationError {
            return
        } catch {
            status = .unknown
            errorCode = "update-agent.registration-failed"
        }
    }

    public func openApprovalSettings() {
        service.openApprovalSettings()
    }
}

public actor SimulatedRuntimeUpdateAgentRegistrar: RuntimeUpdateAgentRegistering {
    private var current: RuntimeUpdateAgentRegistrationStatus = .notRegistered

    public init() {}

    public func status() -> RuntimeUpdateAgentRegistrationStatus { current }

    public func reconcile(enabled: Bool) -> RuntimeUpdateAgentRegistrationStatus {
        current = enabled ? .enabled : .notRegistered
        return current
    }

    public nonisolated func openApprovalSettings() {}
}
