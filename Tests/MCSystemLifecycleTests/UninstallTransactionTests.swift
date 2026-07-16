import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("Complete runtime uninstallation")
struct UninstallTransactionTests {
    @Test func `complete uninstall ends with independent empty audit`() async throws {
        let fixture = UninstallFixture()

        let result = try await fixture.transaction.completelyUninstall(
            confirmation: fixture.validConfirmation(mode: .complete)
        )

        #expect(result.completion == .complete)
        #expect(result.audit.isEmpty)
        #expect(await fixture.state.artifacts.isEmpty)
        #expect(fixture.actions.values == UninstallStage.allCases.map(\.rawValue))
    }

    @Test(arguments: UninstallStage.allCases)
    func `failure at every stage never claims complete removal`(_ stage: UninstallStage) async throws {
        let fixture = UninstallFixture(failingAt: stage)
        let confirmation = await fixture.validConfirmation(mode: .complete)

        await #expect(throws: UninstallError.self) {
            _ = try await fixture.transaction.completelyUninstall(confirmation: confirmation)
        }

        #expect(!fixture.actions.values.contains("uninstall.success"))
    }

    @Test func `stale confirmation is rejected before mutation`() async throws {
        let fixture = UninstallFixture()
        let stale = CompleteUninstallConfirmation(
            mode: .complete,
            inventoryFingerprint: String(repeating: "0", count: 64),
            acknowledgesIrreversibleDeletion: true
        )

        await #expect(throws: UninstallError.staleConfirmation) {
            _ = try await fixture.transaction.completelyUninstall(confirmation: stale)
        }
        #expect(await fixture.state.artifacts == Set(ResidueKind.allCases))
        #expect(fixture.services.stopCount == 0)
    }

    @Test func `remaining or unverifiable artifact reports uninstall incomplete`() async throws {
        let fixture = UninstallFixture(undeletableKind: .downloadCache)

        do {
            _ = try await fixture.transaction.completelyUninstall(
                confirmation: fixture.validConfirmation(mode: .complete)
            )
            Issue.record("Expected incomplete uninstall")
        } catch let UninstallError.incomplete(report) {
            #expect(report.items.first { $0.kind == .downloadCache }?.status == .present)
        }
    }

    @Test func `preservation mode never uses complete success and reports preserved data`() async throws {
        let fixture = UninstallFixture()

        let result = try await fixture.transaction.removeRuntimePreservingData(
            confirmation: fixture.validConfirmation(mode: .preserveData)
        )

        #expect(result.completion == .dataPreserved)
        #expect(!result.audit.isEmpty)
        #expect(Set(result.preservedKinds) == Set([
            .applicationSupport, .configuration, .defaultsDomain, .registryCredential
        ]))
        #expect(await fixture.state.artifacts == Set(result.preservedKinds))
    }

    @Test func `global lifecycle lock rejects overlap and releases exactly once`() throws {
        let lock = LifecycleOperationLock()
        let first = try lock.acquire()

        #expect(throws: UninstallError.lifecycleBusy) {
            _ = try lock.acquire()
        }
        first.release()
        first.release()
        let second = try lock.acquire()
        second.release()
    }
}

private final class UninstallFixture {
    let state: UninstallArtifactState
    let actions: LockedUninstallActions
    let services: RecordingUninstallServices
    let transaction: UninstallTransaction

    init(
        failingAt: UninstallStage? = nil,
        undeletableKind: ResidueKind? = nil
    ) {
        state = UninstallArtifactState(
            artifacts: Set(ResidueKind.allCases),
            undeletableKind: undeletableKind
        )
        actions = LockedUninstallActions(failingAt: failingAt)
        services = RecordingUninstallServices(state: state, actions: actions)
        let auditor = ResidueAuditor(checker: StatefulResidueChecker(state: state))
        transaction = UninstallTransaction(
            target: .reviewedRuntime110,
            operationLock: LifecycleOperationLock(),
            inventory: RecordingUninstallInventory(state: state, actions: actions),
            confirmation: RecordingUninstallConfirmation(actions: actions),
            services: services,
            processes: RecordingUninstallProcesses(actions: actions),
            credentials: RecordingUninstallCredentials(state: state, actions: actions),
            helper: RecordingUninstallHelper(state: state, actions: actions),
            userArtifacts: RecordingUserArtifactRemover(state: state, actions: actions),
            auditor: RecordingUninstallAuditor(auditor: auditor, actions: actions),
            journal: RecordingUninstallJournal(actions: actions)
        )
    }

    func validConfirmation(mode: UninstallMode) async -> CompleteUninstallConfirmation {
        let inventory = await state.inventory(mode: mode)
        return .init(
            mode: mode,
            inventoryFingerprint: inventory.fingerprint,
            acknowledgesIrreversibleDeletion: mode == .complete
        )
    }
}

private actor UninstallArtifactState {
    private(set) var artifacts: Set<ResidueKind>
    let undeletableKind: ResidueKind?

    init(artifacts: Set<ResidueKind>, undeletableKind: ResidueKind?) {
        self.artifacts = artifacts
        self.undeletableKind = undeletableKind
    }

    func inventory(mode: UninstallMode) -> UninstallInventory {
        .init(
            runtimeVersion: "1.1.0",
            activeWork: ["container:web", "machine:builder"],
            serviceLabels: ["com.apple.container.apiserver"],
            resolverNames: ["web.test"],
            artifactKinds: artifacts,
            estimatedBytes: 4096,
            mode: mode
        )
    }

    func remove(_ kinds: Set<ResidueKind>) {
        artifacts.subtract(kinds.filter { $0 != undeletableKind })
    }
}

private final class LockedUninstallActions: @unchecked Sendable {
    private let lock = NSLock()
    private let failingAt: UninstallStage?
    private var storage: [String] = []

    init(failingAt: UninstallStage?) {
        self.failingAt = failingAt
    }

    var values: [String] {
        lock.withLock { storage }
    }

    func stage(_ stage: UninstallStage) throws {
        lock.withLock { storage.append(stage.rawValue) }
        if failingAt == stage {
            throw UninstallFixtureError.injected
        }
    }
}

private struct RecordingUninstallInventory: UninstallInventoryRefreshing {
    let state: UninstallArtifactState
    let actions: LockedUninstallActions

    func refresh(mode: UninstallMode) async throws -> UninstallInventory {
        try actions.stage(.inventoryRefresh)
        return await state.inventory(mode: mode)
    }
}

private struct RecordingUninstallConfirmation: UninstallConfirmationChecking {
    let actions: LockedUninstallActions

    func approve(
        inventory: UninstallInventory,
        confirmation: CompleteUninstallConfirmation
    ) async throws -> Bool {
        _ = inventory
        _ = confirmation
        try actions.stage(.confirmation)
        return true
    }
}

private final class RecordingUninstallServices: UninstallServiceStopping, @unchecked Sendable {
    let state: UninstallArtifactState
    let actions: LockedUninstallActions
    private(set) var stopCount = 0

    init(state: UninstallArtifactState, actions: LockedUninstallActions) {
        self.state = state
        self.actions = actions
    }

    func stopAll(activeWork: [String], serviceLabels: [String]) async throws {
        _ = activeWork
        _ = serviceLabels
        stopCount += 1
        try actions.stage(.serviceStop)
        await state.remove([.launchService, .process])
    }
}

private struct RecordingUninstallProcesses: UninstallProcessVerifying {
    let actions: LockedUninstallActions

    func verifyNoOwnedProcess() async throws {
        try actions.stage(.processVerification)
    }
}

private struct RecordingUninstallCredentials: UninstallCredentialRemoving {
    let state: UninstallArtifactState
    let actions: LockedUninstallActions

    func removeAll() async throws {
        try actions.stage(.credentialRemoval)
        await state.remove([.registryCredential])
    }
}

private final class RecordingUninstallHelper: UninstallPrivilegedHelping, @unchecked Sendable {
    let state: UninstallArtifactState
    let actions: LockedUninstallActions
    private var recordedNetworkStage = false

    init(state: UninstallArtifactState, actions: LockedUninstallActions) {
        self.state = state
        self.actions = actions
    }

    func removeResolver(name: String) async throws {
        _ = name
        try recordNetworkStageOnce()
        await state.remove([.resolver])
    }

    func removePacketFilter(anchor: String) async throws {
        _ = anchor
        try recordNetworkStageOnce()
        await state.remove([.packetFilter])
    }

    func removePayload(manifestID: String, manifestSHA256: String) async throws {
        _ = manifestID
        _ = manifestSHA256
        try actions.stage(.payloadRemoval)
        await state.remove([.receiptPayload])
    }

    func forgetReceipt(identifier: String) async throws {
        _ = identifier
        try actions.stage(.receiptRemoval)
        await state.remove([.receipt])
    }

    func removeKnownEmptyDirectories(manifestID: String) async throws {
        _ = manifestID
        try actions.stage(.emptyDirectoryRemoval)
        await state.remove([.runtimeOwnedDirectory])
    }

    private func recordNetworkStageOnce() throws {
        guard !recordedNetworkStage else { return }
        recordedNetworkStage = true
        try actions.stage(.networkRemoval)
    }
}

private final class RecordingUserArtifactRemover: UninstallUserArtifactRemoving, @unchecked Sendable {
    let state: UninstallArtifactState
    let actions: LockedUninstallActions
    private var recordedStage = false

    init(state: UninstallArtifactState, actions: LockedUninstallActions) {
        self.state = state
        self.actions = actions
    }

    func remove(_ kind: ResidueKind) async throws {
        if !recordedStage {
            recordedStage = true
            try actions.stage(.userArtifactRemoval)
        }
        await state.remove([kind])
    }
}

private actor StatefulResidueChecker: ResidueAuditChecking {
    let state: UninstallArtifactState

    init(state: UninstallArtifactState) {
        self.state = state
    }

    func status(for kind: ResidueKind) async throws -> ResidueStatus {
        await state.artifacts.contains(kind) ? .present : .absent
    }
}

private struct RecordingUninstallAuditor: ResidueAuditing {
    let auditor: ResidueAuditor
    let actions: LockedUninstallActions

    func audit() async -> ResidueReport {
        do {
            try actions.stage(.residueAudit)
        } catch {
            return .unverifiableForAll(recoveryKey: "uninstall.audit.failed")
        }
        return await auditor.audit()
    }
}

private struct RecordingUninstallJournal: UninstallJournalWriting {
    let actions: LockedUninstallActions

    func begin(mode: UninstallMode) async throws -> UUID {
        _ = mode
        return UUID()
    }

    func recordIntent(transactionID: UUID, action: LifecycleAction) async throws {
        _ = transactionID
        _ = action
    }

    func recordApplied(transactionID: UUID, action: LifecycleAction) async throws {
        _ = transactionID
        _ = action
    }

    func commit(transactionID: UUID) async throws {
        _ = transactionID
    }

    func fail(transactionID: UUID, failure: RedactedLifecycleFailure) async throws {
        _ = transactionID
        _ = failure
    }
}

private enum UninstallFixtureError: Error {
    case injected
}
