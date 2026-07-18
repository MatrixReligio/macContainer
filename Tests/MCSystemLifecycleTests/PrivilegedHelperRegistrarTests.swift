import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("Privileged helper registration")
struct PrivilegedHelperRegistrarTests {
    @Test func `already enabled helper is not registered twice`() async throws {
        let backend = RecordingHelperRegistrationBackend(statuses: [.enabled])
        let registrar = PrivilegedHelperRegistrar(backend: backend)

        #expect(try await registrar.ensureAvailable() == .enabled)
        #expect(backend.actions == ["status"])
    }

    @Test func `new registration reports required system approval without claiming success`() async throws {
        let backend = RecordingHelperRegistrationBackend(statuses: [.notRegistered, .requiresApproval])
        let registrar = PrivilegedHelperRegistrar(backend: backend)

        #expect(try await registrar.ensureAvailable() == .requiresApproval)
        #expect(backend.actions == ["status", "register", "status"])
    }

    @Test func `missing helper and ambiguous post registration status fail closed`() async {
        let missingBackend = RecordingHelperRegistrationBackend(statuses: [.notFound, .notFound])
        let missing = PrivilegedHelperRegistrar(
            backend: missingBackend
        )
        await #expect(throws: PrivilegedHelperRegistrationError.helperMissing) {
            try await missing.ensureAvailable()
        }
        #expect(missingBackend.actions == ["status", "register", "status"])

        let ambiguous = PrivilegedHelperRegistrar(
            backend: RecordingHelperRegistrationBackend(statuses: [.notRegistered, .notRegistered])
        )
        await #expect(throws: PrivilegedHelperRegistrationError.registrationDidNotTakeEffect) {
            try await ambiguous.ensureAvailable()
        }
    }

    @Test func `unregister is idempotent and verifies absence`() async throws {
        let enabled = RecordingHelperRegistrationBackend(statuses: [.enabled, .notRegistered])
        let registrar = PrivilegedHelperRegistrar(backend: enabled)
        try await registrar.unregister()
        #expect(enabled.actions == ["status", "unregister", "status"])

        let absent = RecordingHelperRegistrationBackend(statuses: [.notRegistered])
        try await PrivilegedHelperRegistrar(backend: absent).unregister()
        #expect(absent.actions == ["status"])
    }
}

private final class RecordingHelperRegistrationBackend: PrivilegedHelperRegistrationBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [PrivilegedHelperRegistrationStatus]
    private var actionStorage: [String] = []

    init(statuses: [PrivilegedHelperRegistrationStatus]) {
        self.statuses = statuses
    }

    var actions: [String] {
        lock.withLock { actionStorage }
    }

    func status() -> PrivilegedHelperRegistrationStatus {
        lock.withLock {
            actionStorage.append("status")
            return statuses.isEmpty ? .unknown : statuses.removeFirst()
        }
    }

    func register() throws {
        lock.withLock { actionStorage.append("register") }
    }

    func unregister() throws {
        lock.withLock { actionStorage.append("unregister") }
    }
}
