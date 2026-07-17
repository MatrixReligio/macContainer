import Foundation
import ServiceManagement

public enum PrivilegedHelperRegistrationStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unknown
}

public protocol PrivilegedHelperRegistrationBackend: Sendable {
    func status() -> PrivilegedHelperRegistrationStatus
    func register() throws
    func unregister() throws
}

public protocol PrivilegedHelperRegistering: Sendable {
    func status() async -> PrivilegedHelperRegistrationStatus
    func ensureAvailable() async throws -> PrivilegedHelperRegistrationStatus
    func unregister() async throws
    func openApprovalSettings()
}

public actor PrivilegedHelperRegistrar: PrivilegedHelperRegistering {
    public static let daemonPlistName = "container.matrixreligio.com.helper.plist"

    private let backend: any PrivilegedHelperRegistrationBackend

    public init(backend: any PrivilegedHelperRegistrationBackend) {
        self.backend = backend
    }

    public init(plistName: String = PrivilegedHelperRegistrar.daemonPlistName) {
        backend = SystemHelperRegistrationBackend(plistName: plistName)
    }

    public func status() -> PrivilegedHelperRegistrationStatus {
        backend.status()
    }

    @discardableResult
    public func ensureAvailable() async throws -> PrivilegedHelperRegistrationStatus {
        switch backend.status() {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            try backend.register()
        case .unknown:
            throw PrivilegedHelperRegistrationError.ambiguousStatus
        case .notRegistered:
            try backend.register()
        }

        switch backend.status() {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            throw PrivilegedHelperRegistrationError.helperMissing
        case .notRegistered, .unknown:
            throw PrivilegedHelperRegistrationError.registrationDidNotTakeEffect
        }
    }

    public func unregister() async throws {
        switch backend.status() {
        case .notRegistered, .notFound:
            return
        case .enabled, .requiresApproval:
            try backend.unregister()
        case .unknown:
            throw PrivilegedHelperRegistrationError.ambiguousStatus
        }

        guard backend.status() == .notRegistered else {
            throw PrivilegedHelperRegistrationError.unregistrationDidNotTakeEffect
        }
    }

    // Swift requires the access modifier before nonisolated here; SwiftLint's preferred order conflicts with it.
    // swiftlint:disable:next modifier_order
    public nonisolated func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

public final class SystemHelperRegistrationBackend: PrivilegedHelperRegistrationBackend, @unchecked Sendable {
    private let service: SMAppService

    public init(plistName: String = PrivilegedHelperRegistrar.daemonPlistName) {
        service = SMAppService.daemon(plistName: plistName)
    }

    public func status() -> PrivilegedHelperRegistrationStatus {
        switch service.status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .unknown
        }
    }

    public func register() throws {
        try service.register()
    }

    public func unregister() throws {
        try service.unregister()
    }
}

public enum PrivilegedHelperRegistrationError: Error, Equatable, Sendable {
    case ambiguousStatus
    case helperMissing
    case registrationDidNotTakeEffect
    case unregistrationDidNotTakeEffect
}
