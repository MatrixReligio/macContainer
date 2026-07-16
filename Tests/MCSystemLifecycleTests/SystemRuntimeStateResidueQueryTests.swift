import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("Live runtime state residue query")
struct SystemRuntimeStateResidueQueryTests {
    @Test func `queries exact launch process credential and packet filter evidence`() async throws {
        let launchServices = RecordingLaunchResidueInspector(hasServices: true)
        let processes = RecordingProcessResidueInspector(hasProcess: true)
        let credentials = FixedCredentialResidueInspector(hasCredential: true)
        let packetFilter = RecordingPacketFilterResidueInspector(hasRules: true)
        let query = SystemRuntimeStateResidueQuery(
            manifest: ReviewedRuntime110Manifest.package,
            launchServices: launchServices,
            processes: processes,
            credentials: credentials,
            packetFilter: packetFilter
        )

        for kind in [ResidueKind.launchService, .process, .registryCredential, .packetFilter] {
            #expect(try await query.status(for: kind) == .present)
        }
        #expect(launchServices.prefix == "com.apple.container.")
        #expect(processes.paths.contains("/usr/local/bin/container"))
        #expect(processes.paths.contains("/usr/local/bin/container-apiserver"))
        #expect(processes.teamID == "UPBK2H6LZM")
        #expect(packetFilter.anchor == "com.apple.container")
    }

    @Test func `rejects non-runtime residue kinds instead of guessing absent`() async {
        let query = SystemRuntimeStateResidueQuery(
            manifest: ReviewedRuntime110Manifest.package,
            launchServices: RecordingLaunchResidueInspector(hasServices: false),
            processes: RecordingProcessResidueInspector(hasProcess: false),
            credentials: FixedCredentialResidueInspector(hasCredential: false),
            packetFilter: RecordingPacketFilterResidueInspector(hasRules: false)
        )

        await #expect(throws: SystemRuntimeStateResidueError.unsupportedKind(.receipt)) {
            _ = try await query.status(for: .receipt)
        }
    }
}

private final class RecordingLaunchResidueInspector: LaunchServiceResidueInspecting, @unchecked Sendable {
    private let hasServices: Bool
    private(set) var prefix: String?

    init(hasServices: Bool) {
        self.hasServices = hasServices
    }

    func hasServices(prefix: String) async throws -> Bool {
        self.prefix = prefix
        return hasServices
    }
}

private final class RecordingProcessResidueInspector: OwnedProcessResidueInspecting, @unchecked Sendable {
    private let hasProcess: Bool
    private(set) var paths: Set<String> = []
    private(set) var teamID: String?

    init(hasProcess: Bool) {
        self.hasProcess = hasProcess
    }

    func hasOwnedProcess(executablePaths: Set<String>, expectedTeamID: String) throws -> Bool {
        paths = executablePaths
        teamID = expectedTeamID
        return hasProcess
    }
}

private struct FixedCredentialResidueInspector: RegistryCredentialResidueInspecting {
    let hasCredential: Bool

    func hasCredentials() async throws -> Bool {
        hasCredential
    }
}

private final class RecordingPacketFilterResidueInspector: PacketFilterResidueInspecting, @unchecked Sendable {
    private let hasRules: Bool
    private(set) var anchor: String?

    init(hasRules: Bool) {
        self.hasRules = hasRules
    }

    func hasRules(anchor: String) async throws -> Bool {
        self.anchor = anchor
        return hasRules
    }
}
