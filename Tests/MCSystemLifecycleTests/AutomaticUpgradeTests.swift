import Foundation
import MCCompatibility
import MCModel
@testable import MCSystemLifecycle
import Testing
import TestSupport

@Suite("Guarded automatic runtime upgrade")
struct AutomaticUpgradeTests {
    @Test func `compatible idle update passes every gate and succeeds`() async throws {
        let fixture = try AutomaticFixture()

        #expect(try await fixture.coordinator.process(.fixture) == .upToDate)
        #expect(fixture.actions.values == ["context", "package", "rollback", "final-idle", "upgrade"])
        #expect(await fixture.blocker.records.isEmpty)
        #expect(await fixture.sink.states == [
            .checking, .available(version: "1.1.0"), .downloading(version: "1.1.0"),
            .installing(.packagePreparation), .upToDate
        ])
    }

    @Test func `unknown bad package and busy state never install`() async throws {
        let unknown = try AutomaticFixture(candidateVersion: "9.9.9")
        #expect(try await unknown.coordinator.process(unknown.candidate) == .held(.unknownRuntime))
        #expect(unknown.actions.values == ["context"])

        let badPackage = try AutomaticFixture(candidateDigest: String(repeating: "0", count: 64))
        #expect(try await badPackage.coordinator.process(badPackage.candidate) == .held(.packageIdentityMismatch))
        #expect(badPackage.actions.values == ["context"])

        let busy = try AutomaticFixture(activity: [.init(activeContainers: 1)])
        #expect(try await busy.coordinator.process(.fixture) == .pending(.workActive))
        #expect(busy.actions.values == ["context", "package"])
    }

    @Test func `package rollback and preflight failures hold before mutation`() async throws {
        let badPackage = try AutomaticFixture(packageFails: true)
        #expect(try await badPackage.coordinator.process(.fixture) == .held(.packageIdentityMismatch))

        let noRollback = try AutomaticFixture(rollbackFails: true)
        #expect(try await noRollback.coordinator.process(.fixture) == .held(.rollbackUnavailable))

        let failingProbe = FakeAutomaticProbe(id: .images, outcome: .failed("decode"))
        let preflight = try AutomaticFixture(probeRegistry: ProbeRegistry(probes: [failingProbe]))
        #expect(try await preflight.coordinator.process(.fixture) == .held(.preflightFailed))
        #expect(await preflight.blocker.records.map(\.failedProbeID) == [.images])
        #expect(preflight.actions.values.contains("upgrade") == false)
    }

    @Test func `work appearing at final check remains pending`() async throws {
        let fixture = try AutomaticFixture(activity: [.init(), .init(activeMachines: 1)])

        #expect(try await fixture.coordinator.process(.fixture) == .pending(.workActive))
        #expect(fixture.actions.values == ["context", "package", "rollback", "final-idle"])
    }

    @Test func `transaction rollback and recovery requirement persist target block`() async throws {
        let rolledBack = try AutomaticFixture(upgradeError: .rolledBack)
        #expect(try await rolledBack.coordinator.process(.fixture) ==
            .rolledBack(previousVersion: "1.0.0", failedProbeID: nil))
        #expect(await rolledBack.blocker.records.count == 1)

        let recovery = try AutomaticFixture(upgradeError: .recoveryRequired(.previousProbes))
        #expect(try await recovery.coordinator.process(.fixture) ==
            .recoveryRequired(code: RollbackStage.previousProbes.rawValue))
        #expect(await recovery.blocker.records.count == 1)
    }

    @Test func `cancellation before mutation propagates`() async throws {
        let fixture = try AutomaticFixture(rollbackDelay: .seconds(30))
        let task = Task { try await fixture.coordinator.process(.fixture) }
        await fixture.rollback.waitUntilRequested()
        task.cancel()

        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(fixture.actions.values.contains("upgrade") == false)
    }
}

private final class AutomaticFixture {
    let candidate: RuntimeReleaseCandidate
    let actions = LockedAutomaticActions()
    let provider: RecordingAutomaticContextProvider
    let package: RecordingAutomaticPackageVerifier
    let rollback: RecordingRollbackAvailability
    let executor: RecordingAutomaticExecutor
    let blocker = RecordingAutomaticBlocker()
    let sink = RecordingAutomaticSink()
    let coordinator: RuntimeUpdateCoordinator

    init(
        candidateVersion: String = "1.1.0",
        candidateDigest: String? = nil,
        activity: [RuntimeActivitySnapshot] = [.init(), .init()],
        packageFails: Bool = false,
        rollbackFails: Bool = false,
        rollbackDelay: Duration = .zero,
        upgradeError: UpgradeError? = nil,
        probeRegistry: ProbeRegistry = ProbeRegistry()
    ) throws {
        let catalog = try CompatibilityCatalog.bundled()
        let entry = try #require(catalog.entries.first)
        candidate = RuntimeReleaseCandidate(
            version: candidateVersion,
            packageURL: URL(string: "https://github.com/apple/container/releases/download/1.1.0/container-1.1.0-installer-signed.pkg")!,
            packageSHA256: candidateDigest ?? entry.package.sha256
        )
        provider = RecordingAutomaticContextProvider(
            actions: actions,
            catalog: catalog,
            entry: entry,
            activity: activity
        )
        package = RecordingAutomaticPackageVerifier(actions: actions, fails: packageFails)
        rollback = RecordingRollbackAvailability(
            actions: actions,
            fails: rollbackFails,
            delay: rollbackDelay
        )
        executor = RecordingAutomaticExecutor(actions: actions, error: upgradeError)
        coordinator = RuntimeUpdateCoordinator(
            contextProvider: provider,
            packageVerifier: package,
            rollbackAvailability: rollback,
            probeRegistry: probeRegistry,
            executor: executor,
            blocker: blocker,
            stateSink: sink
        )
    }
}

private final class LockedAutomaticActions: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    var values: [String] {
        lock.withLock { storage }
    }

    func append(_ value: String) {
        lock.withLock { storage.append(value) }
    }
}

private actor RecordingAutomaticContextProvider: AutomaticUpdateContextProviding {
    let actions: LockedAutomaticActions
    let catalog: CompatibilityCatalog
    let entry: CompatibilityEntry
    var activity: [RuntimeActivitySnapshot]

    init(
        actions: LockedAutomaticActions,
        catalog: CompatibilityCatalog,
        entry: CompatibilityEntry,
        activity: [RuntimeActivitySnapshot]
    ) {
        self.actions = actions
        self.catalog = catalog
        self.entry = entry
        self.activity = activity
    }

    func context(for _: RuntimeReleaseCandidate) async throws -> AutomaticUpdateContext {
        actions.append("context")
        let initialActivity = activity.isEmpty ? RuntimeActivitySnapshot() : activity.removeFirst()
        return AutomaticUpdateContext(
            catalog: catalog,
            appVersion: "0.1.0",
            host: HostProfile(
                logicalCPUs: 8,
                physicalMemoryBytes: 16 * 1_073_741_824,
                chip: .appleSilicon,
                macOSMajor: 26,
                capabilities: []
            ),
            installedRuntimeVersion: "1.0.0",
            installedPackageSHA256: entry.allowedUpgradeSources[0].packageSHA256,
            verifiedAttestationIDs: [entry.attestation.id],
            blockedAttestationID: nil,
            destructiveMigrationConsent: false,
            mode: .automaticWhenIdle,
            consentVersion: RuntimeUpdatePolicy.currentConsentVersion,
            helperAuthorized: true,
            activity: initialActivity,
            bridge: FakeRuntimeBridge(),
            enabledCapabilityIDs: entry.capabilityIDs
        )
    }

    func currentActivity() async throws -> RuntimeActivitySnapshot {
        actions.append("final-idle")
        guard !activity.isEmpty else { return .init() }
        return activity.removeFirst()
    }
}

private struct RecordingAutomaticPackageVerifier: AutomaticUpdatePackageVerifying {
    let actions: LockedAutomaticActions
    let fails: Bool

    func verify(
        candidate: RuntimeReleaseCandidate,
        entry: CompatibilityEntry
    ) async throws -> RuntimeUpgradeTarget {
        actions.append("package")
        if fails {
            throw AutomaticFixtureError.injected
        }
        let install = RuntimeInstallTarget(
            manifest: ReviewedRuntime110Manifest.package,
            releaseAPIURL: candidate.packageURL,
            requiredProbes: entry.requiredProbeIDs
        )
        return RuntimeUpgradeTarget(
            installTarget: install,
            requiresFullDataRollback: entry.rollback == .fullDataClone,
            destroysStorageCompatibility: entry.storageMigration == .destructive
        )
    }
}

private actor RecordingRollbackAvailability: AutomaticRollbackAvailabilityChecking {
    let actions: LockedAutomaticActions
    let fails: Bool
    let delay: Duration
    private var requested = false

    init(actions: LockedAutomaticActions, fails: Bool, delay: Duration) {
        self.actions = actions
        self.fails = fails
        self.delay = delay
    }

    func check(target _: RuntimeUpgradeTarget) async throws {
        actions.append("rollback")
        requested = true
        try await ContinuousClock().sleep(for: delay)
        if fails {
            throw AutomaticFixtureError.injected
        }
    }

    func waitUntilRequested() async {
        while !requested {
            await Task.yield()
        }
    }
}

private struct RecordingAutomaticExecutor: AutomaticUpgradeExecuting {
    let actions: LockedAutomaticActions
    let error: UpgradeError?

    func upgrade(to target: RuntimeUpgradeTarget) async throws -> UpgradeReport {
        actions.append("upgrade")
        if let error {
            throw error
        }
        return UpgradeReport(previousRuntimeVersion: "1.0.0", runtimeVersion: target.version, kind: .upgrade)
    }
}

private actor RecordingAutomaticBlocker: AutomaticUpdateBlocking {
    struct Record: Sendable {
        let failedProbeID: ProbeID?
    }

    var records: [Record] = []

    func block(
        entry _: CompatibilityEntry,
        catalogRevision _: String,
        appVersion _: String,
        failedProbeID: ProbeID?
    ) async throws {
        records.append(.init(failedProbeID: failedProbeID))
    }
}

private actor RecordingAutomaticSink: RuntimeUpdateStateSink {
    var states: [RuntimeUpdateState] = []
    func publish(_ state: RuntimeUpdateState) {
        states.append(state)
    }
}

private struct FakeAutomaticProbe: CompatibilityProbe {
    let id: ProbeID
    let outcome: ProbeOutcome
    func run(context _: ProbeContext) async -> ProbeResult {
        .init(id: id, outcome: outcome)
    }
}

private enum AutomaticFixtureError: Error {
    case injected
}

private extension RuntimeReleaseCandidate {
    static let fixture = Self(
        version: "1.1.0",
        packageURL: URL(string: "https://github.com/apple/container/releases/download/1.1.0/container-1.1.0-installer-signed.pkg")!,
        packageSHA256: "0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714"
    )
}
