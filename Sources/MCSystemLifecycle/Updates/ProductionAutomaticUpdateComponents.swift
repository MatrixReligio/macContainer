import Darwin
import Foundation
import MCCompatibility
import MCContainerBridge
import MCModel

public protocol CompatibilityCatalogProviding: Sendable {
    func catalog() throws -> CompatibilityCatalog
}

public struct BundledCompatibilityCatalogProvider: CompatibilityCatalogProviding, Sendable {
    public init() {}
    public func catalog() throws -> CompatibilityCatalog { try CompatibilityCatalog.bundled() }
}

public protocol RuntimeUpdateHostProfiling: Sendable {
    func profile() -> HostProfile
}

public struct SystemRuntimeUpdateHostProfiler: RuntimeUpdateHostProfiling, Sendable {
    public init() {}

    public func profile() -> HostProfile {
        HostProfile(
            logicalCPUs: ProcessInfo.processInfo.processorCount,
            physicalMemoryBytes: Int64(clamping: ProcessInfo.processInfo.physicalMemory),
            chip: .appleSilicon,
            macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            capabilities: []
        )
    }
}

public protocol RuntimeUpdateActivityProviding: Sendable {
    func currentActivity() async throws -> RuntimeActivitySnapshot
}

public struct BridgeRuntimeUpdateActivityProvider: RuntimeUpdateActivityProviding, Sendable {
    private let bridge: any RuntimeBridge

    public init(bridge: any RuntimeBridge) {
        self.bridge = bridge
    }

    public func currentActivity() async throws -> RuntimeActivitySnapshot {
        async let containers = bridge.containers.list()
        async let machines = bridge.machines.list()
        async let builder = bridge.builders.status()
        let containerCount = try await containers.count(where: { Self.isActive($0.state) })
        let machineCount = try await machines.count(where: { Self.isActive($0.state) })
        let builderActive = try await Self.isActive(builder.state)
        return RuntimeActivitySnapshot(
            activeContainers: containerCount,
            activeMachines: machineCount,
            activeBuilds: 0,
            builderActive: builderActive
        )
    }

    private static func isActive(_ state: RuntimeResourceState) -> Bool {
        switch state {
        case .stopped: false
        case .starting, .running, .stopping, .failed, .unknown: true
        }
    }
}

public protocol PhysicalAttestationIDProviding: Sendable {
    func verifiedIDs(for entry: CompatibilityEntry) async -> Set<String>
}

public struct FailClosedPhysicalAttestationIDProvider: PhysicalAttestationIDProviding, Sendable {
    public init() {}
    public func verifiedIDs(for _: CompatibilityEntry) async -> Set<String> { [] }
}

public struct SystemAutomaticUpdateContextProvider: AutomaticUpdateContextProviding, Sendable {
    private let catalogProvider: any CompatibilityCatalogProviding
    private let appVersion: String
    private let hostProvider: any RuntimeUpdateHostProfiling
    private let targetResolver: any InstalledRuntimeTargetResolving
    private let preferences: any RuntimeUpdatePreferencesPersisting
    private let registrar: any PrivilegedHelperRegistering
    private let activityProvider: any RuntimeUpdateActivityProviding
    private let attestationProvider: any PhysicalAttestationIDProviding
    private let blockedVersions: BlockedVersionStore
    private let bridge: any RuntimeBridge

    public init(
        catalogProvider: any CompatibilityCatalogProviding = BundledCompatibilityCatalogProvider(),
        appVersion: String = SystemApplicationVersion.current,
        hostProvider: any RuntimeUpdateHostProfiling = SystemRuntimeUpdateHostProfiler(),
        targetResolver: any InstalledRuntimeTargetResolving = SystemInstalledRuntimeTargetResolver(),
        preferences: any RuntimeUpdatePreferencesPersisting = RuntimeUpdatePreferencesStore(),
        registrar: any PrivilegedHelperRegistering = PrivilegedHelperRegistrar(),
        activityProvider: (any RuntimeUpdateActivityProviding)? = nil,
        attestationProvider: any PhysicalAttestationIDProviding = FailClosedPhysicalAttestationIDProvider(),
        blockedVersions: BlockedVersionStore = BlockedVersionStore(),
        bridge: any RuntimeBridge = AppleRuntimeBridge()
    ) {
        self.catalogProvider = catalogProvider
        self.appVersion = appVersion
        self.hostProvider = hostProvider
        self.targetResolver = targetResolver
        self.preferences = preferences
        self.registrar = registrar
        self.activityProvider = activityProvider ?? BridgeRuntimeUpdateActivityProvider(bridge: bridge)
        self.attestationProvider = attestationProvider
        self.blockedVersions = blockedVersions
        self.bridge = bridge
    }

    public func context(for candidate: RuntimeReleaseCandidate) async throws -> AutomaticUpdateContext {
        let catalog = try? catalogProvider.catalog().validated()
        let installed = try await targetResolver.resolve()
        let preferences = try preferences.load()
        let activity = try await activityProvider.currentActivity()
        let entry = catalog?.entry(runtimeVersion: candidate.version)
        let verifiedAttestationIDs = if let entry {
            await attestationProvider.verifiedIDs(for: entry)
        } else {
            Set<String>()
        }
        let blockedAttestationID: String? = if let catalog, let entry {
            try await blockedVersions.blockingAttestationID(
                for: entry,
                catalogRevision: catalog.revision
            )
        } else {
            nil
        }
        return AutomaticUpdateContext(
            catalog: catalog,
            appVersion: appVersion,
            host: hostProvider.profile(),
            installedRuntimeVersion: installed.manifest.runtimeVersion,
            installedPackageSHA256: installed.manifest.sha256,
            verifiedAttestationIDs: verifiedAttestationIDs,
            blockedAttestationID: blockedAttestationID,
            destructiveMigrationConsent: false,
            mode: preferences.mode,
            consentVersion: preferences.consentVersion,
            helperAuthorized: await registrar.status() == .enabled,
            activity: activity,
            bridge: bridge,
            enabledCapabilityIDs: entry?.capabilityIDs ?? []
        )
    }

    public func currentActivity() async throws -> RuntimeActivitySnapshot {
        try await activityProvider.currentActivity()
    }
}

public struct SystemAutomaticUpgradeBaselineCapture: UpgradeBaselineCapturing, Sendable {
    private let targetResolver: any InstalledRuntimeTargetResolving
    private let packageRoot: URL
    private let homeDirectory: URL

    public init(
        targetResolver: any InstalledRuntimeTargetResolving = SystemInstalledRuntimeTargetResolver(),
        packageRoot: URL = VerifiedRuntimePackageCache.defaultRootDirectory,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.targetResolver = targetResolver
        self.packageRoot = packageRoot.standardizedFileURL
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    public func capture() async throws -> UpgradeBaseline {
        let installed = try await targetResolver.resolve()
        guard installed == .reviewedRuntime100 else {
            throw ProductionAutomaticUpdateComponentError.unsupportedUpgradeSource
        }
        let previousTarget = RuntimeInstallTarget(
            manifest: ReviewedRuntime100Manifest.package,
            releaseAPIURL: Self.reviewed100PackageURL,
            requiredProbes: ProbeID.baselineAllCases.map(\.rawValue)
        )
        return try await SystemUpgradeBaselineCapture(
            previousTarget: previousTarget,
            previousPackageURL: packageRoot.appendingPathComponent(
                ReviewedRuntime100Manifest.package.assetName,
                isDirectory: false
            ),
            configurationAndMetadata: [
                homeDirectory.appendingPathComponent(".config/container", isDirectory: true)
            ],
            fullData: []
        ).capture()
    }

    private static let reviewed100PackageURL = URL(
        string: "https://github.com/apple/container/releases/download/1.0.0/" +
            ReviewedRuntime100Manifest.package.assetName
    )!
}

public struct SystemAutomaticRollbackAvailabilityChecker: AutomaticRollbackAvailabilityChecking, Sendable {
    private let baselineCapture: any UpgradeBaselineCapturing
    private let previousPackageVerifier: any PreviousRuntimePackageVerifying

    public init(
        baselineCapture: any UpgradeBaselineCapturing = SystemAutomaticUpgradeBaselineCapture(),
        previousPackageVerifier: any PreviousRuntimePackageVerifying = SystemPreviousRuntimePackageVerifier()
    ) {
        self.baselineCapture = baselineCapture
        self.previousPackageVerifier = previousPackageVerifier
    }

    public func check(target: RuntimeUpgradeTarget) async throws {
        guard target.installTarget.manifest == ReviewedRuntime110Manifest.package else {
            throw ProductionAutomaticUpdateComponentError.invalidTarget
        }
        let baseline = try await baselineCapture.capture()
        guard baseline.previousTarget.manifest == ReviewedRuntime100Manifest.package else {
            throw ProductionAutomaticUpdateComponentError.unsupportedUpgradeSource
        }
        let verified = try await previousPackageVerifier.verify(baseline)
        guard verified.runtimeVersion == baseline.previousTarget.manifest.runtimeVersion,
              verified.sha256 == baseline.previousTarget.manifest.sha256,
              verified.receiptIdentifier == baseline.previousTarget.manifest.receiptIdentifier,
              verified.installLocation == baseline.previousTarget.manifest.installLocation,
              verified.payload == baseline.previousTarget.manifest.payload
        else {
            throw ProductionAutomaticUpdateComponentError.previousPackageMismatch
        }
        try verified.openFile.revalidateIdentity()
    }
}

public enum ProductionAutomaticUpdateComponentError: Error, Equatable, Sendable {
    case invalidTarget
    case previousPackageMismatch
    case unsupportedUpgradeSource
}

public enum SystemApplicationVersion {
    public static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
}

public struct ReviewedUpgradeTargetBlocker: UpgradeTargetBlocking, Sendable {
    private let entry: CompatibilityEntry
    private let catalogRevision: String
    private let appVersion: String
    private let store: BlockedVersionStore
    private let now: @Sendable () -> Date

    public init(
        entry: CompatibilityEntry,
        catalogRevision: String,
        appVersion: String,
        store: BlockedVersionStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.entry = entry
        self.catalogRevision = catalogRevision
        self.appVersion = appVersion
        self.store = store
        self.now = now
    }

    public func block(version: String, failureCode _: String) async throws {
        guard version == entry.runtimeVersion else {
            throw ProductionAutomaticUpdateComponentError.invalidTarget
        }
        try await store.record(.init(
            runtimeVersion: version,
            appVersion: appVersion,
            catalogRevision: catalogRevision,
            attestationID: entry.attestation.id,
            failedProbeID: nil,
            timestamp: now()
        ))
    }
}

public struct DenyAutomaticDowngradeConsentProvider: UpgradeDowngradeConsentProviding, Sendable {
    public init() {}
    public func approve(_: DowngradeConsentRequest) async -> Bool { false }
}

public struct UpgradeDiagnosticRecord: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let failure: RedactedLifecycleFailure

    public init(timestamp: Date, failure: RedactedLifecycleFailure) {
        self.timestamp = timestamp
        self.failure = failure
    }
}

public enum PrivateUpgradeDiagnosticStoreError: Error, Equatable, Sendable {
    case corruptStorage
    case unsafeStorage
}

public actor PrivateUpgradeDiagnosticStore: UpgradeDiagnosticPersisting {
    private struct Storage: Codable {
        let schemaVersion: Int
        var records: [UpgradeDiagnosticRecord]
    }

    private let fileURL: URL
    private let now: @Sendable () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileURL: URL = PrivateUpgradeDiagnosticStore.defaultURL,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileURL = fileURL.standardizedFileURL
        self.now = now
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func persist(_ failure: RedactedLifecycleFailure) throws {
        var storage = try load()
        storage.records.append(.init(timestamp: now(), failure: failure))
        storage.records = Array(storage.records.suffix(32))
        try save(storage)
    }

    public func records() throws -> [UpgradeDiagnosticRecord] {
        try load().records
    }

    private func load() throws -> Storage {
        var status = stat()
        guard Darwin.lstat(fileURL.path, &status) == 0 else {
            if errno == ENOENT { return Storage(schemaVersion: 1, records: []) }
            throw PrivateUpgradeDiagnosticStoreError.unsafeStorage
        }
        guard status.st_mode & S_IFMT == S_IFREG,
              status.st_uid == geteuid(),
              status.st_nlink == 1,
              status.st_mode & 0o077 == 0,
              status.st_size <= 1_048_576
        else {
            throw PrivateUpgradeDiagnosticStoreError.unsafeStorage
        }
        let descriptor = Darwin.open(fileURL.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw PrivateUpgradeDiagnosticStoreError.unsafeStorage }
        defer { Darwin.close(descriptor) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else {
                if errno == EINTR { continue }
                throw PrivateUpgradeDiagnosticStoreError.unsafeStorage
            }
            guard count > 0 else { break }
            guard data.count + count <= 1_048_576 else {
                throw PrivateUpgradeDiagnosticStoreError.corruptStorage
            }
            data.append(buffer, count: count)
        }
        do {
            let storage = try decoder.decode(Storage.self, from: data)
            guard storage.schemaVersion == 1, storage.records.count <= 32 else {
                throw PrivateUpgradeDiagnosticStoreError.corruptStorage
            }
            return storage
        } catch let error as PrivateUpgradeDiagnosticStoreError {
            throw error
        } catch {
            throw PrivateUpgradeDiagnosticStoreError.corruptStorage
        }
    }

    private func save(_ storage: Storage) throws {
        let parent = fileURL.deletingLastPathComponent()
        try ensurePrivateDirectory(parent.deletingLastPathComponent())
        try ensurePrivateDirectory(parent)
        let data = try encoder.encode(storage)
        guard data.count <= 1_048_576 else {
            throw PrivateUpgradeDiagnosticStoreError.corruptStorage
        }
        let directoryDescriptor = Darwin.open(
            parent.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard directoryDescriptor >= 0 else {
            throw PrivateUpgradeDiagnosticStoreError.unsafeStorage
        }
        defer { Darwin.close(directoryDescriptor) }
        let temporaryName = ".diagnostic-\(UUID().uuidString).tmp"
        let descriptor = temporaryName.withCString {
            Darwin.openat(directoryDescriptor, $0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        }
        guard descriptor >= 0 else {
            throw PrivateUpgradeDiagnosticStoreError.unsafeStorage
        }
        var removeTemporary = true
        defer {
            Darwin.close(descriptor)
            if removeTemporary {
                _ = temporaryName.withCString { Darwin.unlinkat(directoryDescriptor, $0, 0) }
            }
        }
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                guard count >= 0 else {
                    if errno == EINTR { continue }
                    throw PrivateUpgradeDiagnosticStoreError.unsafeStorage
                }
                offset += count
            }
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw PrivateUpgradeDiagnosticStoreError.unsafeStorage
        }
        let renamed = temporaryName.withCString { temporary in
            fileURL.lastPathComponent.withCString { destination in
                Darwin.renameat(directoryDescriptor, temporary, directoryDescriptor, destination)
            }
        }
        guard renamed == 0, Darwin.fsync(directoryDescriptor) == 0 else {
            throw PrivateUpgradeDiagnosticStoreError.unsafeStorage
        }
        removeTemporary = false
    }

    private func ensurePrivateDirectory(_ directory: URL) throws {
        var status = stat()
        if Darwin.lstat(directory.path, &status) != 0 {
            guard errno == ENOENT, Darwin.mkdir(directory.path, 0o700) == 0,
                  Darwin.lstat(directory.path, &status) == 0
            else {
                throw PrivateUpgradeDiagnosticStoreError.unsafeStorage
            }
        }
        guard status.st_mode & S_IFMT == S_IFDIR,
              status.st_uid == geteuid(),
              status.st_mode & 0o077 == 0
        else {
            throw PrivateUpgradeDiagnosticStoreError.unsafeStorage
        }
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("container.matrixreligio.com", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
            .appendingPathComponent("upgrade-diagnostics.json", isDirectory: false)
    }
}

public enum ProductionRuntimeUpdateCoordinatorFactory {
    public static func make(
        stateSink: any RuntimeUpdateStateSink,
        bridge: any RuntimeBridge = AppleRuntimeBridge(),
        registrar: any PrivilegedHelperRegistering = PrivilegedHelperRegistrar(),
        preferences: any RuntimeUpdatePreferencesPersisting = RuntimeUpdatePreferencesStore(),
        attestationProvider: any PhysicalAttestationIDProviding = FailClosedPhysicalAttestationIDProvider(),
        targetResolver: any InstalledRuntimeTargetResolving = SystemInstalledRuntimeTargetResolver(),
        blockedVersions: BlockedVersionStore = BlockedVersionStore(),
        packageCache: VerifiedRuntimePackageCache = VerifiedRuntimePackageCache(),
        rollbackStore: RollbackStore = RollbackStore(packageVerifier: RuntimePackageVerifier.system),
        diagnostics: any UpgradeDiagnosticPersisting = PrivateUpgradeDiagnosticStore()
    ) throws -> RuntimeUpdateCoordinator {
        let catalog = try CompatibilityCatalog.bundled().validated()
        guard let entry = catalog.entry(runtimeVersion: ReviewedRuntime110Manifest.package.runtimeVersion) else {
            throw ProductionAutomaticUpdateComponentError.invalidTarget
        }
        let appVersion = SystemApplicationVersion.current
        let baseline = SystemAutomaticUpgradeBaselineCapture(targetResolver: targetResolver)
        let helper = HelperClient()
        let transaction = UpgradeTransaction(
            packagePreparer: SystemUpgradePackagePreparer(),
            baselineCapture: baseline,
            previousPackageVerifier: SystemPreviousRuntimePackageVerifier(),
            rollback: rollbackStore,
            workloads: BridgeUpgradeWorkObserver(bridge: bridge),
            services: BridgeUpgradeServiceController(bridge: bridge),
            helper: helper,
            installedRuntimeVerifier: SystemUpgradeInstalledRuntimeVerifier(bridge: bridge),
            probes: BridgeUpgradeProbeRunner(
                bridge: bridge,
                enabledCapabilityIDs: entry.capabilityIDs
            ),
            journal: LifecycleUpgradeJournalWriter(journal: .live()),
            blocker: ReviewedUpgradeTargetBlocker(
                entry: entry,
                catalogRevision: catalog.revision,
                appVersion: appVersion,
                store: blockedVersions
            ),
            diagnostics: diagnostics,
            downgradeConsent: DenyAutomaticDowngradeConsentProvider(),
            packageRetainer: packageCache
        )
        return RuntimeUpdateCoordinator(
            contextProvider: SystemAutomaticUpdateContextProvider(
                catalogProvider: BundledCompatibilityCatalogProvider(),
                appVersion: appVersion,
                targetResolver: targetResolver,
                preferences: preferences,
                registrar: registrar,
                attestationProvider: attestationProvider,
                blockedVersions: blockedVersions,
                bridge: bridge
            ),
            packageVerifier: ReviewedAutomaticUpdatePackageVerifier(),
            rollbackAvailability: SystemAutomaticRollbackAvailabilityChecker(
                baselineCapture: baseline,
                previousPackageVerifier: SystemPreviousRuntimePackageVerifier()
            ),
            executor: transaction,
            blocker: BlockedVersionUpdateRecorder(store: blockedVersions),
            stateSink: stateSink
        )
    }
}
