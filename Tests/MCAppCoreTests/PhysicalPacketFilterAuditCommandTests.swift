import Foundation
@testable import MCAppCore
import MCSystemLifecycle
import Testing

@Suite("Physical packet-filter audit command")
struct PhysicalPacketFilterAuditCommandTests {
    @Test func `accepts only an exact authorized output inside the private temporary root`() async throws {
        let runID = UUID()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mc-pf-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("packet-filter-\(runID.uuidString.lowercased()).json")

        let command = try #require(PhysicalPacketFilterAuditCommand(
            arguments: ["--physical-pf-audit-output=\(output.path)"],
            environment: [
                "PHYSICAL_AUDIT_AUTHORIZATION": runID.uuidString.lowercased(),
                "PHYSICAL_AUDIT_ROOT": root.path
            ],
            helper: FixturePacketFilterAuditor(residuePresent: false)
        ))
        try await command.execute()
        #expect(try JSONDecoder().decode(
            PhysicalPacketFilterAuditResult.self,
            from: Data(contentsOf: output)
        ) == .init(verified: true, residuePresent: false))

        #expect(PhysicalPacketFilterAuditCommand(
            arguments: ["--physical-pf-audit-output=/tmp/other.json"],
            environment: [
                "PHYSICAL_AUDIT_AUTHORIZATION": runID.uuidString.lowercased(),
                "PHYSICAL_AUDIT_ROOT": root.path
            ],
            helper: FixturePacketFilterAuditor(residuePresent: false)
        ) == nil)
    }

    @Test func `packet filter audit persists only a non-sensitive failure identity`() async throws {
        let runID = UUID()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mc-pf-audit-error-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("packet-filter-\(runID.uuidString.lowercased()).json")
        let command = try #require(PhysicalPacketFilterAuditCommand(
            arguments: ["--physical-pf-audit-output=\(output.path)"],
            environment: [
                "PHYSICAL_AUDIT_AUTHORIZATION": runID.uuidString.lowercased(),
                "PHYSICAL_AUDIT_ROOT": root.path
            ],
            helper: FailingPacketFilterAuditor()
        ))

        try await command.execute()
        let result = try JSONDecoder().decode(
            PhysicalPacketFilterAuditResult.self,
            from: Data(contentsOf: output)
        )
        #expect(result.verified == false)
        #expect(result.residuePresent == false)
        #expect(result.errorDomain == "MCAppCoreTests.PacketFilterAuditFailure")
        #expect(result.errorCode == 19)
    }

    @Test func `helper bootstrap reports the exact registration state`() async throws {
        let runID = UUID()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mc-helper-bootstrap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("helper-bootstrap-\(runID.uuidString.lowercased()).json")
        let registrar = FixturePhysicalHelperRegistrar(result: .enabled)
        let command = try #require(PhysicalHelperBootstrapCommand(
            arguments: ["--physical-helper-bootstrap-output=\(output.path)"],
            environment: [
                "PHYSICAL_AUDIT_AUTHORIZATION": runID.uuidString.lowercased(),
                "PHYSICAL_AUDIT_ROOT": root.path
            ],
            registrar: registrar
        ))

        try await command.execute()
        #expect(try JSONDecoder().decode(
            PhysicalHelperBootstrapResult.self,
            from: Data(contentsOf: output)
        ).status == "enabled")
        #expect(await registrar.ensureCalls == 1)
    }

    @Test func `helper bootstrap persists a non-sensitive failure result`() async throws {
        let runID = UUID()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mc-helper-bootstrap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("helper-bootstrap-\(runID.uuidString.lowercased()).json")
        let command = try #require(PhysicalHelperBootstrapCommand(
            arguments: ["--physical-helper-bootstrap-output=\(output.path)"],
            environment: [
                "PHYSICAL_AUDIT_AUTHORIZATION": runID.uuidString.lowercased(),
                "PHYSICAL_AUDIT_ROOT": root.path
            ],
            registrar: FixturePhysicalHelperRegistrar(result: .notRegistered, shouldFail: true)
        ))

        try await command.execute()
        let result = try JSONDecoder().decode(
            PhysicalHelperBootstrapResult.self,
            from: Data(contentsOf: output)
        )
        #expect(result.status == "failed")
        #expect(result.errorDomain == "MCAppCoreTests.PhysicalHelperBootstrapFailure")
        #expect(result.errorCode == 1)
    }

    @Test func `helper bootstrap reports approval requested even when registration throws`() async throws {
        let runID = UUID()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mc-helper-approval-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("helper-bootstrap-\(runID.uuidString.lowercased()).json")
        let command = try #require(PhysicalHelperBootstrapCommand(
            arguments: ["--physical-helper-bootstrap-output=\(output.path)"],
            environment: [
                "PHYSICAL_AUDIT_AUTHORIZATION": runID.uuidString.lowercased(),
                "PHYSICAL_AUDIT_ROOT": root.path
            ],
            registrar: FixturePhysicalHelperRegistrar(result: .requiresApproval, shouldFail: true)
        ))

        try await command.execute()
        #expect(try JSONDecoder().decode(
            PhysicalHelperBootstrapResult.self,
            from: Data(contentsOf: output)
        ).status == "requires-approval")
    }

    @Test func `helper cleanup unregisters the exact embedded service`() async throws {
        let runID = UUID()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mc-helper-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("helper-cleanup-\(runID.uuidString.lowercased()).json")
        let registrar = FixturePhysicalHelperRegistrar(result: .enabled)
        let command = try #require(PhysicalHelperBootstrapCommand(
            arguments: ["--physical-helper-cleanup-output=\(output.path)"],
            environment: [
                "PHYSICAL_AUDIT_AUTHORIZATION": runID.uuidString.lowercased(),
                "PHYSICAL_AUDIT_ROOT": root.path
            ],
            registrar: registrar
        ))

        try await command.execute()
        #expect(try JSONDecoder().decode(
            PhysicalHelperBootstrapResult.self,
            from: Data(contentsOf: output)
        ).status == "unregistered")
        #expect(await registrar.unregisterCalls == 1)
        #expect(await registrar.ensureCalls == 0)
    }
}

private struct FixturePacketFilterAuditor: PacketFilterAuditing {
    let residuePresent: Bool

    func hasRules(anchor _: String) async throws -> Bool {
        residuePresent
    }
}

private struct FailingPacketFilterAuditor: PacketFilterAuditing {
    func hasRules(anchor _: String) async throws -> Bool {
        throw PacketFilterAuditFailure.connection
    }
}

private enum PacketFilterAuditFailure: Int, CustomNSError {
    case connection = 19

    static let errorDomain = "MCAppCoreTests.PacketFilterAuditFailure"
    var errorCode: Int {
        rawValue
    }
}

private actor FixturePhysicalHelperRegistrar: PrivilegedHelperRegistering {
    let result: PrivilegedHelperRegistrationStatus
    let shouldFail: Bool
    private(set) var ensureCalls = 0
    private(set) var unregisterCalls = 0

    init(result: PrivilegedHelperRegistrationStatus, shouldFail: Bool = false) {
        self.result = result
        self.shouldFail = shouldFail
    }

    func status() -> PrivilegedHelperRegistrationStatus {
        result
    }

    func ensureAvailable() throws -> PrivilegedHelperRegistrationStatus {
        ensureCalls += 1
        if shouldFail {
            throw PhysicalHelperBootstrapFailure.registration
        }
        return result
    }

    func unregister() {
        unregisterCalls += 1
    }

    nonisolated func openApprovalSettings() {}
}

private enum PhysicalHelperBootstrapFailure: Int, CustomNSError {
    case registration = 1

    static let errorDomain = "MCAppCoreTests.PhysicalHelperBootstrapFailure"
    var errorCode: Int {
        rawValue
    }
}
