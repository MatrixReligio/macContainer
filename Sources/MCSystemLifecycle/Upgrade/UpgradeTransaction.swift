import Foundation

public enum UpgradeStage: String, CaseIterable, Codable, Sendable {
    case packagePreparation = "upgrade.package.prepare"
    case baselineCapture = "upgrade.baseline.capture"
    case previousPackageVerification = "upgrade.previous-package.verify"
    case rollbackPointCreation = "upgrade.rollback-point.create"
    case finalIdleCheck = "upgrade.idle.final-check"
    case serviceStop = "upgrade.service.stop"
    case targetInstall = "upgrade.target.install"
    case serviceStart = "upgrade.service.start"
    case targetVerification = "upgrade.target.verify"
    case targetProbes = "upgrade.probes.run"
    case packageRetention = "upgrade.package.retain"
    case journalCommit = "upgrade.journal.commit"

    public var requiresRollbackOnFailure: Bool {
        guard
            let current = Self.allCases.firstIndex(of: self),
            let irreversible = Self.allCases.firstIndex(of: .serviceStop)
        else {
            return false
        }
        return current >= irreversible
    }
}

public enum RollbackStage: String, CaseIterable, Codable, Sendable {
    case targetStop = "rollback.target.stop"
    case previousPackageReinstall = "rollback.previous-package.reinstall"
    case dataRestore = "rollback.data.restore"
    case previousServiceStart = "rollback.previous-service.start"
    case previousProbes = "rollback.previous-probes.run"
    case diagnosticPersist = "rollback.diagnostic.persist"
    case targetBlock = "rollback.target.block"
}

public struct RuntimeUpgradeTarget: Equatable, Sendable {
    public let installTarget: RuntimeInstallTarget
    public let requiresFullDataRollback: Bool
    public let destroysStorageCompatibility: Bool

    public var version: String {
        installTarget.manifest.runtimeVersion
    }

    public var requiredProbes: [String] {
        installTarget.requiredProbes
    }

    public init(
        installTarget: RuntimeInstallTarget,
        requiresFullDataRollback: Bool,
        destroysStorageCompatibility: Bool
    ) {
        self.installTarget = installTarget
        self.requiresFullDataRollback = requiresFullDataRollback
        self.destroysStorageCompatibility = destroysStorageCompatibility
    }
}

public struct UpgradeBaseline: Equatable, Sendable {
    public let previousTarget: RuntimeInstallTarget
    public let previousPackageURL: URL
    public let configurationAndMetadata: [URL]
    public let fullData: [URL]

    public init(
        previousTarget: RuntimeInstallTarget,
        previousPackageURL: URL,
        configurationAndMetadata: [URL],
        fullData: [URL]
    ) {
        self.previousTarget = previousTarget
        self.previousPackageURL = previousPackageURL.standardizedFileURL
        self.configurationAndMetadata = configurationAndMetadata.map(\.standardizedFileURL)
        self.fullData = fullData.map(\.standardizedFileURL)
    }
}

public struct UpgradeVersionAgreement: Equatable, Sendable {
    public let receipt: String
    public let payload: String
    public let binary: String
    public let api: String

    public init(receipt: String, payload: String, binary: String, api: String) {
        self.receipt = receipt
        self.payload = payload
        self.binary = binary
        self.api = api
    }

    public func agrees(with expectedVersion: String) -> Bool {
        receipt == expectedVersion && payload == expectedVersion &&
            binary == expectedVersion && api == expectedVersion
    }
}

public struct UpgradeReport: Equatable, Sendable {
    public let previousRuntimeVersion: String
    public let runtimeVersion: String
    public let kind: LifecycleKind

    public init(previousRuntimeVersion: String, runtimeVersion: String, kind: LifecycleKind) {
        self.previousRuntimeVersion = previousRuntimeVersion
        self.runtimeVersion = runtimeVersion
        self.kind = kind
    }
}

public struct DowngradeConsentRequest: Equatable, Sendable {
    public let fromVersion: String
    public let toVersion: String
    public let destroysStorageCompatibility: Bool

    public init(
        fromVersion: String,
        toVersion: String,
        destroysStorageCompatibility: Bool
    ) {
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.destroysStorageCompatibility = destroysStorageCompatibility
    }
}

public struct UpgradeRollbackPoint: Equatable, Sendable {
    public let id: UUID
    public let previousProbes: [String]

    public init(id: UUID, previousProbes: [String] = []) {
        self.id = id
        self.previousProbes = previousProbes
    }
}

public final class PreparedUpgradePackage: @unchecked Sendable {
    public let package: VerifiedRuntimePackage
    private let lock = NSLock()
    private let cleanupAction: @Sendable () throws -> Void
    private var cleaned = false

    public init(
        package: VerifiedRuntimePackage,
        cleanup: @escaping @Sendable () throws -> Void
    ) {
        self.package = package
        cleanupAction = cleanup
    }

    deinit {
        try? cleanup()
    }

    public func cleanup() throws {
        try lock.withLock {
            guard !cleaned else { return }
            try cleanupAction()
            cleaned = true
        }
    }
}

public protocol UpgradePackagePreparing: Sendable {
    func prepare(_ target: RuntimeUpgradeTarget) async throws -> PreparedUpgradePackage
}

public protocol UpgradeBaselineCapturing: Sendable {
    func capture() async throws -> UpgradeBaseline
}

public protocol PreviousRuntimePackageVerifying: Sendable {
    func verify(_ baseline: UpgradeBaseline) async throws -> VerifiedRuntimePackage
}

public protocol UpgradeRollbackManaging: Sendable {
    func createPoint(
        from baseline: UpgradeBaseline,
        verifiedPrevious: VerifiedRuntimePackage,
        requiresFullData: Bool
    ) async throws -> UpgradeRollbackPoint
    func previousPackage(in point: UpgradeRollbackPoint) async throws -> VerifiedRuntimePackage
    func restore(_ point: UpgradeRollbackPoint) async throws
    func discard(_ point: UpgradeRollbackPoint) async throws
}

public protocol UpgradeWorkObserving: Sendable {
    func activeWork() async throws -> [String]
}

public protocol UpgradeServiceControlling: Sendable {
    func stopRuntime() async throws
    func startRuntime(expectedVersion: String) async throws
}

public protocol UpgradePrivilegedHelping: Sendable {
    func install(_ package: VerifiedRuntimePackage) async throws
}

extension HelperClient: UpgradePrivilegedHelping {}

public protocol UpgradeInstalledRuntimeVerifying: Sendable {
    func verify(target: RuntimeUpgradeTarget) async throws -> UpgradeVersionAgreement
}

public protocol UpgradeProbeRunning: Sendable {
    func run(probes: [String], runtimeVersion: String) async throws
}

public protocol UpgradeJournalWriting: Sendable {
    func begin(kind: LifecycleKind, targetVersion: String) async throws -> UUID
    func recordInstallIntent(transactionID: UUID, digest: String) async throws
    func recordInstallApplied(transactionID: UUID, digest: String) async throws
    func recordRollbackPoint(transactionID: UUID, pointID: UUID) async throws
    func commit(transactionID: UUID) async throws
    func beginRollback(transactionID: UUID, pointID: UUID) async throws
    func finishRollback(transactionID: UUID) async throws
    func fail(transactionID: UUID, failure: RedactedLifecycleFailure) async throws
}

public protocol UpgradeTargetBlocking: Sendable {
    func block(version: String, failureCode: String) async throws
}

public protocol UpgradeDiagnosticPersisting: Sendable {
    func persist(_ failure: RedactedLifecycleFailure) async throws
}

public protocol UpgradeDowngradeConsentProviding: Sendable {
    func approve(_ request: DowngradeConsentRequest) async throws -> Bool
}

public struct LifecycleUpgradeJournalWriter: UpgradeJournalWriting {
    private let journal: LifecycleJournal

    public init(journal: LifecycleJournal) {
        self.journal = journal
    }

    public func begin(kind: LifecycleKind, targetVersion: String) async throws -> UUID {
        try await journal.begin(kind: kind, targetVersion: targetVersion)
    }

    public func recordInstallIntent(transactionID: UUID, digest: String) async throws {
        try await journal.recordIntent(.installPackage(digest: digest), transactionID: transactionID)
    }

    public func recordInstallApplied(transactionID: UUID, digest: String) async throws {
        try await journal.recordApplied(.installPackage(digest: digest), transactionID: transactionID)
    }

    public func recordRollbackPoint(transactionID: UUID, pointID: UUID) async throws {
        let action = LifecycleAction.retainRollbackPoint(identifier: pointID)
        try await journal.recordIntent(action, transactionID: transactionID)
        try await journal.recordApplied(action, transactionID: transactionID)
    }

    public func commit(transactionID: UUID) async throws {
        try await journal.recordVerified(transactionID: transactionID)
        try await journal.commit(transactionID: transactionID)
    }

    public func beginRollback(transactionID: UUID, pointID: UUID) async throws {
        try await journal.recordRollingBack(
            .restoreRollbackPoint(identifier: pointID),
            transactionID: transactionID
        )
    }

    public func finishRollback(transactionID: UUID) async throws {
        try await journal.recordRolledBack(transactionID: transactionID)
    }

    public func fail(transactionID: UUID, failure: RedactedLifecycleFailure) async throws {
        try await journal.recordFailure(failure, transactionID: transactionID)
    }
}

public struct UpgradeTransaction: Sendable {
    private let packagePreparer: any UpgradePackagePreparing
    private let baselineCapture: any UpgradeBaselineCapturing
    private let previousPackageVerifier: any PreviousRuntimePackageVerifying
    private let rollback: any UpgradeRollbackManaging
    private let workloads: any UpgradeWorkObserving
    private let services: any UpgradeServiceControlling
    private let helper: any UpgradePrivilegedHelping
    private let installedRuntimeVerifier: any UpgradeInstalledRuntimeVerifying
    private let probes: any UpgradeProbeRunning
    private let journal: any UpgradeJournalWriting
    private let blocker: any UpgradeTargetBlocking
    private let diagnostics: any UpgradeDiagnosticPersisting
    private let downgradeConsent: any UpgradeDowngradeConsentProviding
    private let packageRetainer: any InstallPackageRetaining

    public init(
        packagePreparer: any UpgradePackagePreparing,
        baselineCapture: any UpgradeBaselineCapturing,
        previousPackageVerifier: any PreviousRuntimePackageVerifying,
        rollback: any UpgradeRollbackManaging,
        workloads: any UpgradeWorkObserving,
        services: any UpgradeServiceControlling,
        helper: any UpgradePrivilegedHelping,
        installedRuntimeVerifier: any UpgradeInstalledRuntimeVerifying,
        probes: any UpgradeProbeRunning,
        journal: any UpgradeJournalWriting,
        blocker: any UpgradeTargetBlocking,
        diagnostics: any UpgradeDiagnosticPersisting,
        downgradeConsent: any UpgradeDowngradeConsentProviding,
        packageRetainer: any InstallPackageRetaining = NoOpInstallPackageRetainer()
    ) {
        self.packagePreparer = packagePreparer
        self.baselineCapture = baselineCapture
        self.previousPackageVerifier = previousPackageVerifier
        self.rollback = rollback
        self.workloads = workloads
        self.services = services
        self.helper = helper
        self.installedRuntimeVerifier = installedRuntimeVerifier
        self.probes = probes
        self.journal = journal
        self.blocker = blocker
        self.diagnostics = diagnostics
        self.downgradeConsent = downgradeConsent
        self.packageRetainer = packageRetainer
    }

    public func upgrade(to target: RuntimeUpgradeTarget) async throws -> UpgradeReport {
        var currentStage = UpgradeStage.packagePreparation
        let prepared: PreparedUpgradePackage
        do {
            try validate(target)
            prepared = try await packagePreparer.prepare(target)
            try validate(prepared.package, against: target.installTarget.manifest)
        } catch let error as UpgradeError {
            throw error
        } catch {
            throw UpgradeError.stageFailed(.packagePreparation)
        }

        var point: UpgradeRollbackPoint?
        var transactionID: UUID?
        var stopAttempted = false
        let report: UpgradeReport
        do {
            currentStage = .baselineCapture
            let baseline = try await baselineCapture.capture()
            try validate(baseline)
            let initialWork = try await workloads.activeWork()
            guard initialWork.isEmpty else { throw UpgradeError.workActive(initialWork.sorted()) }

            let kind = try await lifecycleKind(
                from: baseline.previousTarget.manifest.runtimeVersion,
                to: target,
                consent: downgradeConsent
            )
            transactionID = try await journal.begin(kind: kind, targetVersion: target.version)

            currentStage = .previousPackageVerification
            let previous = try await previousPackageVerifier.verify(baseline)
            try validate(previous, against: baseline.previousTarget.manifest)

            currentStage = .rollbackPointCreation
            point = try await rollback.createPoint(
                from: baseline,
                verifiedPrevious: previous,
                requiresFullData: target.requiresFullDataRollback
            )
            guard let transactionID, let point else { throw UpgradeError.journalUnavailable }
            try await journal.recordRollbackPoint(transactionID: transactionID, pointID: point.id)

            currentStage = .finalIdleCheck
            let finalWork = try await workloads.activeWork()
            guard finalWork.isEmpty else {
                throw UpgradeError.workBecameActive(finalWork.sorted())
            }

            currentStage = .serviceStop
            stopAttempted = true
            try await services.stopRuntime()

            currentStage = .targetInstall
            try await journal.recordInstallIntent(
                transactionID: transactionID,
                digest: prepared.package.sha256
            )
            try await helper.install(prepared.package)
            try await journal.recordInstallApplied(
                transactionID: transactionID,
                digest: prepared.package.sha256
            )

            currentStage = .serviceStart
            try await services.startRuntime(expectedVersion: target.version)

            currentStage = .targetVerification
            let agreement = try await installedRuntimeVerifier.verify(target: target)
            guard agreement.agrees(with: target.version) else {
                throw UpgradeError.versionAgreementMismatch
            }

            currentStage = .targetProbes
            try await probes.run(probes: target.requiredProbes, runtimeVersion: target.version)

            currentStage = .packageRetention
            let retained = try await packageRetainer.retain(
                prepared.package,
                assetName: target.installTarget.manifest.assetName
            )
            guard retained.runtimeVersion == prepared.package.runtimeVersion,
                  retained.sha256 == prepared.package.sha256
            else {
                throw UpgradeError.packageVerificationMismatch
            }

            currentStage = .journalCommit
            try await journal.commit(transactionID: transactionID)
            report = .init(
                previousRuntimeVersion: baseline.previousTarget.manifest.runtimeVersion,
                runtimeVersion: target.version,
                kind: kind
            )
        } catch {
            try await handleUpgradeFailure(
                error,
                context: .init(
                    target: target,
                    stage: currentStage,
                    prepared: prepared,
                    point: point,
                    transactionID: transactionID,
                    stopAttempted: stopAttempted
                )
            )
        }

        try await cleanupAfterUpgrade(point: point, prepared: prepared)
        return report
    }

    private func handleUpgradeFailure(
        _ error: Error,
        context: UpgradeFailureContext
    ) async throws -> Never {
        let failure = RedactedLifecycleFailure(
            code: "upgrade.\(context.stage.rawValue)",
            redactedDetail: "stage-failed"
        )
        if context.stopAttempted {
            if let point = context.point, let transactionID = context.transactionID {
                let rollbackError = await rollBack(
                    target: context.target,
                    point: point,
                    transactionID: transactionID,
                    failure: failure
                )
                try? context.prepared.cleanup()
                throw rollbackError
            }
        }
        if let point = context.point {
            try? await rollback.discard(point)
        }
        if let transactionID = context.transactionID {
            try? await journal.fail(transactionID: transactionID, failure: failure)
        }
        try? context.prepared.cleanup()
        if let upgradeError = error as? UpgradeError {
            throw upgradeError
        }
        throw UpgradeError.stageFailed(context.stage)
    }

    private func cleanupAfterUpgrade(
        point: UpgradeRollbackPoint?,
        prepared: PreparedUpgradePackage
    ) async throws {
        do {
            if let point {
                try await rollback.discard(point)
            }
            try prepared.cleanup()
        } catch {
            throw UpgradeError.upgradedButCleanupFailed
        }
    }

    private func rollBack(
        target: RuntimeUpgradeTarget,
        point: UpgradeRollbackPoint,
        transactionID: UUID,
        failure: RedactedLifecycleFailure
    ) async -> UpgradeError {
        try? await journal.beginRollback(transactionID: transactionID, pointID: point.id)
        var stage = RollbackStage.targetStop
        do {
            try await services.stopRuntime()
            stage = .previousPackageReinstall
            let previous = try await rollback.previousPackage(in: point)
            try await helper.install(previous)
            stage = .dataRestore
            try await rollback.restore(point)
            stage = .previousServiceStart
            try await services.startRuntime(expectedVersion: previous.runtimeVersion)
            stage = .previousProbes
            try await probes.run(
                probes: point.previousProbes,
                runtimeVersion: previous.runtimeVersion
            )
            stage = .diagnosticPersist
            try await diagnostics.persist(failure)
            stage = .targetBlock
            try await blocker.block(version: target.version, failureCode: failure.code)
            try await journal.finishRollback(transactionID: transactionID)
            try await rollback.discard(point)
            return .rolledBack
        } catch {
            await preserveRollbackFailure(
                originalStage: stage,
                target: target,
                failure: failure
            )
            return .recoveryRequired(stage)
        }
    }

    private func preserveRollbackFailure(
        originalStage: RollbackStage,
        target: RuntimeUpgradeTarget,
        failure: RedactedLifecycleFailure
    ) async {
        if originalStage != .diagnosticPersist {
            try? await diagnostics.persist(failure)
        }
        if originalStage != .targetBlock {
            try? await blocker.block(version: target.version, failureCode: failure.code)
        }
    }

    private func lifecycleKind(
        from previousVersion: String,
        to target: RuntimeUpgradeTarget,
        consent: any UpgradeDowngradeConsentProviding
    ) async throws -> LifecycleKind {
        let previous = try ParsedRuntimeVersion(previousVersion)
        let next = try ParsedRuntimeVersion(target.version)
        guard previous != next else { throw UpgradeError.sameVersion }
        guard next < previous else { return .upgrade }
        let approved = try await consent.approve(.init(
            fromVersion: previousVersion,
            toVersion: target.version,
            destroysStorageCompatibility: target.destroysStorageCompatibility
        ))
        guard approved else { throw UpgradeError.downgradeConsentRequired }
        return .downgrade
    }

    private func validate(_ target: RuntimeUpgradeTarget) throws {
        do {
            try target.installTarget.manifest.validate()
        } catch {
            throw UpgradeError.invalidTarget
        }
        guard
            !target.requiredProbes.isEmpty,
            Set(target.requiredProbes).count == target.requiredProbes.count
        else {
            throw UpgradeError.invalidTarget
        }
    }

    private func validate(_ baseline: UpgradeBaseline) throws {
        do {
            try baseline.previousTarget.manifest.validate()
        } catch {
            throw UpgradeError.invalidBaseline
        }
        guard
            baseline.previousPackageURL.isFileURL,
            !baseline.configurationAndMetadata.isEmpty
        else {
            throw UpgradeError.invalidBaseline
        }
    }

    private func validate(
        _ package: VerifiedRuntimePackage,
        against manifest: RuntimePackageManifest
    ) throws {
        guard
            package.runtimeVersion == manifest.runtimeVersion,
            package.sha256 == manifest.sha256,
            package.installerTeamID == manifest.installerTeamID,
            package.signerCommonName == manifest.signerCommonName,
            package.receiptIdentifier == manifest.receiptIdentifier,
            package.installLocation == manifest.installLocation,
            package.payload == manifest.payload
        else {
            throw UpgradeError.packageVerificationMismatch
        }
        try package.openFile.revalidateIdentity()
    }
}

public enum UpgradeError: Error, Equatable, Sendable {
    case downgradeConsentRequired
    case invalidBaseline
    case invalidTarget
    case journalUnavailable
    case packageVerificationMismatch
    case recoveryRequired(RollbackStage)
    case rolledBack
    case sameVersion
    case stageFailed(UpgradeStage)
    case upgradedButCleanupFailed
    case versionAgreementMismatch
    case workActive([String])
    case workBecameActive([String])
}

private struct ParsedRuntimeVersion: Comparable {
    let components: [Int]

    init(_ value: String) throws {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard
            parts.count == 3,
            parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
            parts.compactMap({ Int($0) }).count == 3
        else {
            throw UpgradeError.invalidTarget
        }
        components = parts.compactMap { Int($0) }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

private struct UpgradeFailureContext: Sendable {
    let target: RuntimeUpgradeTarget
    let stage: UpgradeStage
    let prepared: PreparedUpgradePackage
    let point: UpgradeRollbackPoint?
    let transactionID: UUID?
    let stopAttempted: Bool
}

extension RollbackStore: UpgradeRollbackManaging {
    public func createPoint(
        from baseline: UpgradeBaseline,
        verifiedPrevious: VerifiedRuntimePackage,
        requiresFullData: Bool
    ) async throws -> UpgradeRollbackPoint {
        let request = RollbackCaptureRequest(
            previousPackageURL: baseline.previousPackageURL,
            previousManifest: baseline.previousTarget.manifest,
            configurationAndMetadata: baseline.configurationAndMetadata,
            fullData: baseline.fullData,
            requiresFullData: requiresFullData
        )
        let point = try await createPoint(request, verifiedPrevious: verifiedPrevious)
        upgradePoints[point.id] = point
        return .init(id: point.id, previousProbes: baseline.previousTarget.requiredProbes)
    }

    public func previousPackage(in point: UpgradeRollbackPoint) async throws -> VerifiedRuntimePackage {
        guard let stored = upgradePoints[point.id] else { throw RollbackStoreError.unsafePoint }
        return try await openPreviousPackage(in: stored)
    }

    public func restore(_ point: UpgradeRollbackPoint) async throws {
        guard let stored = upgradePoints[point.id] else { throw RollbackStoreError.unsafePoint }
        try restore(stored)
    }

    public func discard(_ point: UpgradeRollbackPoint) async throws {
        guard let stored = upgradePoints.removeValue(forKey: point.id) else {
            throw RollbackStoreError.unsafePoint
        }
        try discard(stored)
    }
}
