import Darwin
import Foundation

public enum RecoveryInstallationState: String, Codable, Equatable, Sendable {
    case absent
    case partial
    case present
    case unverifiable
}

public struct RecoveryFreshEvidence: Equatable, Sendable {
    public let targetInstallation: RecoveryInstallationState
    public let verifiedRollbackPoints: Set<UUID>
    public let residueReport: ResidueReport

    public init(
        targetInstallation: RecoveryInstallationState,
        verifiedRollbackPoints: Set<UUID>,
        residueReport: ResidueReport
    ) {
        self.targetInstallation = targetInstallation
        self.verifiedRollbackPoints = verifiedRollbackPoints
        self.residueReport = residueReport
    }

    public static var clean: Self {
        .init(
            targetInstallation: .absent,
            verifiedRollbackPoints: [],
            residueReport: ResidueReport(items: ResidueInventory.expectations.map { expectation in
                ResidueItem(
                    kind: expectation.kind,
                    redactedLocation: expectation.redactedLocation,
                    status: .absent,
                    recoveryKey: expectation.recoveryKey
                )
            })
        )
    }
}

public enum RecoveryDecision: Equatable, Sendable {
    case noAction
    case cleanStaging(transactionID: UUID)
    case rollBack(transactionID: UUID, rollbackPoint: UUID)
    case resumeUninstall(transactionID: UUID, remaining: [ResidueKind])
    case requiresUserRecovery(RedactedLifecycleFailure)
}

public struct LifecycleRecoveryPlanner: Sendable {
    public init() {}

    public func decide(
        events: [LifecycleEvent],
        evidence: RecoveryFreshEvidence
    ) -> RecoveryDecision {
        guard validateJournal(events) else { return recoveryRequired("recovery.journal.ambiguous") }
        let active = activeTransactions(in: events)
        guard active.count <= 1 else { return recoveryRequired("recovery.journal.multiple-active") }
        guard let transactionEvents = active.first, let first = transactionEvents.first,
              let last = transactionEvents.last
        else {
            return .noAction
        }
        if first.kind == .uninstall {
            return uninstallDecision(events: transactionEvents, evidence: evidence)
        }
        return installDecision(events: transactionEvents, evidence: evidence, last: last)
    }

    private func installDecision(
        events: [LifecycleEvent],
        evidence: RecoveryFreshEvidence,
        last: LifecycleEvent
    ) -> RecoveryDecision {
        let transactionID = last.transactionID
        if last.phase == .rollingBack, last.action == .cleanStaging {
            return .cleanStaging(transactionID: transactionID)
        }
        let pointID = events.compactMap { event -> UUID? in
            switch event.action {
            case let .retainRollbackPoint(identifier), let .restoreRollbackPoint(identifier):
                identifier
            default:
                nil
            }
        }.last
        if last.phase == .rollingBack {
            guard let pointID, evidence.verifiedRollbackPoints.contains(pointID) else {
                return recoveryRequired("recovery.rollback.unverifiable")
            }
            return .rollBack(transactionID: transactionID, rollbackPoint: pointID)
        }
        let installWasAttempted = events.contains { event in
            guard case .installPackage = event.action else { return false }
            return event.phase == .intent || event.phase == .applied
        }
        guard installWasAttempted else {
            return .cleanStaging(transactionID: transactionID)
        }
        guard evidence.targetInstallation != .unverifiable else {
            return recoveryRequired("recovery.target.unverifiable")
        }
        if last.kind == .install, evidence.targetInstallation == .absent {
            return .cleanStaging(transactionID: transactionID)
        }
        guard let pointID, evidence.verifiedRollbackPoints.contains(pointID) else {
            return recoveryRequired("recovery.rollback.missing")
        }
        return .rollBack(transactionID: transactionID, rollbackPoint: pointID)
    }

    private func uninstallDecision(
        events: [LifecycleEvent],
        evidence: RecoveryFreshEvidence
    ) -> RecoveryDecision {
        guard let last = events.last else { return recoveryRequired("recovery.uninstall.missing") }
        if last.phase == .rollingBack, last.action == .cleanStaging {
            return .cleanStaging(transactionID: last.transactionID)
        }
        if last.phase == .began {
            return .cleanStaging(transactionID: last.transactionID)
        }
        guard !evidence.residueReport.items.contains(where: { $0.status == .unverifiable }) else {
            return recoveryRequired("recovery.uninstall.unverifiable")
        }
        let recordedKinds = Set(events.flatMap { Self.residueKinds(for: $0.action) })
        let presentKinds = Set(evidence.residueReport.items.compactMap { item in
            item.status == .present ? item.kind : nil
        })
        guard presentKinds.isSubset(of: recordedKinds) else {
            return recoveryRequired("recovery.uninstall.unrecorded-residue")
        }
        var remaining = presentKinds
        if last.phase == .intent {
            remaining.formUnion(Self.residueKinds(for: last.action))
        }
        return .resumeUninstall(
            transactionID: last.transactionID,
            remaining: ResidueKind.allCases.filter(remaining.contains)
        )
    }

    private func validateJournal(_ events: [LifecycleEvent]) -> Bool {
        guard events.isEmpty || events.first?.sequence == 1 else { return false }
        guard zip(events, events.dropFirst()).allSatisfy({ $1.sequence == $0.sequence + 1 }) else {
            return false
        }
        return Dictionary(grouping: events, by: \.transactionID).values.allSatisfy(validateTransaction)
    }

    private func validateTransaction(_ events: [LifecycleEvent]) -> Bool {
        guard let first = events.first, first.phase == .began, first.action == nil,
              events.allSatisfy({
                  $0.kind == first.kind &&
                      $0.targetVersion == first.targetVersion &&
                      Self.actionIsAllowed($0.action, for: first.kind)
              })
        else {
            return false
        }
        for (previous, current) in zip(events, events.dropFirst()) {
            guard Self.transitionIsAllowed(from: previous.phase, to: current.phase) else { return false }
            let appliedMatchesIntent = previous.phase == .intent && previous.action == current.action
            if current.phase == .applied, !appliedMatchesIntent {
                return false
            }
            if current.phase == .intent || current.phase == .applied, current.action == nil {
                return false
            }
        }
        return true
    }

    private func activeTransactions(in events: [LifecycleEvent]) -> [[LifecycleEvent]] {
        Dictionary(grouping: events, by: \.transactionID).values
            .filter { $0.last?.phase.isTerminal == false }
            .sorted { ($0.last?.sequence ?? 0) < ($1.last?.sequence ?? 0) }
    }

    private static func actionIsAllowed(_ action: LifecycleAction?, for kind: LifecycleKind) -> Bool {
        guard let action else { return true }
        return switch kind {
        case .install:
            action.isInstallRecoveryAction
        case .upgrade, .downgrade:
            action.isUpgradeRecoveryAction
        case .rollback:
            action.isRollbackRecoveryAction
        case .uninstall:
            action.isUninstallRecoveryAction
        }
    }

    private static func transitionIsAllowed(from: LifecyclePhase, to: LifecyclePhase) -> Bool {
        if to == .failed {
            return true
        }
        return switch (from, to) {
        case (.began, .intent), (.applied, .intent), (.verified, .intent),
             (.intent, .applied), (.applied, .verified), (.verified, .committed),
             (.applied, .committed), (.began, .committed),
             (.began, .rollingBack), (.intent, .rollingBack),
             (.applied, .rollingBack), (.verified, .rollingBack),
             (.rollingBack, .intent), (.rollingBack, .rolledBack), (.applied, .rolledBack):
            true
        default:
            false
        }
    }

    fileprivate static func residueKinds(for action: LifecycleAction?) -> [ResidueKind] {
        switch action {
        case .stopServices:
            [.launchService, .process]
        case .removePayload:
            [.receiptPayload]
        case .removeReceipt:
            [.receipt]
        case let .removeUserArtifact(kind):
            [kind]
        default:
            []
        }
    }

    private func recoveryRequired(_ code: String) -> RecoveryDecision {
        .requiresUserRecovery(.init(code: code, redactedDetail: "manual-recovery-required"))
    }
}

public protocol RecoveryEvidenceReading: Sendable {
    func read(recordedRollbackPoints: Set<UUID>) async -> RecoveryFreshEvidence
}

public protocol RecoveryTargetInstallationInspecting: Sendable {
    func installationState() async -> RecoveryInstallationState
}

public struct ResidueRecoveryTargetInspector: RecoveryTargetInstallationInspecting {
    private let checker: any ResidueAuditChecking

    public init(checker: any ResidueAuditChecking) {
        self.checker = checker
    }

    public func installationState() async -> RecoveryInstallationState {
        do {
            let receipt = try await checker.status(for: .receipt)
            let payload = try await checker.status(for: .receiptPayload)
            guard receipt != .unverifiable, payload != .unverifiable else {
                return .unverifiable
            }
            return switch (receipt, payload) {
            case (.absent, .absent): .absent
            case (.present, .present): .present
            default: .partial
            }
        } catch {
            return .unverifiable
        }
    }
}

public protocol RecoveryRollbackPointVerifying: Sendable {
    func verifiedPointIDs(_ recordedPointIDs: Set<UUID>) async -> Set<UUID>
}

public struct SystemRecoveryEvidenceReader: RecoveryEvidenceReading {
    private let target: any RecoveryTargetInstallationInspecting
    private let rollbackPoints: any RecoveryRollbackPointVerifying
    private let residueAuditor: any ResidueAuditing

    public init(
        target: any RecoveryTargetInstallationInspecting,
        rollbackPoints: any RecoveryRollbackPointVerifying,
        residueAuditor: any ResidueAuditing
    ) {
        self.target = target
        self.rollbackPoints = rollbackPoints
        self.residueAuditor = residueAuditor
    }

    public func read(recordedRollbackPoints: Set<UUID>) async -> RecoveryFreshEvidence {
        let installationState = await target.installationState()
        let verifiedPoints = await rollbackPoints.verifiedPointIDs(recordedRollbackPoints)
        let residueReport = await residueAuditor.audit()
        return .init(
            targetInstallation: installationState,
            verifiedRollbackPoints: verifiedPoints,
            residueReport: residueReport
        )
    }
}

public protocol RecoveryMutationExecuting: Sendable {
    func cleanStaging(transactionID: UUID) async throws
    func rollBack(pointID: UUID) async throws
    func removeUninstallResidue(_ kind: ResidueKind) async throws
    func auditResidue() async -> ResidueReport
}

public protocol RecoveryStagingCleaning: Sendable {
    func clean(transactionID: UUID) async throws
}

public protocol RecoveryRollbackExecuting: Sendable {
    func rollBack(pointID: UUID) async throws
}

public protocol RecoveryUninstallResidueRemoving: Sendable {
    func remove(_ kind: ResidueKind) async throws
}

public struct SystemRecoveryMutationExecutor: RecoveryMutationExecuting {
    private let staging: any RecoveryStagingCleaning
    private let rollback: any RecoveryRollbackExecuting
    private let uninstall: any RecoveryUninstallResidueRemoving
    private let residueAuditor: any ResidueAuditing

    public init(
        staging: any RecoveryStagingCleaning,
        rollback: any RecoveryRollbackExecuting,
        uninstall: any RecoveryUninstallResidueRemoving,
        residueAuditor: any ResidueAuditing
    ) {
        self.staging = staging
        self.rollback = rollback
        self.uninstall = uninstall
        self.residueAuditor = residueAuditor
    }

    public func cleanStaging(transactionID: UUID) async throws {
        try await staging.clean(transactionID: transactionID)
    }

    public func rollBack(pointID: UUID) async throws {
        try await rollback.rollBack(pointID: pointID)
    }

    public func removeUninstallResidue(_ kind: ResidueKind) async throws {
        try await uninstall.remove(kind)
    }

    public func auditResidue() async -> ResidueReport {
        await residueAuditor.audit()
    }
}

public struct LocalRecoveryStagingCleaner: RecoveryStagingCleaning {
    private let baseDirectory: URL
    private let requiredOwner: uid_t
    private let remover: LocalOwnedArtifactRemover

    public init(
        baseDirectory: URL = LocalInstallTemporaryDirectoryProvider.defaultBaseDirectory,
        requiredOwner: uid_t = geteuid()
    ) {
        self.baseDirectory = baseDirectory.standardizedFileURL
        self.requiredOwner = requiredOwner
        remover = LocalOwnedArtifactRemover(requiredOwner: requiredOwner)
    }

    public func clean(transactionID: UUID) async throws {
        var status = stat()
        guard Darwin.lstat(baseDirectory.path, &status) == 0 else {
            if errno == ENOENT {
                return
            }
            throw posixError()
        }
        guard
            status.st_mode & S_IFMT == S_IFDIR,
            status.st_uid == requiredOwner,
            status.st_mode & 0o077 == 0
        else {
            throw RecoveryStagingError.unsafeBaseDirectory
        }
        let transactionDirectory = baseDirectory
            .appendingPathComponent(transactionID.uuidString, isDirectory: true)
            .standardizedFileURL
        guard transactionDirectory.deletingLastPathComponent() == baseDirectory else {
            throw RecoveryStagingError.unsafeTransactionDirectory
        }
        try remover.remove(at: transactionDirectory)
        let children = try FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil
        )
        if children.isEmpty {
            try remover.remove(at: baseDirectory)
        }
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}

public enum RecoveryStagingError: Error, Equatable, Sendable {
    case unsafeBaseDirectory
    case unsafeTransactionDirectory
}

public protocol LifecycleRecoveryJournaling: Sendable {
    func allEvents() async throws -> [LifecycleEvent]
    func recordRollingBack(_ action: LifecycleAction?, transactionID: UUID) async throws
    func recordRolledBack(transactionID: UUID) async throws
    func recordIntent(_ action: LifecycleAction, transactionID: UUID) async throws
    func recordApplied(_ action: LifecycleAction, transactionID: UUID) async throws
    func recordVerified(transactionID: UUID) async throws
    func commit(transactionID: UUID) async throws
    func recordFailure(_ failure: RedactedLifecycleFailure, transactionID: UUID) async throws
}

extension LifecycleJournal: LifecycleRecoveryJournaling {}

public struct LifecycleRecovery: Sendable {
    private let journal: any LifecycleRecoveryJournaling
    private let evidenceReader: any RecoveryEvidenceReading
    private let mutations: any RecoveryMutationExecuting
    private let operationLock: LifecycleOperationLock
    private let planner: LifecycleRecoveryPlanner

    public init(
        journal: any LifecycleRecoveryJournaling,
        evidenceReader: any RecoveryEvidenceReading,
        mutations: any RecoveryMutationExecuting,
        operationLock: LifecycleOperationLock = LifecycleOperationLock(),
        planner: LifecycleRecoveryPlanner = LifecycleRecoveryPlanner()
    ) {
        self.journal = journal
        self.evidenceReader = evidenceReader
        self.mutations = mutations
        self.operationLock = operationLock
        self.planner = planner
    }

    public func recover() async throws -> RecoveryDecision {
        let lease = try operationLock.acquire()
        defer { lease.release() }
        let events: [LifecycleEvent]
        do {
            events = try await journal.allEvents()
        } catch {
            _ = await evidenceReader.read(recordedRollbackPoints: [])
            return recoveryRequired("recovery.journal.unreadable")
        }
        let recordedPointIDs = Set(events.compactMap { event -> UUID? in
            if case let .retainRollbackPoint(identifier) = event.action {
                return identifier
            }
            return nil
        })
        let evidence = await evidenceReader.read(recordedRollbackPoints: recordedPointIDs)
        let decision = planner.decide(events: events, evidence: evidence)
        do {
            switch decision {
            case .noAction, .requiresUserRecovery:
                return decision
            case let .cleanStaging(transactionID):
                try await executeCleanup(transactionID: transactionID, events: events)
            case let .rollBack(transactionID, pointID):
                try await executeRollback(
                    transactionID: transactionID,
                    pointID: pointID,
                    events: events
                )
            case let .resumeUninstall(transactionID, remaining):
                return try await executeUninstall(
                    transactionID: transactionID,
                    remaining: remaining,
                    events: events,
                    originalDecision: decision
                )
            }
            return decision
        } catch {
            if let transactionID = Self.activeTransactionID(in: events) {
                try? await journal.recordFailure(
                    .init(code: "recovery.mutation.failed", redactedDetail: "manual-recovery-required"),
                    transactionID: transactionID
                )
            }
            return recoveryRequired("recovery.mutation.failed")
        }
    }

    private func executeCleanup(transactionID: UUID, events: [LifecycleEvent]) async throws {
        if events.last(where: { $0.transactionID == transactionID })?.phase != .rollingBack {
            try await journal.recordRollingBack(.cleanStaging, transactionID: transactionID)
        }
        try await mutations.cleanStaging(transactionID: transactionID)
        try await journal.recordRolledBack(transactionID: transactionID)
    }

    private func executeRollback(
        transactionID: UUID,
        pointID: UUID,
        events: [LifecycleEvent]
    ) async throws {
        if events.last(where: { $0.transactionID == transactionID })?.phase != .rollingBack {
            try await journal.recordRollingBack(
                .restoreRollbackPoint(identifier: pointID),
                transactionID: transactionID
            )
        }
        try await mutations.rollBack(pointID: pointID)
        try await journal.recordRolledBack(transactionID: transactionID)
    }

    private func executeUninstall(
        transactionID: UUID,
        remaining: [ResidueKind],
        events: [LifecycleEvent],
        originalDecision: RecoveryDecision
    ) async throws -> RecoveryDecision {
        var pending = remaining
        let last = events.last(where: { $0.transactionID == transactionID })
        if let last, last.phase == .intent, let action = last.action {
            let intentKinds = LifecycleRecoveryPlanner.residueKinds(for: action)
            for kind in intentKinds where pending.contains(kind) {
                try await mutations.removeUninstallResidue(kind)
                pending.removeAll { $0 == kind }
            }
            try await journal.recordApplied(action, transactionID: transactionID)
        }
        for kind in pending {
            let action = Self.action(for: kind)
            try await journal.recordIntent(action, transactionID: transactionID)
            try await mutations.removeUninstallResidue(kind)
            try await journal.recordApplied(action, transactionID: transactionID)
        }
        let report = await mutations.auditResidue()
        guard report.isEmpty else {
            try await journal.recordFailure(
                .init(code: "recovery.uninstall.incomplete", redactedDetail: "manual-recovery-required"),
                transactionID: transactionID
            )
            return recoveryRequired("recovery.uninstall.incomplete")
        }
        try await journal.recordVerified(transactionID: transactionID)
        try await journal.commit(transactionID: transactionID)
        return originalDecision
    }

    private static func action(for kind: ResidueKind) -> LifecycleAction {
        switch kind {
        case .receiptPayload:
            .removePayload(manifestID: ReviewedRuntime110Manifest.identifier)
        case .receipt:
            .removeReceipt(identifier: ReviewedRuntime110Manifest.package.receiptIdentifier)
        default:
            .removeUserArtifact(kind: kind)
        }
    }

    private static func activeTransactionID(in events: [LifecycleEvent]) -> UUID? {
        Dictionary(grouping: events, by: \.transactionID).values
            .first { $0.last?.phase.isTerminal == false }?
            .last?.transactionID
    }

    private func recoveryRequired(_ code: String) -> RecoveryDecision {
        .requiresUserRecovery(.init(code: code, redactedDetail: "manual-recovery-required"))
    }
}

private extension LifecycleAction {
    var isInstallRecoveryAction: Bool {
        switch self {
        case .cleanStaging, .installPackage:
            true
        default:
            false
        }
    }

    var isUpgradeRecoveryAction: Bool {
        switch self {
        case .cleanStaging, .installPackage, .retainRollbackPoint, .restoreRollbackPoint:
            true
        default:
            false
        }
    }

    var isRollbackRecoveryAction: Bool {
        switch self {
        case .cleanStaging, .restoreRollbackPoint, .retainRollbackPoint:
            true
        default:
            false
        }
    }

    var isUninstallRecoveryAction: Bool {
        switch self {
        case .cleanStaging, .stopServices, .removePayload, .removeReceipt, .removeUserArtifact:
            true
        default:
            false
        }
    }
}
