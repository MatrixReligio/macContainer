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
        self.rollbackAvailability = rollbackAvailability
        self.probeRegistry = probeRegistry
        self.executor = executor
        self.blocker = blocker
        self.stateSink = stateSink
        self.decisionEngine = decisionEngine
        self.updatePolicy = updatePolicy
    }

    public func process(_ candidate: RuntimeReleaseCandidate) async throws -> RuntimeUpdateState {
        await stateSink.publish(.checking)
        try Task.checkCancellation()

        let context = try await contextProvider.context(for: candidate)
        guard let catalog = context.catalog,
              (try? catalog.validated()) != nil
        else {
            return await finish(.held(.catalogInvalid))
        }
        guard let entry = catalog.entry(runtimeVersion: candidate.version) else {
            return await finish(.held(.unknownRuntime))
        }

        let candidatePackage = RuntimePackageIdentity(
            runtimeVersion: candidate.version,
            assetName: candidate.packageURL.lastPathComponent,
            sha256: candidate.packageSHA256,
            installerTeamID: entry.package.installerTeamID,
            signerCommonName: entry.package.signerCommonName,
            receiptIdentifier: entry.package.receiptIdentifier
        )
        let decision = decisionEngine.decide(.init(
            catalog: catalog,
            targetRuntimeVersion: candidate.version,
            appVersion: context.appVersion,
            host: context.host,
            package: candidatePackage,
            installedRuntimeVersion: context.installedRuntimeVersion,
            installedPackageSHA256: context.installedPackageSHA256,
            verifiedAttestationIDs: context.verifiedAttestationIDs,
            blockedAttestationID: context.blockedAttestationID,
            destructiveMigrationConsent: context.destructiveMigrationConsent
        ))
        guard case let .allow(reviewedEntry) = decision else {
            guard case let .hold(reason) = decision else {
                return await finish(.held(.catalogInvalid))
            }
            return await finish(.held(reason))
        }

        await stateSink.publish(.available(version: candidate.version))
        await stateSink.publish(.downloading(version: candidate.version))
        let target: RuntimeUpgradeTarget
        do {
            target = try await packageVerifier.verify(candidate: candidate, entry: reviewedEntry)
            guard targetMatchesEntry(target, entry: reviewedEntry) else {
                return await finish(.held(.packageIdentityMismatch))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return await finish(.held(.packageIdentityMismatch))
        }

        let initialAction = updatePolicy.action(for: .init(
            mode: context.mode,
            compatibilityDecision: decision,
            consentVersion: context.consentVersion,
            helperAuthorized: context.helperAuthorized,
            activity: context.activity
        ))
        switch initialAction {
        case .notify, .downloadThenNotify:
            return await finish(.available(version: candidate.version))
        case let .pending(reason):
            return await finish(.pending(reason))
        case let .held(reason):
            return await finish(.held(reason))
        case .install:
            break
        }

        do {
            try await rollbackAvailability.check(target: target)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return await finish(.held(.rollbackUnavailable))
        }

        let report = await probeRegistry.runAll(context: .init(
            bridge: context.bridge,
            expectedRuntimeVersion: candidate.version,
            expectedCapabilityIDs: reviewedEntry.capabilityIDs,
            enabledCapabilityIDs: context.enabledCapabilityIDs,
            phase: .preflight
        ))
        guard report.isCompatible else {
            let failedProbeID = report.results.first { result in
                if case .failed = result.outcome { return true }
                return false
            }?.id
            try? await blocker.block(
                entry: reviewedEntry,
                catalogRevision: catalog.revision,
                appVersion: context.appVersion,
                failedProbeID: failedProbeID
            )
            return await finish(.held(.preflightFailed))
        }

        let finalActivity = try await contextProvider.currentActivity()
        let finalAction = updatePolicy.action(for: .init(
            mode: context.mode,
            compatibilityDecision: decision,
            consentVersion: context.consentVersion,
            helperAuthorized: context.helperAuthorized,
            activity: finalActivity
        ))
        switch finalAction {
        case .install:
            break
        case let .pending(reason):
            return await finish(.pending(reason))
        case let .held(reason):
            return await finish(.held(reason))
        case .notify, .downloadThenNotify:
            return await finish(.available(version: candidate.version))
        }

        try Task.checkCancellation()
        await stateSink.publish(.installing(.packagePreparation))
        do {
            _ = try await executor.upgrade(to: target)
            return await finish(.upToDate)
        } catch is CancellationError {
            throw CancellationError()
        } catch UpgradeError.workActive, UpgradeError.workBecameActive {
            return await finish(.pending(.workActive))
        } catch UpgradeError.rolledBack {
            try? await blocker.block(
                entry: reviewedEntry,
                catalogRevision: catalog.revision,
                appVersion: context.appVersion,
                failedProbeID: nil
            )
            return await finish(.rolledBack(
                previousVersion: context.installedRuntimeVersion,
                failedProbeID: nil
            ))
        } catch let UpgradeError.recoveryRequired(stage) {
            try? await blocker.block(
                entry: reviewedEntry,
                catalogRevision: catalog.revision,
                appVersion: context.appVersion,
                failedProbeID: nil
            )
            return await finish(.recoveryRequired(code: stage.rawValue))
        } catch {
            return await finish(.recoveryRequired(code: "automatic-update-failed"))
        }
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
