import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("Evidence-driven lifecycle recovery")
struct LifecycleRecoveryTests {
    @Test(arguments: LifecycleKind.allCases)
    func `transaction before target side effect only cleans staging`(_ kind: LifecycleKind) {
        let transactionID = UUID()
        let events = [event(1, transactionID, kind, .began)]

        #expect(
            LifecycleRecoveryPlanner().decide(events: events, evidence: .clean) ==
                .cleanStaging(transactionID: transactionID)
        )
    }

    @Test(arguments: [LifecycleKind.upgrade, .downgrade])
    func `installed upgrade target rolls back only to verified recorded point`(_ kind: LifecycleKind) {
        let transactionID = UUID()
        let pointID = UUID()
        let pointAction = LifecycleAction.retainRollbackPoint(identifier: pointID)
        let installAction = LifecycleAction.installPackage(digest: "reviewed-digest")
        let events = [
            event(1, transactionID, kind, .began),
            event(2, transactionID, kind, .intent, action: pointAction),
            event(3, transactionID, kind, .applied, action: pointAction),
            event(4, transactionID, kind, .intent, action: installAction),
            event(5, transactionID, kind, .applied, action: installAction)
        ]
        let evidence = RecoveryFreshEvidence(
            targetInstallation: .present,
            verifiedRollbackPoints: [pointID],
            residueReport: .empty
        )

        #expect(
            LifecycleRecoveryPlanner().decide(events: events, evidence: evidence) ==
                .rollBack(transactionID: transactionID, rollbackPoint: pointID)
        )
    }

    @Test func `unverified point and ambiguous target require recovery UI without mutation`() {
        let transactionID = UUID()
        let pointID = UUID()
        let action = LifecycleAction.installPackage(digest: "reviewed-digest")
        let events = [
            event(1, transactionID, .upgrade, .began),
            event(2, transactionID, .upgrade, .intent, action: action),
            event(3, transactionID, .upgrade, .applied, action: action)
        ]
        let evidence = RecoveryFreshEvidence(
            targetInstallation: .unverifiable,
            verifiedRollbackPoints: [pointID],
            residueReport: .empty
        )

        #expect(requiresRecoveryUI(LifecycleRecoveryPlanner().decide(events: events, evidence: evidence)))
    }

    @Test func `uninstall resumes only recorded allowlisted residue kinds`() {
        let transactionID = UUID()
        let action = LifecycleAction.removeUserArtifact(kind: .configuration)
        let events = [
            event(1, transactionID, .uninstall, .began),
            event(2, transactionID, .uninstall, .intent, action: action)
        ]
        let evidence = RecoveryFreshEvidence(
            targetInstallation: .absent,
            verifiedRollbackPoints: [],
            residueReport: report(present: [.configuration])
        )

        #expect(
            LifecycleRecoveryPlanner().decide(events: events, evidence: evidence) ==
                .resumeUninstall(transactionID: transactionID, remaining: [.configuration])
        )
    }

    @Test func `unrecorded or unverifiable uninstall residue never triggers guessed deletion`() {
        let transactionID = UUID()
        let action = LifecycleAction.removeUserArtifact(kind: .configuration)
        let events = [
            event(1, transactionID, .uninstall, .began),
            event(2, transactionID, .uninstall, .intent, action: action)
        ]
        let unrecorded = RecoveryFreshEvidence(
            targetInstallation: .absent,
            verifiedRollbackPoints: [],
            residueReport: report(present: [.receiptPayload])
        )
        let unverifiable = RecoveryFreshEvidence(
            targetInstallation: .absent,
            verifiedRollbackPoints: [],
            residueReport: report(unverifiable: [.resolver])
        )

        #expect(requiresRecoveryUI(LifecycleRecoveryPlanner().decide(events: events, evidence: unrecorded)))
        #expect(requiresRecoveryUI(LifecycleRecoveryPlanner().decide(events: events, evidence: unverifiable)))
    }

    @Test func `corrupt transition never causes a mutation decision`() {
        let transactionID = UUID()
        let action = LifecycleAction.removeReceipt(identifier: "com.apple.container-installer")
        let events = [
            event(1, transactionID, .uninstall, .began),
            event(2, transactionID, .uninstall, .applied, action: action)
        ]

        #expect(requiresRecoveryUI(LifecycleRecoveryPlanner().decide(events: events, evidence: .clean)))
    }

    @Test(arguments: LifecycleKind.allCases)
    func `interrupted staging cleanup remains safely resumable`(_ kind: LifecycleKind) {
        let transactionID = UUID()
        let events = [
            event(1, transactionID, kind, .began),
            event(2, transactionID, kind, .rollingBack, action: .cleanStaging)
        ]

        #expect(
            LifecycleRecoveryPlanner().decide(events: events, evidence: .clean) ==
                .cleanStaging(transactionID: transactionID)
        )
    }

    @Test func `recovery records rollback intent before cleanup side effect`() async throws {
        let storage = RecoveryMemoryJournalStorage()
        let journal = LifecycleJournal(storage: storage)
        let transactionID = try await journal.begin(kind: .upgrade, targetVersion: "1.2.0")
        let evidence = FixedRecoveryEvidenceReader(evidence: .clean)
        let mutations = RecordingRecoveryMutations()
        let recovery = LifecycleRecovery(
            journal: journal,
            evidenceReader: evidence,
            mutations: mutations
        )

        #expect(try await recovery.recover() == .cleanStaging(transactionID: transactionID))
        #expect(await mutations.actions == ["clean:\(transactionID.uuidString)"])
        let events = try await journal.events(for: transactionID)
        #expect(events.map(\.phase) == [.began, .rollingBack, .rolledBack])
        #expect(events[1].action == .cleanStaging)
    }

    @Test func `recovery resumes existing uninstall intent then independently audits and commits`() async throws {
        let storage = RecoveryMemoryJournalStorage()
        let journal = LifecycleJournal(storage: storage)
        let transactionID = try await journal.begin(kind: .uninstall, targetVersion: nil)
        let action = LifecycleAction.removeUserArtifact(kind: .configuration)
        try await journal.recordIntent(action, transactionID: transactionID)
        let evidence = FixedRecoveryEvidenceReader(evidence: .init(
            targetInstallation: .absent,
            verifiedRollbackPoints: [],
            residueReport: report(present: [.configuration])
        ))
        let mutations = RecordingRecoveryMutations()
        let recovery = LifecycleRecovery(
            journal: journal,
            evidenceReader: evidence,
            mutations: mutations
        )

        #expect(
            try await recovery.recover() ==
                .resumeUninstall(transactionID: transactionID, remaining: [.configuration])
        )
        #expect(await mutations.actions == ["remove:configuration", "audit"])
        let events = try await journal.events(for: transactionID)
        #expect(events.map(\.phase) == [.began, .intent, .applied, .verified, .committed])
    }

    @Test func `recovery revalidates exact recorded point before rollback`() async throws {
        let storage = RecoveryMemoryJournalStorage()
        let journal = LifecycleJournal(storage: storage)
        let transactionID = try await journal.begin(kind: .upgrade, targetVersion: "1.2.0")
        let pointID = UUID()
        let checkpoint = LifecycleAction.retainRollbackPoint(identifier: pointID)
        try await journal.recordIntent(checkpoint, transactionID: transactionID)
        try await journal.recordApplied(checkpoint, transactionID: transactionID)
        let install = LifecycleAction.installPackage(digest: "reviewed-digest")
        try await journal.recordIntent(install, transactionID: transactionID)
        try await journal.recordApplied(install, transactionID: transactionID)
        let evidence = FixedRecoveryEvidenceReader(evidence: .init(
            targetInstallation: .present,
            verifiedRollbackPoints: [pointID],
            residueReport: .empty
        ))
        let mutations = RecordingRecoveryMutations()
        let recovery = LifecycleRecovery(
            journal: journal,
            evidenceReader: evidence,
            mutations: mutations
        )

        #expect(
            try await recovery.recover() ==
                .rollBack(transactionID: transactionID, rollbackPoint: pointID)
        )
        #expect(await evidence.requestedPointIDs == [[pointID]])
        #expect(await mutations.actions == ["rollback:\(pointID.uuidString)"])
        #expect(try await journal.events(for: transactionID).last?.phase == .rolledBack)
    }

    @Test func `unreadable journal still runs read only evidence and performs no mutation`() async {
        let journal = FailingRecoveryJournal()
        let evidence = FixedRecoveryEvidenceReader(evidence: .clean)
        let mutations = RecordingRecoveryMutations()
        let recovery = LifecycleRecovery(
            journal: journal,
            evidenceReader: evidence,
            mutations: mutations
        )

        let decision = try? await recovery.recover()
        #expect(decision.map(requiresRecoveryUI) == true)
        #expect(await evidence.readCount == 1)
        #expect(await evidence.requestedPointIDs == [[]])
        #expect(await mutations.actions.isEmpty)
    }

    @Test func `local staging recovery removes only exact transaction directory`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainerRecoveryStaging-\(UUID().uuidString)", isDirectory: true)
        let staging = root.appendingPathComponent("Staging", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let transactionID = UUID()
        let temporary = try LocalInstallTemporaryDirectoryProvider(baseDirectory: staging)
            .create(transactionID: transactionID)
        try Data("package".utf8).write(to: temporary.url.appendingPathComponent("runtime.pkg"))
        let unrelated = staging.appendingPathComponent("unrelated", isDirectory: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: false)
        let cleaner = LocalRecoveryStagingCleaner(baseDirectory: staging)

        try await cleaner.clean(transactionID: transactionID)

        #expect(!FileManager.default.fileExists(atPath: temporary.url.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }

    @Test func `fresh target inspection distinguishes absent partial present and unverifiable`() async {
        #expect(await ResidueRecoveryTargetInspector(checker: RecoveryStatusChecker(statuses: [:]))
            .installationState() == .absent)
        #expect(await ResidueRecoveryTargetInspector(checker: RecoveryStatusChecker(statuses: [
            .receipt: .present
        ])).installationState() == .partial)
        #expect(await ResidueRecoveryTargetInspector(checker: RecoveryStatusChecker(statuses: [
            .receipt: .present, .receiptPayload: .present
        ])).installationState() == .present)
        #expect(await ResidueRecoveryTargetInspector(checker: RecoveryStatusChecker(statuses: [
            .receiptPayload: .unverifiable
        ])).installationState() == .unverifiable)
    }
}

private func event(
    _ sequence: UInt64,
    _ transactionID: UUID,
    _ kind: LifecycleKind,
    _ phase: LifecyclePhase,
    action: LifecycleAction? = nil
) -> LifecycleEvent {
    LifecycleEvent(
        sequence: sequence,
        transactionID: transactionID,
        kind: kind,
        phase: phase,
        targetVersion: kind == .install ? "1.1.0" : "1.2.0",
        action: action,
        failure: nil,
        timestamp: Date(timeIntervalSince1970: TimeInterval(sequence))
    )
}

private func report(
    present: Set<ResidueKind> = [],
    unverifiable: Set<ResidueKind> = []
) -> ResidueReport {
    ResidueReport(items: ResidueInventory.expectations.map { expectation in
        let status: ResidueStatus = if present.contains(expectation.kind) {
            .present
        } else if unverifiable.contains(expectation.kind) {
            .unverifiable
        } else {
            .absent
        }
        return ResidueItem(
            kind: expectation.kind,
            redactedLocation: expectation.redactedLocation,
            status: status,
            recoveryKey: expectation.recoveryKey
        )
    })
}

private func requiresRecoveryUI(_ decision: RecoveryDecision) -> Bool {
    if case .requiresUserRecovery = decision {
        return true
    }
    return false
}

private actor RecoveryMemoryJournalStorage: LifecycleJournalStorage {
    private var events: [LifecycleEvent] = []

    func load() -> [LifecycleEvent] {
        events
    }

    func append(_ event: LifecycleEvent) {
        events.append(event)
    }
}

private actor FixedRecoveryEvidenceReader: RecoveryEvidenceReading {
    let evidence: RecoveryFreshEvidence
    private(set) var readCount = 0
    private(set) var requestedPointIDs: [Set<UUID>] = []

    init(evidence: RecoveryFreshEvidence) {
        self.evidence = evidence
    }

    func read(recordedRollbackPoints: Set<UUID>) async -> RecoveryFreshEvidence {
        readCount += 1
        requestedPointIDs.append(recordedRollbackPoints)
        return evidence
    }
}

private actor RecordingRecoveryMutations: RecoveryMutationExecuting {
    private(set) var actions: [String] = []

    func cleanStaging(transactionID: UUID) async throws {
        actions.append("clean:\(transactionID.uuidString)")
    }

    func rollBack(pointID: UUID) async throws {
        actions.append("rollback:\(pointID.uuidString)")
    }

    func removeUninstallResidue(_ kind: ResidueKind) async throws {
        actions.append("remove:\(kind.rawValue)")
    }

    func auditResidue() async -> ResidueReport {
        actions.append("audit")
        return .empty
    }
}

private struct FailingRecoveryJournal: LifecycleRecoveryJournaling {
    func allEvents() async throws -> [LifecycleEvent] {
        throw RecoveryFixtureError.unreadable
    }

    func recordRollingBack(_: LifecycleAction?, transactionID _: UUID) async throws {}
    func recordRolledBack(transactionID _: UUID) async throws {}
    func recordIntent(_: LifecycleAction, transactionID _: UUID) async throws {}
    func recordApplied(_: LifecycleAction, transactionID _: UUID) async throws {}
    func recordVerified(transactionID _: UUID) async throws {}
    func commit(transactionID _: UUID) async throws {}
    func recordFailure(_: RedactedLifecycleFailure, transactionID _: UUID) async throws {}
}

private enum RecoveryFixtureError: Error {
    case unreadable
}

private struct RecoveryStatusChecker: ResidueAuditChecking {
    let statuses: [ResidueKind: ResidueStatus]

    func status(for kind: ResidueKind) async throws -> ResidueStatus {
        statuses[kind, default: .absent]
    }
}

private extension ResidueReport {
    static var empty: Self {
        report()
    }
}
