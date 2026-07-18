import MCSystemLifecycle
import Observation

public enum RuntimeLifecycleViewState: Equatable, Sendable {
    case ready
    case authorizingHelper
    case helperApprovalRequired
    case installing
    case installed(version: String)
    case preparingUninstall(UninstallMode)
    case readyToUninstall(UninstallMode)
    case uninstalling(UninstallMode)
    case uninstalled(UninstallCompletion)
    case failed(code: String)
}

@MainActor
@Observable
public final class RuntimeLifecycleController {
    public private(set) var state: RuntimeLifecycleViewState = .ready
    public private(set) var helperStatus: PrivilegedHelperRegistrationStatus = .unknown
    public private(set) var preparedInventory: UninstallInventory?

    private let service: any RuntimeLifecycleServicing

    public init(service: any RuntimeLifecycleServicing) {
        self.service = service
    }

    public var isBusy: Bool {
        switch state {
        case .authorizingHelper, .installing, .preparingUninstall, .uninstalling:
            true
        default:
            false
        }
    }

    public func refreshHelperStatus() async {
        helperStatus = await service.helperStatus()
        if helperStatus == .requiresApproval {
            state = .helperApprovalRequired
        }
    }

    public func authorizeHelper() async {
        state = .authorizingHelper
        do {
            let status = try await service.requestHelperAvailability()
            helperStatus = status
            state = status == .enabled ? .ready : .helperApprovalRequired
        } catch {
            state = .failed(code: "lifecycle.helper.authorization-failed")
        }
    }

    public func openHelperApprovalSettings() async {
        await service.openHelperApprovalSettings()
    }

    public func install() async {
        state = .installing
        do {
            let report = try await service.installReviewedRuntime()
            preparedInventory = nil
            state = .installed(version: report.runtimeVersion)
        } catch RuntimeLifecycleServiceError.helperApprovalRequired {
            helperStatus = .requiresApproval
            state = .helperApprovalRequired
        } catch let error as InstallError {
            state = .failed(code: Self.installFailureCode(error))
        } catch {
            state = .failed(code: "lifecycle.install.failed")
        }
    }

    public func prepareUninstall(mode: UninstallMode) async {
        state = .preparingUninstall(mode)
        do {
            let inventory = try await service.prepareUninstall(mode: mode)
            preparedInventory = inventory
            state = .readyToUninstall(mode)
        } catch RuntimeLifecycleServiceError.helperApprovalRequired {
            helperStatus = .requiresApproval
            state = .helperApprovalRequired
        } catch {
            preparedInventory = nil
            state = .failed(code: "lifecycle.uninstall.inventory-failed")
        }
    }

    public func uninstall(
        mode: UninstallMode,
        inventory: UninstallInventory,
        acknowledgesIrreversibleDeletion: Bool
    ) async {
        guard preparedInventory?.fingerprint == inventory.fingerprint,
              inventory.mode == mode
        else {
            state = .failed(code: "lifecycle.uninstall.stale-inventory")
            return
        }
        state = .uninstalling(mode)
        do {
            let result = try await service.uninstall(
                mode: mode,
                inventoryFingerprint: inventory.fingerprint,
                acknowledgesIrreversibleDeletion: acknowledgesIrreversibleDeletion
            )
            preparedInventory = nil
            state = .uninstalled(result.completion)
        } catch {
            state = .failed(code: "lifecycle.uninstall.failed")
        }
    }

    public func unregisterHelper() async {
        do {
            try await service.unregisterHelper()
            helperStatus = .notRegistered
        } catch {
            state = .failed(code: "lifecycle.helper.unregistration-failed")
        }
    }

    private static func installFailureCode(_ error: InstallError) -> String {
        switch error {
        case let .postflightFailed(stage), let .stageFailed(stage):
            "lifecycle.install.\(stage.rawValue)"
        case .consentDenied:
            "lifecycle.install.consent-denied"
        case .incompleteRecovery:
            "lifecycle.install.recovery-incomplete"
        case .installedButTemporaryCleanupFailed, .temporaryCleanupFailed:
            "lifecycle.install.cleanup-failed"
        case .invalidReleaseMetadata, .invalidTarget:
            "lifecycle.install.metadata-invalid"
        case .journalUnavailable:
            "lifecycle.install.journal-unavailable"
        case .receiptMismatch:
            "lifecycle.install.receipt-mismatch"
        case .temporaryDirectoryUnavailable, .unsafeTemporaryDirectory:
            "lifecycle.install.staging-unavailable"
        case .upgradeRequired:
            "lifecycle.install.upgrade-required"
        case .verificationReportMismatch:
            "lifecycle.install.verification-mismatch"
        }
    }
}
