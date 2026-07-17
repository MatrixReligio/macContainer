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

    @Test func `signed app physical operations are fixed to the authorized run root`() async throws {
        let runID = UUID()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mc-physical-operation-\(UUID().uuidString)", isDirectory: true)
        let runRoot = root.appendingPathComponent(runID.uuidString.lowercased(), isDirectory: true)
        let downloads = runRoot.appendingPathComponent("downloads", isDirectory: true)
        try FileManager.default.createDirectory(
            at: downloads,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runRoot.path)
        defer { try? FileManager.default.removeItem(at: root) }
        let package = downloads.appendingPathComponent("container-1.1.0-installer-signed.pkg")
        try Data("reviewed-package".utf8).write(to: package)
        let executor = FixturePhysicalOperationExecutor()
        let invocationID = UUID()
        let output = root.appendingPathComponent(
            "helper-operation-\(invocationID.uuidString.lowercased()).json"
        )
        let environment = [
            "PHYSICAL_AUDIT_AUTHORIZATION": invocationID.uuidString.lowercased(),
            "PHYSICAL_AUDIT_ROOT": root.path,
            "PHYSICAL_RUN_ID": runID.uuidString.lowercased(),
            "PHYSICAL_RUN_ROOT": runRoot.path
        ]
        let command = try #require(PhysicalPrivilegedOperationCommand(
            arguments: [
                "--physical-helper-operation=install-1.1.0",
                "--physical-helper-operation-output=\(output.path)"
            ],
            environment: environment,
            executor: executor
        ))

        try await command.execute()

        #expect(await executor.installations == ["1.1.0|\(package.path)"])
        #expect(try JSONDecoder().decode(
            PhysicalPrivilegedOperationResult.self,
            from: Data(contentsOf: output)
        ) == .init(operation: "install-1.1.0", succeeded: true))
        #expect(PhysicalPrivilegedOperationCommand(
            arguments: [
                "--physical-helper-operation=install-9.9.9",
                "--physical-helper-operation-output=\(output.path)"
            ],
            environment: environment,
            executor: executor
        ) == nil)
    }

    @Test func `signed app DNS and uninstall operations return independently auditable results`() async throws {
        let fixture = try PhysicalOperationFixture()
        defer { fixture.cleanup() }
        let executor = FixturePhysicalOperationExecutor()

        let dns = try #require(fixture.command(operation: "dns-round-trip", executor: executor))
        try await dns.command.execute()
        #expect(await executor.domains == ["mct-e2e-\(fixture.runID.uuidString.lowercased()).test"])
        #expect(try fixture.result(at: dns.output) == .init(
            operation: "dns-round-trip",
            succeeded: true
        ))

        let uninstall = try #require(fixture.command(operation: "complete-uninstall", executor: executor))
        try await uninstall.command.execute()
        #expect(try fixture.result(at: uninstall.output) == .init(
            operation: "complete-uninstall",
            succeeded: true,
            completion: "complete",
            auditEmpty: true,
            auditComplete: true,
            preservedCount: 0
        ))
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

private actor FixturePhysicalOperationExecutor: PhysicalPrivilegedOperationExecuting {
    private(set) var installations: [String] = []
    private(set) var domains: [String] = []

    func install(version: String, packageURL: URL) {
        installations.append("\(version)|\(packageURL.path)")
    }

    func roundTripDNS(domain: String) {
        domains.append(domain)
    }

    func completeUninstall() -> PhysicalCompleteUninstallResult {
        .init(completion: "complete", auditEmpty: true, auditComplete: true, preservedCount: 0)
    }
}

private struct PhysicalOperationFixture {
    let root: URL
    let runRoot: URL
    let runID: UUID

    init() throws {
        runID = UUID()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mc-physical-operation-\(UUID().uuidString)", isDirectory: true)
        runRoot = root.appendingPathComponent(runID.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(
            at: runRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runRoot.path)
    }

    func command(
        operation: String,
        executor: any PhysicalPrivilegedOperationExecuting
    ) -> (command: PhysicalPrivilegedOperationCommand, output: URL)? {
        let invocationID = UUID()
        let output = root.appendingPathComponent(
            "helper-operation-\(invocationID.uuidString.lowercased()).json"
        )
        let command = PhysicalPrivilegedOperationCommand(
            arguments: [
                "--physical-helper-operation=\(operation)",
                "--physical-helper-operation-output=\(output.path)"
            ],
            environment: [
                "PHYSICAL_AUDIT_AUTHORIZATION": invocationID.uuidString.lowercased(),
                "PHYSICAL_AUDIT_ROOT": root.path,
                "PHYSICAL_RUN_ID": runID.uuidString.lowercased(),
                "PHYSICAL_RUN_ROOT": runRoot.path
            ],
            executor: executor
        )
        return command.map { ($0, output) }
    }

    func result(at output: URL) throws -> PhysicalPrivilegedOperationResult {
        try JSONDecoder().decode(
            PhysicalPrivilegedOperationResult.self,
            from: Data(contentsOf: output)
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
