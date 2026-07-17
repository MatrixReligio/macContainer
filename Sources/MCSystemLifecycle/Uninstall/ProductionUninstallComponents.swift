import Darwin
import Foundation
import MCContainerBridge
import MCModel

public protocol InstalledRuntimeTargetResolving: Sendable {
    func resolve() async throws -> RuntimeUninstallTarget
}

public struct SystemInstalledRuntimeTargetResolver: InstalledRuntimeTargetResolving, Sendable {
    private let receipts: PackageReceiptReader

    public init(
        receipts: PackageReceiptReader = PackageReceiptReader(backend: SystemPackageReceiptBackend())
    ) {
        self.receipts = receipts
    }

    public func resolve() async throws -> RuntimeUninstallTarget {
        guard let receipt = try await receipts.readReviewedRuntimeReceipt() else {
            throw ProductionUninstallComponentError.runtimeNotInstalled
        }
        return switch receipt.version {
        case ReviewedRuntime100Manifest.package.runtimeVersion:
            .reviewedRuntime100
        case ReviewedRuntime110Manifest.package.runtimeVersion:
            .reviewedRuntime110
        default:
            throw ProductionUninstallComponentError.unreviewedRuntime
        }
    }
}

public struct SystemUninstallInventoryRefresher: UninstallInventoryRefreshing, Sendable {
    private let target: RuntimeUninstallTarget
    private let receipts: PackageReceiptReader
    private let bridge: any RuntimeBridge
    private let services: any ServiceManaging
    private let resolvers: any ResolverNameInventorying
    private let residue: any ResidueAuditChecking

    public init(
        target: RuntimeUninstallTarget = .reviewedRuntime110,
        receipts: PackageReceiptReader = PackageReceiptReader(backend: SystemPackageReceiptBackend()),
        bridge: any RuntimeBridge = AppleRuntimeBridge(),
        services: any ServiceManaging = AppleServiceManager(managedPlistURLs: [:]),
        resolvers: any ResolverNameInventorying = SystemResolverNameInventory(),
        residue: any ResidueAuditChecking = SystemResidueAuditChecker()
    ) {
        self.target = target
        self.receipts = receipts
        self.bridge = bridge
        self.services = services
        self.resolvers = resolvers
        self.residue = residue
    }

    public func refresh(mode: UninstallMode) async throws -> UninstallInventory {
        try target.manifest.validate()
        guard let receipt = try await receipts.readReviewedRuntimeReceipt(
            identifier: target.manifest.receiptIdentifier
        ) else {
            throw ProductionUninstallComponentError.runtimeNotInstalled
        }
        guard receipt.version == target.manifest.runtimeVersion,
              receipt.installLocation == target.manifest.installLocation
        else {
            throw ProductionUninstallComponentError.unreviewedRuntime
        }

        async let containers = bridge.containers.list()
        async let machines = bridge.machines.list()
        async let serviceLabels = services.labels(prefix: SystemServiceController.servicePrefix)
        let activeContainers = try await containers.filter { Self.isActive($0.state) }.map(\.id)
        let activeMachines = try await machines.filter { Self.isActive($0.state) }.map(\.id)
        let labels = try await serviceLabels.sorted()
        guard labels.allSatisfy({ $0.hasPrefix(SystemServiceController.servicePrefix) }),
              Set(labels).count == labels.count
        else {
            throw ProductionUninstallComponentError.invalidServiceInventory
        }
        let resolverNames = try resolvers.names().sorted()
        guard Set(resolverNames).count == resolverNames.count else {
            throw ProductionUninstallComponentError.invalidResolverInventory
        }

        var artifactKinds = Set<ResidueKind>()
        for expectation in ResidueInventory.expectations {
            switch try await residue.status(for: expectation.kind) {
            case .present:
                artifactKinds.insert(expectation.kind)
            case .absent:
                break
            case .unverifiable:
                throw ProductionUninstallComponentError.incompleteResidueInventory
            }
        }
        return try UninstallInventory(
            runtimeVersion: receipt.version,
            activeWork: activeContainers.map { "container:\($0)" } +
                activeMachines.map { "machine:\($0)" },
            serviceLabels: labels,
            resolverNames: resolverNames,
            artifactKinds: artifactKinds,
            estimatedBytes: estimatedPayloadBytes(),
            mode: mode
        )
    }

    private static func isActive(_ state: RuntimeResourceState) -> Bool {
        switch state {
        case .stopped: false
        case .starting, .running, .stopping, .failed, .unknown: true
        }
    }

    private func estimatedPayloadBytes() throws -> UInt64 {
        let root = URL(fileURLWithPath: target.manifest.installLocation, isDirectory: true)
        var total: UInt64 = 0
        for entry in target.manifest.payload where entry.kind == .file {
            var status = stat()
            let url = root.appendingPathComponent(entry.relativePath)
            guard Darwin.lstat(url.path, &status) == 0 else {
                if errno == ENOENT {
                    continue
                }
                throw ProductionUninstallComponentError.payloadInventoryFailed
            }
            guard status.st_mode & S_IFMT == S_IFREG, status.st_size >= 0 else {
                throw ProductionUninstallComponentError.payloadInventoryFailed
            }
            let size = UInt64(status.st_size)
            let (next, overflow) = total.addingReportingOverflow(size)
            total = overflow ? .max : next
        }
        return total
    }
}

public struct BridgeUninstallServiceStopper: UninstallServiceStopping, Sendable {
    private let bridge: any RuntimeBridge

    public init(bridge: any RuntimeBridge) {
        self.bridge = bridge
    }

    public func stopAll(activeWork _: [String], serviceLabels: [String]) async throws {
        guard serviceLabels.allSatisfy({ $0.hasPrefix(SystemServiceController.servicePrefix) }) else {
            throw ProductionUninstallComponentError.invalidServiceInventory
        }
        let result = try await bridge.system.stop(.init(
            stopActiveWorkloads: true,
            timeoutSeconds: 60
        ))
        guard result.state == .stopped else {
            throw ProductionUninstallComponentError.serviceStopFailed
        }
    }
}

public struct SystemUninstallProcessVerifier: UninstallProcessVerifying, Sendable {
    private let manifest: RuntimePackageManifest
    private let processes: any OwnedProcessResidueInspecting

    public init(
        manifest: RuntimePackageManifest = ReviewedRuntime110Manifest.package,
        processes: any OwnedProcessResidueInspecting = SystemOwnedProcessResidueInspector()
    ) {
        self.manifest = manifest
        self.processes = processes
    }

    public func verifyNoOwnedProcess() async throws {
        let paths = Set(manifest.payload.compactMap { entry -> String? in
            guard entry.kind == .file else { return nil }
            return URL(fileURLWithPath: manifest.installLocation, isDirectory: true)
                .appendingPathComponent(entry.relativePath)
                .standardizedFileURL.path
        })
        guard try !processes.hasOwnedProcess(
            executablePaths: paths,
            expectedTeamID: manifest.installerTeamID
        ) else {
            throw ProductionUninstallComponentError.ownedProcessStillRunning
        }
    }
}

public struct SystemUninstallConfirmationChecker: UninstallConfirmationChecking, Sendable {
    public init() {}

    public func approve(
        inventory: UninstallInventory,
        confirmation: CompleteUninstallConfirmation
    ) async throws -> Bool {
        guard inventory.fingerprint == confirmation.inventoryFingerprint,
              inventory.mode == confirmation.mode
        else {
            return false
        }
        return confirmation.mode == .preserveData || confirmation.acknowledgesIrreversibleDeletion
    }
}

public enum ProductionUninstallComponentError: Error, Equatable, Sendable {
    case incompleteResidueInventory
    case invalidResolverInventory
    case invalidServiceInventory
    case ownedProcessStillRunning
    case payloadInventoryFailed
    case runtimeNotInstalled
    case serviceStopFailed
    case unreviewedRuntime
}
