import Foundation
import MCCompatibility
import MCContainerBridge

public protocol RuntimeLifecycleServicing: Sendable {
    func installedReviewedRuntimeVersion() async throws -> String?
    func helperStatus() async -> PrivilegedHelperRegistrationStatus
    func requestHelperAvailability() async throws -> PrivilegedHelperRegistrationStatus
    func openHelperApprovalSettings() async
    func installReviewedRuntime() async throws -> InstallReport
    func prepareUninstall(mode: UninstallMode) async throws -> UninstallInventory
    func uninstall(
        mode: UninstallMode,
        inventoryFingerprint: String,
        acknowledgesIrreversibleDeletion: Bool
    ) async throws -> UninstallResult
    func unregisterHelper() async throws
}

public actor ProductionRuntimeLifecycle: RuntimeLifecycleServicing {
    private let registrar: any PrivilegedHelperRegistering
    private let bridge: any RuntimeBridge
    private let helper: HelperClient
    private let targetResolver: any InstalledRuntimeTargetResolving
    private let operationLock = LifecycleOperationLock()

    public init(
        registrar: any PrivilegedHelperRegistering = PrivilegedHelperRegistrar(),
        bridge: any RuntimeBridge = AppleRuntimeBridge(),
        helper: HelperClient = HelperClient(),
        targetResolver: any InstalledRuntimeTargetResolving = SystemInstalledRuntimeTargetResolver()
    ) {
        self.registrar = registrar
        self.bridge = bridge
        self.helper = helper
        self.targetResolver = targetResolver
    }

    public func helperStatus() async -> PrivilegedHelperRegistrationStatus {
        await registrar.status()
    }

    public func installedReviewedRuntimeVersion() async throws -> String? {
        do {
            return try await targetResolver.resolve().manifest.runtimeVersion
        } catch ProductionUninstallComponentError.runtimeNotInstalled {
            return nil
        }
    }

    public func requestHelperAvailability() async throws -> PrivilegedHelperRegistrationStatus {
        try await registrar.ensureAvailable()
    }

    public func openHelperApprovalSettings() async {
        registrar.openApprovalSettings()
    }

    public func installReviewedRuntime() async throws -> InstallReport {
        guard try await registrar.ensureAvailable() == .enabled else {
            throw RuntimeLifecycleServiceError.helperApprovalRequired
        }
        let catalog = try CompatibilityCatalog.bundled()
        guard let entry = catalog.entry(
            runtimeVersion: ReviewedRuntime110Manifest.package.runtimeVersion
        ) else {
            throw RuntimeLifecycleServiceError.compatibilityCatalogUnavailable
        }
        let transaction = InstallTransaction(
            platform: SystemInstallPlatformChecker(),
            metadata: SystemRuntimeReleaseMetadataFetcher(),
            downloader: SystemRuntimePackageDownloader(),
            verifier: RuntimePackageVerifier.system,
            consent: ExplicitInstallConsentProvider(),
            journal: LifecycleInstallJournalWriter(journal: .live()),
            helper: helper,
            receipt: SystemInstalledReceiptVerifier(),
            payload: SystemInstalledPayloadVerifier(),
            service: BridgeInstallServiceController(bridge: bridge),
            kernel: BridgeInstallKernelEnsurer(bridge: bridge),
            probes: BridgeInstallProbeRunner(
                bridge: bridge,
                expectedRuntimeVersion: entry.runtimeVersion,
                enabledCapabilityIDs: entry.capabilityIDs
            ),
            partialUninstaller: SystemPartialInstallUninstaller(
                bridge: bridge,
                helper: helper
            ),
            residueAuditor: SystemPartialInstallResidueAuditor(),
            temporaryDirectories: LocalInstallTemporaryDirectoryProvider(),
            packageRetainer: VerifiedRuntimePackageCache()
        )
        return try await transaction.install(.appleContainer110)
    }

    public func prepareUninstall(mode: UninstallMode) async throws -> UninstallInventory {
        guard try await registrar.ensureAvailable() == .enabled else {
            throw RuntimeLifecycleServiceError.helperApprovalRequired
        }
        let target = try await targetResolver.resolve()
        return try await makeInventoryRefresher(target: target).refresh(mode: mode)
    }

    public func uninstall(
        mode: UninstallMode,
        inventoryFingerprint: String,
        acknowledgesIrreversibleDeletion: Bool
    ) async throws -> UninstallResult {
        guard try await registrar.ensureAvailable() == .enabled else {
            throw RuntimeLifecycleServiceError.helperApprovalRequired
        }
        let target = try await targetResolver.resolve()
        let inventory = makeInventoryRefresher(target: target)
        let auditChecker = makeAuditChecker(target: target)
        let transaction = UninstallTransaction(
            target: target,
            operationLock: operationLock,
            inventory: inventory,
            confirmation: SystemUninstallConfirmationChecker(),
            services: BridgeUninstallServiceStopper(bridge: bridge),
            processes: SystemUninstallProcessVerifier(manifest: target.manifest),
            credentials: SystemRegistryCredentialRemover(),
            helper: helper,
            userArtifacts: SystemUninstallUserArtifactRemover(),
            auditor: ResidueAuditor(checker: auditChecker),
            journal: LifecycleUninstallJournalWriter(journal: .live())
        )
        let confirmation = CompleteUninstallConfirmation(
            mode: mode,
            inventoryFingerprint: inventoryFingerprint,
            acknowledgesIrreversibleDeletion: acknowledgesIrreversibleDeletion
        )
        switch mode {
        case .complete:
            return try await transaction.completelyUninstall(confirmation: confirmation)
        case .preserveData:
            return try await transaction.removeRuntimePreservingData(confirmation: confirmation)
        }
    }

    public func unregisterHelper() async throws {
        try await registrar.unregister()
    }

    private func makeInventoryRefresher(target: RuntimeUninstallTarget) -> SystemUninstallInventoryRefresher {
        SystemUninstallInventoryRefresher(
            target: target,
            bridge: bridge,
            residue: makeAuditChecker(target: target)
        )
    }

    private func makeAuditChecker(target: RuntimeUninstallTarget) -> SystemResidueAuditChecker {
        SystemResidueAuditChecker(
            configuration: .live(manifest: target.manifest),
            runtimeState: SystemRuntimeStateResidueQuery(
                manifest: target.manifest,
                launchServices: AppleLaunchServiceResidueInspector(),
                processes: SystemOwnedProcessResidueInspector(),
                credentials: KeychainCredentialResidueInspector(),
                packetFilter: helper
            )
        )
    }
}

public struct SystemPartialInstallUninstaller: PartialInstallUninstalling, Sendable {
    private let bridge: any RuntimeBridge
    private let helper: any UninstallPrivilegedHelping
    private let userArtifacts: any UninstallUserArtifactRemoving
    private let credentials: any UninstallCredentialRemoving
    private let resolvers: any ResolverNameInventorying

    public init(
        bridge: any RuntimeBridge,
        helper: any UninstallPrivilegedHelping,
        userArtifacts: any UninstallUserArtifactRemoving = SystemUninstallUserArtifactRemover(),
        credentials: any UninstallCredentialRemoving = SystemRegistryCredentialRemover(),
        resolvers: any ResolverNameInventorying = SystemResolverNameInventory()
    ) {
        self.bridge = bridge
        self.helper = helper
        self.userArtifacts = userArtifacts
        self.credentials = credentials
        self.resolvers = resolvers
    }

    public func removePartialInstall(manifest: RuntimePackageManifest) async throws {
        try manifest.validate()
        _ = try await bridge.system.stop(.init(stopActiveWorkloads: true, timeoutSeconds: 60))
        try await credentials.removeAll()
        for name in try resolvers.names().sorted() {
            try await helper.removeResolver(name: name)
        }
        try await helper.removeEmptyResolverDirectory()
        try await helper.removePacketFilter(anchor: "com.apple.container")
        try await helper.removePayload(
            manifestID: ReviewedRuntime110Manifest.identifier,
            manifestSHA256: ReviewedRuntime110Manifest.sourceSHA256
        )
        try await helper.forgetReceipt(identifier: manifest.receiptIdentifier)
        for kind in SystemUninstallUserArtifactRemover.fileArtifactKinds + [.defaultsDomain] {
            try await userArtifacts.remove(kind)
        }
        try await helper.removeKnownEmptyDirectories(manifestID: ReviewedRuntime110Manifest.identifier)
    }
}

public struct SystemPartialInstallResidueAuditor: PartialInstallResidueAuditing, Sendable {
    private let auditor: any ResidueAuditing

    public init(
        auditor: any ResidueAuditing = ResidueAuditor(checker: SystemResidueAuditChecker())
    ) {
        self.auditor = auditor
    }

    public func audit(manifest _: RuntimePackageManifest) async throws -> PartialInstallAudit {
        let report = await auditor.audit()
        return .init(
            isEmpty: report.isEmpty,
            hasUnverifiableItems: !report.hasCompleteInventory || report.items.contains {
                $0.status == .unverifiable
            }
        )
    }
}

public protocol ResolverNameInventorying: Sendable {
    func names() throws -> [String]
}

public struct SystemResolverNameInventory: ResolverNameInventorying, Sendable {
    private let directory: URL

    public init(directory: URL = URL(fileURLWithPath: "/etc/resolver", isDirectory: true)) {
        self.directory = directory.standardizedFileURL
    }

    public func names() throws -> [String] {
        var status = stat()
        guard Darwin.lstat(directory.path, &status) == 0 else {
            if errno == ENOENT {
                return []
            }
            throw RuntimeLifecycleServiceError.resolverInventoryFailed
        }
        guard status.st_mode & S_IFMT == S_IFDIR else {
            throw RuntimeLifecycleServiceError.resolverInventoryFailed
        }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).compactMap { url in
            let prefix = "containerization."
            guard url.lastPathComponent.hasPrefix(prefix) else { return nil }
            return String(url.lastPathComponent.dropFirst(prefix.count))
        }
    }
}

public struct SystemRegistryCredentialRemover: UninstallCredentialRemoving, Sendable {
    private let store: any RegistryCredentialStorage

    public init(store: any RegistryCredentialStorage = RegistryCredentialStore()) {
        self.store = store
    }

    public func removeAll() async throws {
        for credential in try await store.list() {
            try await store.delete(server: credential.server)
        }
        guard try await store.list().isEmpty else {
            throw RuntimeLifecycleServiceError.credentialRemovalFailed
        }
    }
}

private struct ExplicitInstallConsentProvider: InstallConsentProviding, Sendable {
    func approve(_: InstallConsentRequest) async throws -> Bool {
        true
    }
}

public enum RuntimeLifecycleServiceError: Error, Equatable, Sendable {
    case compatibilityCatalogUnavailable
    case credentialRemovalFailed
    case helperApprovalRequired
    case resolverInventoryFailed
}
