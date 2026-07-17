import ServiceManagement

public enum RuntimeUpdateAgentRegistrationStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unknown
}

public protocol RuntimeUpdateAgentRegistrationBackend: Sendable {
    func status() -> RuntimeUpdateAgentRegistrationStatus
    func register() throws
    func unregister() throws
}

public protocol RuntimeUpdateAgentRegistering: Sendable {
    func status() async -> RuntimeUpdateAgentRegistrationStatus
    func reconcile(enabled: Bool) async throws -> RuntimeUpdateAgentRegistrationStatus
    func openApprovalSettings()
}

public actor RuntimeUpdateAgentRegistrar: RuntimeUpdateAgentRegistering {
    public static let agentPlistName = "container.matrixreligio.com.update-agent.plist"

    private let backend: any RuntimeUpdateAgentRegistrationBackend

    public init(backend: any RuntimeUpdateAgentRegistrationBackend) {
        self.backend = backend
    }

    public init(plistName: String = RuntimeUpdateAgentRegistrar.agentPlistName) {
        backend = SystemRuntimeUpdateAgentRegistrationBackend(plistName: plistName)
    }

    public func status() -> RuntimeUpdateAgentRegistrationStatus {
        backend.status()
    }

    public func reconcile(enabled: Bool) async throws -> RuntimeUpdateAgentRegistrationStatus {
        if enabled {
            return try enable()
        }
        return try disable()
    }

    private func enable() throws -> RuntimeUpdateAgentRegistrationStatus {
        switch backend.status() {
        case .enabled, .requiresApproval:
            return backend.status()
        case .notRegistered, .notFound:
            do {
                try backend.register()
            } catch {
                guard backend.status() == .requiresApproval else { throw error }
            }
        case .unknown:
            throw RuntimeUpdateAgentRegistrationError.ambiguousStatus
        }
        return switch backend.status() {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: throw RuntimeUpdateAgentRegistrationError.agentMissing
        case .notRegistered, .unknown:
            throw RuntimeUpdateAgentRegistrationError.registrationDidNotTakeEffect
        }
    }

    private func disable() throws -> RuntimeUpdateAgentRegistrationStatus {
        switch backend.status() {
        case .notRegistered, .notFound:
            return .notRegistered
        case .enabled, .requiresApproval:
            do {
                try backend.unregister()
            } catch {
                guard backend.status() == .notRegistered else { throw error }
            }
        case .unknown:
            throw RuntimeUpdateAgentRegistrationError.ambiguousStatus
        }
        guard backend.status() == .notRegistered else {
            throw RuntimeUpdateAgentRegistrationError.unregistrationDidNotTakeEffect
        }
        return .notRegistered
    }

    // Swift requires the access modifier before nonisolated here; SwiftLint's preferred order conflicts with it.
    // swiftlint:disable:next modifier_order
    public nonisolated func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

public final class SystemRuntimeUpdateAgentRegistrationBackend:
    RuntimeUpdateAgentRegistrationBackend,
    @unchecked Sendable
{
    private let service: SMAppService

    public init(plistName: String = RuntimeUpdateAgentRegistrar.agentPlistName) {
        service = SMAppService.agent(plistName: plistName)
    }

    public func status() -> RuntimeUpdateAgentRegistrationStatus {
        switch service.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .unknown
        }
    }

    public func register() throws {
        try service.register()
    }

    public func unregister() throws {
        try service.unregister()
    }
}

public enum RuntimeUpdateAgentRegistrationError: Error, Equatable, Sendable {
    case agentMissing
    case ambiguousStatus
    case registrationDidNotTakeEffect
    case unregistrationDidNotTakeEffect
}
