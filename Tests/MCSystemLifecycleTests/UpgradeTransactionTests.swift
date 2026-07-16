import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("Runtime upgrade and rollback transaction")
struct UpgradeTransactionTests {
    @Test func `successful upgrade commits only after target probes`() async throws {
        let fixture = try UpgradeFixture()
        defer { fixture.cleanup() }

        let report = try await fixture.transaction.upgrade(to: .upgradeFixture)

        #expect(report.runtimeVersion == "1.1.0")
        #expect(fixture.actions.values.filter { $0.hasPrefix("upgrade.") } == UpgradeStage.allCases.map(\.rawValue))
        #expect(fixture.helper.installedVersions == ["1.1.0"])
        #expect(fixture.probes.runs == [RuntimeUpgradeTarget.upgradeFixture.requiredProbes])
        #expect(fixture.rollback.discardCount == 1)
        #expect(fixture.preparer.cleanupCount == 1)
    }

    @Test func `refuses upgrade when work appears at final idle check`() async throws {
        let fixture = try UpgradeFixture(workloads: [[], ["container:web"]])
        defer { fixture.cleanup() }

        await #expect(throws: UpgradeError.workBecameActive(["container:web"])) {
            _ = try await fixture.transaction.upgrade(to: .upgradeFixture)
        }

        #expect(fixture.helper.installedVersions.isEmpty)
        #expect(fixture.services.stopCount == 0)
        #expect(fixture.rollback.discardCount == 1)
    }

    @Test func `postflight failure restores previous verified runtime and blocks target`() async throws {
        let fixture = try UpgradeFixture(failingAt: .targetProbes)
        defer { fixture.cleanup() }

        await #expect(throws: UpgradeError.rolledBack) {
            _ = try await fixture.transaction.upgrade(to: .upgradeFixture)
        }

        #expect(fixture.helper.installedVersions == ["1.1.0", "1.0.0"])
        #expect(fixture.rollback.restoreCount == 1)
        #expect(fixture.probes.runs.last == RuntimeInstallTarget.previousFixture.requiredProbes)
        #expect(fixture.blocker.blockedVersions == ["1.1.0"])
        #expect(fixture.diagnostics.failureCodes == ["upgrade.upgrade.probes.run"])
    }

    @Test(arguments: UpgradeStage.allCases)
    func `failure at every upgrade stage never reports success`(_ stage: UpgradeStage) async throws {
        let fixture = try UpgradeFixture(failingAt: stage)
        defer { fixture.cleanup() }

        await #expect(throws: UpgradeError.self) {
            _ = try await fixture.transaction.upgrade(to: .upgradeFixture)
        }

        let stopAttempted = try #require(UpgradeStage.allCases.firstIndex(of: stage)) >=
            UpgradeStage.allCases.firstIndex(of: .serviceStop)!
        #expect(fixture.blocker.blockedVersions == (stopAttempted ? ["1.1.0"] : []))
        #expect(fixture.preparer.cleanupCount == (stage == .packagePreparation ? 0 : 1))
    }

    @Test(arguments: RollbackStage.allCases)
    func `failure at every rollback stage requires recovery and keeps target blocked`(
        _ rollbackStage: RollbackStage
    ) async throws {
        let fixture = try UpgradeFixture(
            failingAt: .targetProbes,
            failingRollbackAt: rollbackStage
        )
        defer { fixture.cleanup() }

        await #expect(throws: UpgradeError.recoveryRequired(rollbackStage)) {
            _ = try await fixture.transaction.upgrade(to: .upgradeFixture)
        }
        #expect(fixture.blocker.blockAttempts == 1)
    }

    @Test func `downgrade requires explicit destructive storage consent`() async throws {
        let fixture = try UpgradeFixture(
            previousTarget: .newerFixture,
            downgradeApproved: false
        )
        defer { fixture.cleanup() }

        await #expect(throws: UpgradeError.downgradeConsentRequired) {
            _ = try await fixture.transaction.upgrade(to: .upgradeFixture)
        }
        #expect(fixture.consent.requests == [
            .init(fromVersion: "2.0.0", toVersion: "1.1.0", destroysStorageCompatibility: true)
        ])
        #expect(fixture.services.stopCount == 0)
        #expect(fixture.rollback.createCount == 0)
    }
}

private final class UpgradeFixture {
    let root: URL
    let actions: LockedUpgradeActions
    let preparer: RecordingUpgradePackagePreparer
    let rollback: RecordingUpgradeRollbackManager
    let helper: RecordingUpgradeHelper
    let services: RecordingUpgradeServices
    let probes: RecordingUpgradeProbes
    let blocker: RecordingUpgradeBlocker
    let diagnostics: RecordingUpgradeDiagnostics
    let consent: RecordingDowngradeConsent
    let transaction: UpgradeTransaction

    init(
        failingAt: UpgradeStage? = nil,
        failingRollbackAt: RollbackStage? = nil,
        workloads: [[String]] = [[], []],
        previousTarget: RuntimeInstallTarget = .previousFixture,
        downgradeApproved: Bool = true
    ) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainerUpgradeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        actions = LockedUpgradeActions(failingAt: failingAt)
        let targetPackage = try RuntimePackageFile.fixture(
            at: root.appendingPathComponent("target.pkg"),
            manifest: RuntimeUpgradeTarget.upgradeFixture.installTarget.manifest
        )
        let previousPackage = try RuntimePackageFile.fixture(
            at: root.appendingPathComponent("previous.pkg"),
            manifest: previousTarget.manifest
        )
        let configuration = root.appendingPathComponent("configuration.json")
        try Data("configuration".utf8).write(to: configuration)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configuration.path)
        preparer = RecordingUpgradePackagePreparer(actions: actions, package: targetPackage)
        rollback = RecordingUpgradeRollbackManager(
            actions: actions,
            previousPackage: previousPackage,
            failingAt: failingRollbackAt
        )
        helper = RecordingUpgradeHelper(actions: actions)
        services = RecordingUpgradeServices(actions: actions, failingRollbackAt: failingRollbackAt)
        probes = RecordingUpgradeProbes(actions: actions, failingRollbackAt: failingRollbackAt)
        blocker = RecordingUpgradeBlocker(actions: actions, failingRollbackAt: failingRollbackAt)
        diagnostics = RecordingUpgradeDiagnostics(actions: actions, failingRollbackAt: failingRollbackAt)
        consent = RecordingDowngradeConsent(approved: downgradeApproved)
        transaction = UpgradeTransaction(
            packagePreparer: preparer,
            baselineCapture: RecordingUpgradeBaselineCapture(
                actions: actions,
                baseline: .init(
                    previousTarget: previousTarget,
                    previousPackageURL: previousPackage.openFile.sourceURL,
                    configurationAndMetadata: [configuration],
                    fullData: []
                )
            ),
            previousPackageVerifier: RecordingPreviousPackageVerifier(
                actions: actions,
                package: previousPackage
            ),
            rollback: rollback,
            workloads: RecordingUpgradeWorkloads(actions: actions, snapshots: workloads),
            services: services,
            helper: helper,
            installedRuntimeVerifier: RecordingInstalledRuntimeVerifier(actions: actions),
            probes: probes,
            journal: RecordingUpgradeJournal(actions: actions),
            blocker: blocker,
            diagnostics: diagnostics,
            downgradeConsent: consent
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class LockedUpgradeActions: @unchecked Sendable {
    private let lock = NSLock()
    private let failingAt: UpgradeStage?
    private var storage: [String] = []

    init(failingAt: UpgradeStage?) {
        self.failingAt = failingAt
    }

    var values: [String] {
        lock.withLock { storage }
    }

    func stage(_ stage: UpgradeStage) throws {
        lock.withLock { storage.append(stage.rawValue) }
        if failingAt == stage {
            throw UpgradeFixtureFailure.injected
        }
    }

    func append(_ value: String) {
        lock.withLock { storage.append(value) }
    }
}

private final class RecordingUpgradePackagePreparer: UpgradePackagePreparing, @unchecked Sendable {
    let actions: LockedUpgradeActions
    let package: VerifiedRuntimePackage
    private(set) var cleanupCount = 0

    init(actions: LockedUpgradeActions, package: VerifiedRuntimePackage) {
        self.actions = actions
        self.package = package
    }

    func prepare(_ target: RuntimeUpgradeTarget) async throws -> PreparedUpgradePackage {
        _ = target
        try actions.stage(.packagePreparation)
        return PreparedUpgradePackage(package: package) { [weak self] in
            self?.cleanupCount += 1
        }
    }
}

private struct RecordingUpgradeBaselineCapture: UpgradeBaselineCapturing {
    let actions: LockedUpgradeActions
    let baseline: UpgradeBaseline

    func capture() async throws -> UpgradeBaseline {
        try actions.stage(.baselineCapture)
        return baseline
    }
}

private struct RecordingPreviousPackageVerifier: PreviousRuntimePackageVerifying {
    let actions: LockedUpgradeActions
    let package: VerifiedRuntimePackage

    func verify(_ baseline: UpgradeBaseline) async throws -> VerifiedRuntimePackage {
        _ = baseline
        try actions.stage(.previousPackageVerification)
        return package
    }
}

private final class RecordingUpgradeRollbackManager: UpgradeRollbackManaging, @unchecked Sendable {
    let actions: LockedUpgradeActions
    let previousPackage: VerifiedRuntimePackage
    let failingAt: RollbackStage?
    private(set) var createCount = 0
    private(set) var restoreCount = 0
    private(set) var discardCount = 0

    init(
        actions: LockedUpgradeActions,
        previousPackage: VerifiedRuntimePackage,
        failingAt: RollbackStage?
    ) {
        self.actions = actions
        self.previousPackage = previousPackage
        self.failingAt = failingAt
    }

    func createPoint(
        from baseline: UpgradeBaseline,
        verifiedPrevious: VerifiedRuntimePackage,
        requiresFullData: Bool
    ) async throws -> UpgradeRollbackPoint {
        _ = baseline
        _ = verifiedPrevious
        _ = requiresFullData
        createCount += 1
        try actions.stage(.rollbackPointCreation)
        return .init(id: UUID(), previousProbes: baseline.previousTarget.requiredProbes)
    }

    func previousPackage(in point: UpgradeRollbackPoint) async throws -> VerifiedRuntimePackage {
        _ = point
        if failingAt == .previousPackageReinstall {
            throw UpgradeFixtureFailure.injected
        }
        return previousPackage
    }

    func restore(_ point: UpgradeRollbackPoint) async throws {
        _ = point
        actions.append(RollbackStage.dataRestore.rawValue)
        if failingAt == .dataRestore {
            throw UpgradeFixtureFailure.injected
        }
        restoreCount += 1
    }

    func discard(_ point: UpgradeRollbackPoint) async throws {
        _ = point
        discardCount += 1
    }
}

private final class RecordingUpgradeWorkloads: UpgradeWorkObserving, @unchecked Sendable {
    let actions: LockedUpgradeActions
    private let lock = NSLock()
    private var snapshots: [[String]]
    private var callCount = 0

    init(actions: LockedUpgradeActions, snapshots: [[String]]) {
        self.actions = actions
        self.snapshots = snapshots
    }

    func activeWork() async throws -> [String] {
        let result = lock.withLock {
            callCount += 1
            return snapshots.isEmpty ? [] : snapshots.removeFirst()
        }
        if lock.withLock({ callCount }) == 2 {
            try actions.stage(.finalIdleCheck)
        }
        return result
    }
}

private final class RecordingUpgradeServices: UpgradeServiceControlling, @unchecked Sendable {
    let actions: LockedUpgradeActions
    let failingRollbackAt: RollbackStage?
    private(set) var stopCount = 0

    init(actions: LockedUpgradeActions, failingRollbackAt: RollbackStage?) {
        self.actions = actions
        self.failingRollbackAt = failingRollbackAt
    }

    func stopRuntime() async throws {
        stopCount += 1
        if stopCount == 1 {
            try actions.stage(.serviceStop)
        } else {
            actions.append(RollbackStage.targetStop.rawValue)
            if failingRollbackAt == .targetStop {
                throw UpgradeFixtureFailure.injected
            }
        }
    }

    func startRuntime(expectedVersion: String) async throws {
        if expectedVersion == "1.1.0" {
            try actions.stage(.serviceStart)
        } else {
            actions.append(RollbackStage.previousServiceStart.rawValue)
            if failingRollbackAt == .previousServiceStart {
                throw UpgradeFixtureFailure.injected
            }
        }
    }
}

private final class RecordingUpgradeHelper: UpgradePrivilegedHelping, @unchecked Sendable {
    let actions: LockedUpgradeActions
    private(set) var installedVersions: [String] = []

    init(actions: LockedUpgradeActions) {
        self.actions = actions
    }

    func install(_ package: VerifiedRuntimePackage) async throws {
        installedVersions.append(package.runtimeVersion)
        if installedVersions.count == 1 {
            try actions.stage(.targetInstall)
        } else {
            actions.append(RollbackStage.previousPackageReinstall.rawValue)
        }
    }
}

private struct RecordingInstalledRuntimeVerifier: UpgradeInstalledRuntimeVerifying {
    let actions: LockedUpgradeActions

    func verify(target: RuntimeUpgradeTarget) async throws -> UpgradeVersionAgreement {
        try actions.stage(.targetVerification)
        let version = target.version
        return .init(receipt: version, payload: version, binary: version, api: version)
    }
}

private final class RecordingUpgradeProbes: UpgradeProbeRunning, @unchecked Sendable {
    let actions: LockedUpgradeActions
    let failingRollbackAt: RollbackStage?
    private(set) var runs: [[String]] = []

    init(actions: LockedUpgradeActions, failingRollbackAt: RollbackStage?) {
        self.actions = actions
        self.failingRollbackAt = failingRollbackAt
    }

    func run(probes: [String], runtimeVersion: String) async throws {
        _ = runtimeVersion
        runs.append(probes)
        if runs.count == 1 {
            try actions.stage(.targetProbes)
        } else {
            actions.append(RollbackStage.previousProbes.rawValue)
            if failingRollbackAt == .previousProbes {
                throw UpgradeFixtureFailure.injected
            }
        }
    }
}

private struct RecordingUpgradeJournal: UpgradeJournalWriting {
    let actions: LockedUpgradeActions

    func begin(kind: LifecycleKind, targetVersion: String) async throws -> UUID {
        _ = kind
        _ = targetVersion
        return UUID()
    }

    func recordInstallIntent(transactionID: UUID, digest: String) async throws {
        _ = transactionID
        _ = digest
    }

    func recordInstallApplied(transactionID: UUID, digest: String) async throws {
        _ = transactionID
        _ = digest
    }

    func commit(transactionID: UUID) async throws {
        _ = transactionID
        try actions.stage(.journalCommit)
    }

    func beginRollback(transactionID: UUID, pointID: UUID) async throws {
        _ = transactionID
        _ = pointID
    }

    func finishRollback(transactionID: UUID) async throws {
        _ = transactionID
    }

    func fail(transactionID: UUID, failure: RedactedLifecycleFailure) async throws {
        _ = transactionID
        _ = failure
    }
}

private final class RecordingUpgradeBlocker: UpgradeTargetBlocking, @unchecked Sendable {
    let actions: LockedUpgradeActions
    let failingRollbackAt: RollbackStage?
    private(set) var blockedVersions: [String] = []
    private(set) var blockAttempts = 0

    init(actions: LockedUpgradeActions, failingRollbackAt: RollbackStage?) {
        self.actions = actions
        self.failingRollbackAt = failingRollbackAt
    }

    func block(version: String, failureCode: String) async throws {
        _ = failureCode
        blockAttempts += 1
        actions.append(RollbackStage.targetBlock.rawValue)
        if failingRollbackAt == .targetBlock {
            throw UpgradeFixtureFailure.injected
        }
        blockedVersions.append(version)
    }
}

private final class RecordingUpgradeDiagnostics: UpgradeDiagnosticPersisting, @unchecked Sendable {
    let actions: LockedUpgradeActions
    let failingRollbackAt: RollbackStage?
    private(set) var failureCodes: [String] = []

    init(actions: LockedUpgradeActions, failingRollbackAt: RollbackStage?) {
        self.actions = actions
        self.failingRollbackAt = failingRollbackAt
    }

    func persist(_ failure: RedactedLifecycleFailure) async throws {
        actions.append(RollbackStage.diagnosticPersist.rawValue)
        if failingRollbackAt == .diagnosticPersist {
            throw UpgradeFixtureFailure.injected
        }
        failureCodes.append(failure.code)
    }
}

private final class RecordingDowngradeConsent: UpgradeDowngradeConsentProviding, @unchecked Sendable {
    let approved: Bool
    private(set) var requests: [DowngradeConsentRequest] = []

    init(approved: Bool) {
        self.approved = approved
    }

    func approve(_ request: DowngradeConsentRequest) async throws -> Bool {
        requests.append(request)
        return approved
    }
}

private enum UpgradeFixtureFailure: Error {
    case injected
}

private enum RuntimePackageFile {
    static func fixture(at url: URL, manifest: RuntimePackageManifest) throws -> VerifiedRuntimePackage {
        try Data("verified-package-\(manifest.runtimeVersion)".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try VerifiedRuntimePackage(
            runtimeVersion: manifest.runtimeVersion,
            sha256: manifest.sha256,
            installerTeamID: manifest.installerTeamID,
            signerCommonName: manifest.signerCommonName,
            receiptIdentifier: manifest.receiptIdentifier,
            installLocation: manifest.installLocation,
            payload: manifest.payload,
            openFile: OpenRuntimePackageFile(duplicating: handle.fileDescriptor)
        )
    }
}

private extension RuntimeInstallTarget {
    static let previousFixture = Self(
        manifest: .upgradeFixture(version: "1.0.0", digestCharacter: "a"),
        releaseAPIURL: fixtureURL("https://api.github.com/repos/apple/container/releases/tags/1.0.0"),
        requiredProbes: ["health", "images"]
    )

    static let newerFixture = Self(
        manifest: .upgradeFixture(version: "2.0.0", digestCharacter: "c"),
        releaseAPIURL: fixtureURL("https://api.github.com/repos/apple/container/releases/tags/2.0.0"),
        requiredProbes: ["health", "capabilities"]
    )
}

private extension RuntimeUpgradeTarget {
    static let upgradeFixture = Self(
        installTarget: .init(
            manifest: .upgradeFixture(version: "1.1.0", digestCharacter: "b"),
            releaseAPIURL: fixtureURL("https://api.github.com/repos/apple/container/releases/tags/1.1.0"),
            requiredProbes: ["health", "images", "capabilities"]
        ),
        requiresFullDataRollback: true,
        destroysStorageCompatibility: true
    )
}

private extension RuntimePackageManifest {
    static func upgradeFixture(version: String, digestCharacter: Character) -> Self {
        Self(
            runtimeVersion: version,
            assetName: "container-\(version)-installer-signed.pkg",
            sha256: String(repeating: digestCharacter, count: 64),
            installerTeamID: "UPBK2H6LZM",
            signerCommonName: "Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)",
            receiptIdentifier: "com.apple.container-installer",
            installLocation: "/usr/local",
            payload: [
                .init(relativePath: "bin", kind: .directory),
                .init(
                    relativePath: "bin/container",
                    kind: .file,
                    sha256: String(repeating: digestCharacter, count: 64)
                )
            ]
        )
    }
}

private func fixtureURL(_ value: String) -> URL {
    guard let url = URL(string: value) else { preconditionFailure("Invalid fixture URL") }
    return url
}
