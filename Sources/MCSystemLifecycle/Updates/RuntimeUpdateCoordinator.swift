import Foundation
import MCCompatibility
import MCContainerBridge
import MCModel

public struct AutomaticUpdateContext: Sendable {
    public let catalog: CompatibilityCatalog?
    public let appVersion: String
    public let host: HostProfile
    public let installedRuntimeVersion: String
    public let installedPackageSHA256: String
    public let verifiedAttestationIDs: Set<String>
    public let blockedAttestationID: String?
    public let destructiveMigrationConsent: Bool
    public let mode: RuntimeUpdateMode
    public let consentVersion: Int?
    public let helperAuthorized: Bool
    public let activity: RuntimeActivitySnapshot
    public let bridge: any RuntimeBridge
    public let enabledCapabilityIDs: Set<String>

    public init(
        catalog: CompatibilityCatalog?,
        appVersion: String,
        host: HostProfile,
        installedRuntimeVersion: String,
        installedPackageSHA256: String,
        verifiedAttestationIDs: Set<String>,
        blockedAttestationID: String?,
        destructiveMigrationConsent: Bool,
        mode: RuntimeUpdateMode,
        consentVersion: Int?,
        helperAuthorized: Bool,
        activity: RuntimeActivitySnapshot,
        bridge: any RuntimeBridge,
        enabledCapabilityIDs: Set<String>
    ) {
        self.catalog = catalog
        self.appVersion = appVersion
        self.host = host
        self.installedRuntimeVersion = installedRuntimeVersion
        self.installedPackageSHA256 = installedPackageSHA256
        self.verifiedAttestationIDs = verifiedAttestationIDs
        self.blockedAttestationID = blockedAttestationID
        self.destructiveMigrationConsent = destructiveMigrationConsent
        self.mode = mode
        self.consentVersion = consentVersion
        self.helperAuthorized = helperAuthorized
        self.activity = activity
        self.bridge = bridge
        self.enabledCapabilityIDs = enabledCapabilityIDs
    }
}

public protocol AutomaticUpdateContextProviding: Sendable {
    func context(for candidate: RuntimeReleaseCandidate) async throws -> AutomaticUpdateContext
    func currentActivity() async throws -> RuntimeActivitySnapshot
}

public protocol AutomaticUpdatePackageVerifying: Sendable {
    func verify(
        candidate: RuntimeReleaseCandidate,
        entry: CompatibilityEntry
    ) async throws -> RuntimeUpgradeTarget
}

public protocol AutomaticUpdatePackageCaching: Sendable {
    func cache(_ target: RuntimeUpgradeTarget) async throws -> RetainedRuntimePackage
}

public protocol AutomaticRollbackAvailabilityChecking: Sendable {
    func check(target: RuntimeUpgradeTarget) async throws
}

public protocol AutomaticUpgradeExecuting: Sendable {
    func upgrade(to target: RuntimeUpgradeTarget) async throws -> UpgradeReport
}

public protocol AutomaticUpdateBlocking: Sendable {
    func block(
        entry: CompatibilityEntry,
        catalogRevision: String,
        appVersion: String,
        failedProbeID: ProbeID?
    ) async throws
}

public protocol RuntimeUpdateStateSink: Sendable {
    func publish(_ state: RuntimeUpdateState) async
}

public actor RuntimeUpdateCoordinator: RuntimeUpdateCoordinating {
    private let contextProvider: any AutomaticUpdateContextProviding
    private let packageVerifier: any AutomaticUpdatePackageVerifying
    private let packageCache: any AutomaticUpdatePackageCaching
    private let rollbackAvailability: any AutomaticRollbackAvailabilityChecking
    private let probeRegistry: ProbeRegistry
    private let executor: any AutomaticUpgradeExecuting
    private let blocker: any AutomaticUpdateBlocking
    private let stateSink: any RuntimeUpdateStateSink
    private let decisionEngine: CompatibilityDecisionEngine
    private let updatePolicy: RuntimeUpdatePolicy

    public init(
        contextProvider: any AutomaticUpdateContextProviding,
        packageVerifier: any AutomaticUpdatePackageVerifying,
        packageCache: any AutomaticUpdatePackageCaching,
        rollbackAvailability: any AutomaticRollbackAvailabilityChecking,
        probeRegistry: ProbeRegistry = ProbeRegistry(),
        executor: any AutomaticUpgradeExecuting,
        blocker: any AutomaticUpdateBlocking,
        stateSink: any RuntimeUpdateStateSink,
        decisionEngine: CompatibilityDecisionEngine = CompatibilityDecisionEngine(),
        updatePolicy: RuntimeUpdatePolicy = RuntimeUpdatePolicy()
    ) {
        self.contextProvider = contextProvider
        self.packageVerifier = packageVerifier
        self.packageCache = packageCache
        self.rollbackAvailability = rollbackAvailability
        self.probeRegistry = probeRegistry
        self.executor = executor
        self.blocker = blocker
        self.stateSink = stateSink
        self.decisionEngine = decisionEngine
        self.updatePolicy = updatePolicy
    }

    // The coordinator intentionally makes every fail-closed gate visible in one ordered state machine.
    // swiftlint:disable:next cyclomatic_complexity
    public func process(_ candidate: RuntimeReleaseCandidate) async throws -> RuntimeUpdateState {
        await stateSink.publish(.checking)
        try Task.checkCancellation()

        let reviewed: ReviewedAutomaticUpdate
        switch try await review(candidate) {
        case let .proceed(value):
            reviewed = value
        case let .stop(state):
            return await finish(state)
        }

        await stateSink.publish(.available(version: candidate.version))
        switch updateAction(reviewed: reviewed, activity: reviewed.context.activity) {
        case .notify:
            return .available(version: candidate.version)
        case let .pending(reason):
            return await finish(.pending(reason))
        case let .held(reason):
            return await finish(.held(reason))
        case .downloadThenNotify, .install:
            break
        }
        await stateSink.publish(.downloading(version: candidate.version))
        let target: RuntimeUpgradeTarget
        switch try await prepare(candidate, reviewed: reviewed) {
        case let .proceed(value):
            target = value
        case let .stop(state):
            return await finish(state)
        }

        if reviewed.context.mode == .downloadAndNotify {
            do {
                let retained = try await packageCache.cache(target)
                guard retained.runtimeVersion == target.version,
                      retained.sha256 == target.installTarget.manifest.sha256
                else {
                    return await finish(.held(.packageIdentityMismatch))
                }
                return await finish(.available(version: candidate.version))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return await finish(.held(.packageIdentityMismatch))
            }
        }

        if let state = policyState(
            reviewed: reviewed,
            activity: reviewed.context.activity,
            candidateVersion: candidate.version
        ) {
            return await finish(state)
        }

        if let state = try await preflight(reviewed: reviewed, target: target) {
            return await finish(state)
        }

        let finalActivity = try await contextProvider.currentActivity()
        if let state = policyState(
            reviewed: reviewed,
            activity: finalActivity,
            candidateVersion: candidate.version
        ) {
            return await finish(state)
        }

        try Task.checkCancellation()
        await stateSink.publish(.installing(.packagePreparation))
        return try await execute(target: target, reviewed: reviewed)
    }

    private func review(
        _ candidate: RuntimeReleaseCandidate
    ) async throws -> AutomaticCoordinatorGate<ReviewedAutomaticUpdate> {
        let context = try await contextProvider.context(for: candidate)
        guard let catalog = context.catalog, (try? catalog.validated()) != nil else {
            return .stop(.held(.catalogInvalid))
        }
        guard let entry = catalog.entry(runtimeVersion: candidate.version) else {
            return .stop(.held(.unknownRuntime))
        }
        let decision = decisionEngine.decide(.init(
            catalog: catalog,
            targetRuntimeVersion: candidate.version,
            appVersion: context.appVersion,
            host: context.host,
            package: candidatePackage(candidate, entry: entry),
            installedRuntimeVersion: context.installedRuntimeVersion,
            installedPackageSHA256: context.installedPackageSHA256,
            verifiedAttestationIDs: context.verifiedAttestationIDs,
            blockedAttestationID: context.blockedAttestationID,
            destructiveMigrationConsent: context.destructiveMigrationConsent
        ))
        guard case let .allow(reviewedEntry) = decision else {
            guard case let .hold(reason) = decision else { return .stop(.held(.catalogInvalid)) }
            return .stop(.held(reason))
        }
        return .proceed(.init(
            context: context,
            catalog: catalog,
            entry: reviewedEntry,
            decision: decision
        ))
    }

    private func prepare(
        _ candidate: RuntimeReleaseCandidate,
        reviewed: ReviewedAutomaticUpdate
    ) async throws -> AutomaticCoordinatorGate<RuntimeUpgradeTarget> {
        do {
            let target = try await packageVerifier.verify(candidate: candidate, entry: reviewed.entry)
            guard targetMatchesEntry(target, entry: reviewed.entry) else {
                return .stop(.held(.packageIdentityMismatch))
            }
            return .proceed(target)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .stop(.held(.packageIdentityMismatch))
        }
    }

    private func preflight(
        reviewed: ReviewedAutomaticUpdate,
        target: RuntimeUpgradeTarget
    ) async throws -> RuntimeUpdateState? {
        do {
            try await rollbackAvailability.check(target: target)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .held(.rollbackUnavailable)
        }
        let report = await probeRegistry.runAll(context: .init(
            bridge: reviewed.context.bridge,
            expectedRuntimeVersion: reviewed.context.installedRuntimeVersion,
            expectedCapabilityIDs: reviewed.entry.capabilityIDs,
            enabledCapabilityIDs: reviewed.context.enabledCapabilityIDs,
            phase: .preflight
        ))
        guard report.isCompatible else {
            let failedProbeID = report.results.first { result in
                if case .failed = result.outcome {
                    return true
                }
                return false
            }?.id
            try? await blocker.block(
                entry: reviewed.entry,
                catalogRevision: reviewed.catalog.revision,
                appVersion: reviewed.context.appVersion,
                failedProbeID: failedProbeID
            )
            return .held(.preflightFailed)
        }
        return nil
    }

    private func policyState(
        reviewed: ReviewedAutomaticUpdate,
        activity: RuntimeActivitySnapshot,
        candidateVersion: String
    ) -> RuntimeUpdateState? {
        let action = updateAction(reviewed: reviewed, activity: activity)
        switch action {
        case .install: return nil
        case .notify, .downloadThenNotify: return .available(version: candidateVersion)
        case let .pending(reason): return .pending(reason)
        case let .held(reason): return .held(reason)
        }
    }

    private func updateAction(
        reviewed: ReviewedAutomaticUpdate,
        activity: RuntimeActivitySnapshot
    ) -> RuntimeUpdateAction {
        updatePolicy.action(for: .init(
            mode: reviewed.context.mode,
            compatibilityDecision: reviewed.decision,
            consentVersion: reviewed.context.consentVersion,
            helperAuthorized: reviewed.context.helperAuthorized,
            activity: activity
        ))
    }

    private func execute(
        target: RuntimeUpgradeTarget,
        reviewed: ReviewedAutomaticUpdate
    ) async throws -> RuntimeUpdateState {
        do {
            _ = try await executor.upgrade(to: target)
            return await finish(.upToDate)
        } catch is CancellationError {
            throw CancellationError()
        } catch UpgradeError.workActive, UpgradeError.workBecameActive {
            return await finish(.pending(.workActive))
        } catch UpgradeError.rolledBack {
            await block(reviewed)
            return await finish(.rolledBack(
                previousVersion: reviewed.context.installedRuntimeVersion,
                failedProbeID: nil
            ))
        } catch let UpgradeError.recoveryRequired(stage) {
            await block(reviewed)
            return await finish(.recoveryRequired(code: stage.rawValue))
        } catch {
            return await finish(.recoveryRequired(code: "automatic-update-failed"))
        }
    }

    private func block(_ reviewed: ReviewedAutomaticUpdate) async {
        try? await blocker.block(
            entry: reviewed.entry,
            catalogRevision: reviewed.catalog.revision,
            appVersion: reviewed.context.appVersion,
            failedProbeID: nil
        )
    }

    private func candidatePackage(
        _ candidate: RuntimeReleaseCandidate,
        entry: CompatibilityEntry
    ) -> RuntimePackageIdentity {
        .init(
            runtimeVersion: candidate.version,
            assetName: candidate.packageURL.lastPathComponent,
            sha256: candidate.packageSHA256,
            installerTeamID: entry.package.installerTeamID,
            signerCommonName: entry.package.signerCommonName,
            receiptIdentifier: entry.package.receiptIdentifier
        )
    }

    private func targetMatchesEntry(
        _ target: RuntimeUpgradeTarget,
        entry: CompatibilityEntry
    ) -> Bool {
        let manifest = target.installTarget.manifest
        return manifest.runtimeVersion == entry.runtimeVersion &&
            manifest.assetName == entry.package.assetName &&
            manifest.sha256 == entry.package.sha256 &&
            manifest.installerTeamID == entry.package.installerTeamID &&
            manifest.signerCommonName == entry.package.signerCommonName &&
            manifest.receiptIdentifier == entry.package.receiptIdentifier &&
            target.requiredProbes == entry.requiredProbeIDs &&
            target.requiresFullDataRollback == (entry.rollback == .fullDataClone) &&
            target.destroysStorageCompatibility == (entry.storageMigration == .destructive)
    }

    private func finish(_ state: RuntimeUpdateState) async -> RuntimeUpdateState {
        await stateSink.publish(state)
        return state
    }
}

private enum AutomaticCoordinatorGate<Value: Sendable>: Sendable {
    case proceed(Value)
    case stop(RuntimeUpdateState)
}

private struct ReviewedAutomaticUpdate: Sendable {
    let context: AutomaticUpdateContext
    let catalog: CompatibilityCatalog
    let entry: CompatibilityEntry
    let decision: CompatibilityDecision
}

extension UpgradeTransaction: AutomaticUpgradeExecuting {}

public struct BlockedVersionUpdateRecorder: AutomaticUpdateBlocking {
    private let store: BlockedVersionStore
    private let now: @Sendable () -> Date

    public init(store: BlockedVersionStore, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    public func block(
        entry: CompatibilityEntry,
        catalogRevision: String,
        appVersion: String,
        failedProbeID: ProbeID?
    ) async throws {
        try await store.record(.init(
            runtimeVersion: entry.runtimeVersion,
            appVersion: appVersion,
            catalogRevision: catalogRevision,
            attestationID: entry.attestation.id,
            failedProbeID: failedProbeID,
            timestamp: now()
        ))
    }
}
