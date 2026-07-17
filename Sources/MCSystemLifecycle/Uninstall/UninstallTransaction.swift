import CryptoKit
import Foundation

public enum UninstallStage: String, CaseIterable, Codable, Sendable {
    case inventoryRefresh = "uninstall.inventory.refresh"
    case confirmation = "uninstall.confirmation"
    case serviceStop = "uninstall.service.stop"
    case processVerification = "uninstall.process.verify"
    case credentialRemoval = "uninstall.credential.remove"
    case networkRemoval = "uninstall.network.remove"
    case payloadRemoval = "uninstall.payload.remove"
    case receiptRemoval = "uninstall.receipt.remove"
    case userArtifactRemoval = "uninstall.user-artifacts.remove"
    case emptyDirectoryRemoval = "uninstall.empty-directories.remove"
    case residueAudit = "uninstall.residue.audit"
}

public enum UninstallMode: String, Codable, Equatable, Sendable {
    case complete
    case preserveData
}

public enum UninstallCompletion: String, Codable, Equatable, Sendable {
    case complete
    case dataPreserved
}

public struct RuntimeUninstallTarget: Equatable, Sendable {
    public let manifest: RuntimePackageManifest
    public let manifestID: String
    public let manifestSHA256: String
    public let packetFilterAnchor: String

    public init(
        manifest: RuntimePackageManifest,
        manifestID: String,
        manifestSHA256: String,
        packetFilterAnchor: String
    ) {
        self.manifest = manifest
        self.manifestID = manifestID
        self.manifestSHA256 = manifestSHA256
        self.packetFilterAnchor = packetFilterAnchor
    }

    public static let reviewedRuntime110 = Self(
        manifest: ReviewedRuntime110Manifest.package,
        manifestID: ReviewedRuntime110Manifest.identifier,
        manifestSHA256: ReviewedRuntime110Manifest.sourceSHA256,
        packetFilterAnchor: "com.apple.container"
    )

    public static let reviewedRuntime100 = Self(
        manifest: ReviewedRuntime100Manifest.package,
        manifestID: ReviewedRuntime100Manifest.identifier,
        manifestSHA256: ReviewedRuntime100Manifest.sourceSHA256,
        packetFilterAnchor: "com.apple.container"
    )
}

public struct UninstallInventory: Equatable, Sendable {
    public let runtimeVersion: String
    public let activeWork: [String]
    public let serviceLabels: [String]
    public let resolverNames: [String]
    public let artifactKinds: Set<ResidueKind>
    public let estimatedBytes: UInt64
    public let mode: UninstallMode

    public var fingerprint: String {
        let fields = [
            runtimeVersion,
            activeWork.sorted().joined(separator: "\u{1F}"),
            serviceLabels.sorted().joined(separator: "\u{1F}"),
            resolverNames.sorted().joined(separator: "\u{1F}"),
            artifactKinds.map(\.rawValue).sorted().joined(separator: "\u{1F}"),
            String(estimatedBytes),
            mode.rawValue
        ]
        let digest = SHA256.hash(data: Data(fields.joined(separator: "\u{1E}").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public init(
        runtimeVersion: String,
        activeWork: [String],
        serviceLabels: [String],
        resolverNames: [String],
        artifactKinds: Set<ResidueKind>,
        estimatedBytes: UInt64,
        mode: UninstallMode
    ) {
        self.runtimeVersion = runtimeVersion
        self.activeWork = activeWork
        self.serviceLabels = serviceLabels
        self.resolverNames = resolverNames
        self.artifactKinds = artifactKinds
        self.estimatedBytes = estimatedBytes
        self.mode = mode
    }
}

public struct CompleteUninstallConfirmation: Equatable, Sendable {
    public let mode: UninstallMode
    public let inventoryFingerprint: String
    public let acknowledgesIrreversibleDeletion: Bool

    public init(
        mode: UninstallMode,
        inventoryFingerprint: String,
        acknowledgesIrreversibleDeletion: Bool
    ) {
        self.mode = mode
        self.inventoryFingerprint = inventoryFingerprint
        self.acknowledgesIrreversibleDeletion = acknowledgesIrreversibleDeletion
    }
}

public struct UninstallResult: Equatable, Sendable {
    public let completion: UninstallCompletion
    public let audit: ResidueReport
    public let preservedKinds: [ResidueKind]

    public init(
        completion: UninstallCompletion,
        audit: ResidueReport,
        preservedKinds: [ResidueKind]
    ) {
        self.completion = completion
        self.audit = audit
        self.preservedKinds = preservedKinds
    }
}

public protocol UninstallInventoryRefreshing: Sendable {
    func refresh(mode: UninstallMode) async throws -> UninstallInventory
}

public protocol UninstallConfirmationChecking: Sendable {
    func approve(
        inventory: UninstallInventory,
        confirmation: CompleteUninstallConfirmation
    ) async throws -> Bool
}

public protocol UninstallServiceStopping: Sendable {
    func stopAll(activeWork: [String], serviceLabels: [String]) async throws
}

public protocol UninstallProcessVerifying: Sendable {
    func verifyNoOwnedProcess() async throws
}

public protocol UninstallCredentialRemoving: Sendable {
    func removeAll() async throws
}

public protocol UninstallPrivilegedHelping: Sendable {
    func removeResolver(name: String) async throws
    func removePacketFilter(anchor: String) async throws
    func removePayload(manifestID: String, manifestSHA256: String) async throws
    func forgetReceipt(identifier: String) async throws
    func removeKnownEmptyDirectories(manifestID: String) async throws
}

public protocol UninstallUserArtifactRemoving: Sendable {
    func remove(_ kind: ResidueKind) async throws
}

public protocol UninstallJournalWriting: Sendable {
    func begin(mode: UninstallMode) async throws -> UUID
    func recordIntent(transactionID: UUID, action: LifecycleAction) async throws
    func recordApplied(transactionID: UUID, action: LifecycleAction) async throws
    func commit(transactionID: UUID) async throws
    func fail(transactionID: UUID, failure: RedactedLifecycleFailure) async throws
}

public final class LifecycleOperationLock: @unchecked Sendable {
    private let lock = NSLock()
    private var active = false

    public init() {}

    public func acquire() throws -> LifecycleOperationLease {
        try lock.withLock {
            guard !active else { throw UninstallError.lifecycleBusy }
            active = true
            return LifecycleOperationLease { [weak self] in
                self?.lock.withLock { self?.active = false }
            }
        }
    }
}

public final class LifecycleOperationLease: @unchecked Sendable {
    private let lock = NSLock()
    private var releaseAction: (@Sendable () -> Void)?

    fileprivate init(release: @escaping @Sendable () -> Void) {
        releaseAction = release
    }

    deinit {
        release()
    }

    public func release() {
        lock.withLock {
            let action = releaseAction
            releaseAction = nil
            action?()
        }
    }
}

public struct LifecycleUninstallJournalWriter: UninstallJournalWriting {
    private let journal: LifecycleJournal

    public init(journal: LifecycleJournal) {
        self.journal = journal
    }

    public func begin(mode _: UninstallMode) async throws -> UUID {
        try await journal.begin(kind: .uninstall, targetVersion: nil)
    }

    public func recordIntent(transactionID: UUID, action: LifecycleAction) async throws {
        try await journal.recordIntent(action, transactionID: transactionID)
    }

    public func recordApplied(transactionID: UUID, action: LifecycleAction) async throws {
        try await journal.recordApplied(action, transactionID: transactionID)
    }

    public func commit(transactionID: UUID) async throws {
        try await journal.recordVerified(transactionID: transactionID)
        try await journal.commit(transactionID: transactionID)
    }

    public func fail(transactionID: UUID, failure: RedactedLifecycleFailure) async throws {
        try await journal.recordFailure(failure, transactionID: transactionID)
    }
}

extension HelperClient: UninstallPrivilegedHelping {
    public func removeResolver(name: String) async throws {
        _ = try await perform(.removeResolver(name: name))
    }

    public func removePacketFilter(anchor: String) async throws {
        _ = try await perform(.removePacketFilter(anchor: anchor))
    }

    public func removePayload(manifestID: String, manifestSHA256: String) async throws {
        _ = try await perform(.removePayload(.init(
            manifestID: manifestID,
            manifestSHA256: manifestSHA256
        )))
    }

    public func forgetReceipt(identifier: String) async throws {
        _ = try await perform(.forgetReceipt(identifier: identifier))
    }

    public func removeKnownEmptyDirectories(manifestID: String) async throws {
        _ = try await perform(.removeKnownEmptyDirectories(manifestID: manifestID))
    }
}

public struct UninstallTransaction: Sendable {
    private static let preservedDataKinds: Set<ResidueKind> = [
        .applicationSupport, .configuration, .defaultsDomain, .registryCredential
    ]
    private static let removableUserKinds: Set<ResidueKind> = [
        .applicationSupport, .configuration, .defaultsDomain, .downloadedPackage,
        .rollbackPoint, .testFixture, .downloadCache
    ]

    private let target: RuntimeUninstallTarget
    private let operationLock: LifecycleOperationLock
    private let inventory: any UninstallInventoryRefreshing
    private let confirmation: any UninstallConfirmationChecking
    private let services: any UninstallServiceStopping
    private let processes: any UninstallProcessVerifying
    private let credentials: any UninstallCredentialRemoving
    private let helper: any UninstallPrivilegedHelping
    private let userArtifacts: any UninstallUserArtifactRemoving
    private let auditor: any ResidueAuditing
    private let journal: any UninstallJournalWriting

    public init(
        target: RuntimeUninstallTarget,
        operationLock: LifecycleOperationLock,
        inventory: any UninstallInventoryRefreshing,
        confirmation: any UninstallConfirmationChecking,
        services: any UninstallServiceStopping,
        processes: any UninstallProcessVerifying,
        credentials: any UninstallCredentialRemoving,
        helper: any UninstallPrivilegedHelping,
        userArtifacts: any UninstallUserArtifactRemoving,
        auditor: any ResidueAuditing,
        journal: any UninstallJournalWriting
    ) {
        self.target = target
        self.operationLock = operationLock
        self.inventory = inventory
        self.confirmation = confirmation
        self.services = services
        self.processes = processes
        self.credentials = credentials
        self.helper = helper
        self.userArtifacts = userArtifacts
        self.auditor = auditor
        self.journal = journal
    }

    public func completelyUninstall(
        confirmation: CompleteUninstallConfirmation
    ) async throws -> UninstallResult {
        guard confirmation.mode == .complete else { throw UninstallError.invalidMode }
        return try await uninstall(mode: .complete, confirmation: confirmation)
    }

    public func removeRuntimePreservingData(
        confirmation: CompleteUninstallConfirmation
    ) async throws -> UninstallResult {
        guard confirmation.mode == .preserveData else { throw UninstallError.invalidMode }
        return try await uninstall(mode: .preserveData, confirmation: confirmation)
    }

    private func uninstall(
        mode: UninstallMode,
        confirmation suppliedConfirmation: CompleteUninstallConfirmation
    ) async throws -> UninstallResult {
        let lease = try operationLock.acquire()
        defer { lease.release() }
        var stage = UninstallStage.inventoryRefresh
        var transactionID: UUID?
        do {
            let currentInventory = try await inventory.refresh(mode: mode)
            try validate(target: target, inventory: currentInventory)

            stage = .confirmation
            guard
                suppliedConfirmation.inventoryFingerprint == currentInventory.fingerprint,
                suppliedConfirmation.mode == mode
            else {
                throw UninstallError.staleConfirmation
            }
            if mode == .complete, !suppliedConfirmation.acknowledgesIrreversibleDeletion {
                throw UninstallError.irreversibleDeletionNotAcknowledged
            }
            guard try await confirmation.approve(
                inventory: currentInventory,
                confirmation: suppliedConfirmation
            ) else {
                throw UninstallError.confirmationDenied
            }
            transactionID = try await journal.begin(mode: mode)
            guard let transactionID else { throw UninstallError.journalUnavailable }

            stage = .serviceStop
            try await apply(
                .stopServices(labels: currentInventory.serviceLabels),
                transactionID: transactionID
            ) {
                try await services.stopAll(
                    activeWork: currentInventory.activeWork,
                    serviceLabels: currentInventory.serviceLabels
                )
            }

            stage = .processVerification
            try await processes.verifyNoOwnedProcess()

            stage = .credentialRemoval
            if mode == .complete {
                try await apply(.removeUserArtifact(kind: .registryCredential), transactionID: transactionID) {
                    try await credentials.removeAll()
                }
            }

            stage = .networkRemoval
            try await removeNetwork(
                resolverNames: currentInventory.resolverNames,
                transactionID: transactionID
            )

            stage = .payloadRemoval
            try await apply(
                .removePayload(manifestID: target.manifestID),
                transactionID: transactionID
            ) {
                try await helper.removePayload(
                    manifestID: target.manifestID,
                    manifestSHA256: target.manifestSHA256
                )
            }

            stage = .receiptRemoval
            try await apply(
                .removeReceipt(identifier: target.manifest.receiptIdentifier),
                transactionID: transactionID
            ) {
                try await helper.forgetReceipt(identifier: target.manifest.receiptIdentifier)
            }

            stage = .userArtifactRemoval
            try await removeUserArtifacts(mode: mode, transactionID: transactionID)

            stage = .emptyDirectoryRemoval
            try await apply(
                .removeUserArtifact(kind: .runtimeOwnedDirectory),
                transactionID: transactionID
            ) {
                try await helper.removeKnownEmptyDirectories(manifestID: target.manifestID)
            }

            stage = .residueAudit
            let report = await auditor.audit()
            let result = try result(for: mode, report: report)
            try await journal.commit(transactionID: transactionID)
            return result
        } catch {
            if let transactionID {
                try? await journal.fail(
                    transactionID: transactionID,
                    failure: .init(
                        code: "uninstall.\(stage.rawValue)",
                        redactedDetail: "stage-failed"
                    )
                )
            }
            if let uninstallError = error as? UninstallError {
                throw uninstallError
            }
            throw UninstallError.stageFailed(stage)
        }
    }

    private func removeNetwork(resolverNames: [String], transactionID: UUID) async throws {
        for name in resolverNames.sorted() {
            try await apply(.removeUserArtifact(kind: .resolver), transactionID: transactionID) {
                try await helper.removeResolver(name: name)
            }
        }
        try await apply(.removeUserArtifact(kind: .packetFilter), transactionID: transactionID) {
            try await helper.removePacketFilter(anchor: target.packetFilterAnchor)
        }
    }

    private func removeUserArtifacts(mode: UninstallMode, transactionID: UUID) async throws {
        var kinds = Self.removableUserKinds
        if mode == .preserveData {
            kinds.subtract(Self.preservedDataKinds)
        }
        for kind in kinds.sorted(by: { $0.rawValue < $1.rawValue }) {
            try await apply(.removeUserArtifact(kind: kind), transactionID: transactionID) {
                try await userArtifacts.remove(kind)
            }
        }
    }

    private func apply(
        _ action: LifecycleAction,
        transactionID: UUID,
        operation: () async throws -> Void
    ) async throws {
        try await journal.recordIntent(transactionID: transactionID, action: action)
        try await operation()
        try await journal.recordApplied(transactionID: transactionID, action: action)
    }

    private func result(for mode: UninstallMode, report: ResidueReport) throws -> UninstallResult {
        guard report.hasCompleteInventory else { throw UninstallError.incomplete(report) }
        if mode == .complete {
            guard report.isEmpty else { throw UninstallError.incomplete(report) }
            return .init(completion: .complete, audit: report, preservedKinds: [])
        }
        guard !report.items.contains(where: { $0.status == .unverifiable }) else {
            throw UninstallError.incomplete(report)
        }
        let unexpected = report.remainingItems.filter { !Self.preservedDataKinds.contains($0.kind) }
        guard unexpected.isEmpty else { throw UninstallError.incomplete(report) }
        let preserved = report.remainingItems.map(\.kind).sorted { $0.rawValue < $1.rawValue }
        return .init(completion: .dataPreserved, audit: report, preservedKinds: preserved)
    }

    private func validate(target: RuntimeUninstallTarget, inventory: UninstallInventory) throws {
        do {
            try target.manifest.validate()
            try PrivilegedRequest.removePacketFilter(anchor: target.packetFilterAnchor)
                .validate(policy: .runtime110)
            for name in inventory.resolverNames {
                try PrivilegedRequest.removeResolver(name: name).validate(policy: .runtime110)
            }
        } catch {
            throw UninstallError.invalidInventory
        }
        guard
            inventory.runtimeVersion == target.manifest.runtimeVersion,
            inventory.serviceLabels.allSatisfy({ $0.hasPrefix("com.apple.container.") }),
            Set(inventory.serviceLabels).count == inventory.serviceLabels.count,
            Set(inventory.resolverNames).count == inventory.resolverNames.count
        else {
            throw UninstallError.invalidInventory
        }
    }
}

public enum UninstallError: Error, Equatable, Sendable {
    case confirmationDenied
    case incomplete(ResidueReport)
    case invalidInventory
    case invalidMode
    case irreversibleDeletionNotAcknowledged
    case journalUnavailable
    case lifecycleBusy
    case stageFailed(UninstallStage)
    case staleConfirmation
}
