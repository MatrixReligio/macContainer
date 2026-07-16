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

    @Test func `process inventory retries a saturated kernel snapshot before declaring absence`() throws {
        let source = RecordingProcessIDList(
            estimatedCount: 1,
            batches: [
                .init(processIDs: [11], isSaturated: true),
                .init(processIDs: [11, 22], isSaturated: false)
            ]
        )
        let inspector = SystemOwnedProcessResidueInspector(processList: source)

        #expect(try inspector.processIDs() == [11, 22])
        #expect(source.capacities.count == 2)
        #expect(source.capacities[1] == source.capacities[0] * 2)
    }

    @Test func `process inventory fails closed when every kernel snapshot is saturated`() {
        let source = RecordingProcessIDList(
            estimatedCount: 1,
            batches: Array(
                repeating: .init(processIDs: [11], isSaturated: true),
                count: 5
            )
        )
        let inspector = SystemOwnedProcessResidueInspector(processList: source)

        #expect(throws: SystemRuntimeStateResidueError.unstableProcessList) {
            _ = try inspector.processIDs()
        }
    }
}

private final class RecordingProcessIDList: ProcessIDListing, @unchecked Sendable {
    let estimatedCount: Int
    private var batches: [ProcessIDBatch]
    private(set) var capacities: [Int] = []

    init(estimatedCount: Int, batches: [ProcessIDBatch]) {
        self.estimatedCount = estimatedCount
        self.batches = batches
    }

    func estimateCount() throws -> Int {
        estimatedCount
    }

    func list(capacity: Int) throws -> ProcessIDBatch {
        capacities.append(capacity)
        return batches.removeFirst()
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
