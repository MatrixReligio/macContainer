import Foundation
import MCSystemLifecycle

public actor SimulatedRuntimeLifecycleService: RuntimeLifecycleServicing {
    private var helperRegistration: PrivilegedHelperRegistrationStatus = .enabled
    private var installedVersion: String?

    public init() {}

    public func installedReviewedRuntimeVersion() -> String? {
        installedVersion
    }

    public func helperStatus() -> PrivilegedHelperRegistrationStatus {
        helperRegistration
    }

    public func requestHelperAvailability() -> PrivilegedHelperRegistrationStatus {
        helperRegistration = .enabled
        return helperRegistration
    }

    public func openHelperApprovalSettings() {}

    public func installReviewedRuntime() -> InstallReport {
        installedVersion = "1.1.0"
        return .init(
            runtimeVersion: "1.1.0",
            packageSHA256: ReviewedRuntime110Manifest.package.sha256,
            receipt: .init(
                identifier: ReviewedRuntime110Manifest.package.receiptIdentifier,
                version: ReviewedRuntime110Manifest.package.runtimeVersion,
                installLocation: ReviewedRuntime110Manifest.package.installLocation
            )
        )
    }

    public func prepareUninstall(mode: UninstallMode) -> UninstallInventory {
        .init(
            runtimeVersion: "1.1.0",
            activeWork: [],
            serviceLabels: ["com.apple.container.apiserver"],
            resolverNames: [],
            artifactKinds: Set(ResidueKind.allCases),
            estimatedBytes: 420 * 1024 * 1024,
            mode: mode
        )
    }

    public func uninstall(
        mode: UninstallMode,
        inventoryFingerprint _: String,
        acknowledgesIrreversibleDeletion _: Bool
    ) -> UninstallResult {
        installedVersion = nil
        let preserved: Set<ResidueKind> = mode == .preserveData
            ? [.applicationSupport, .configuration, .defaultsDomain, .registryCredential]
            : []
        let report = ResidueReport(items: ResidueInventory.expectations.map { expectation in
            .init(
                kind: expectation.kind,
                redactedLocation: expectation.redactedLocation,
                status: preserved.contains(expectation.kind) ? .present : .absent,
                recoveryKey: expectation.recoveryKey
            )
        })
        return .init(
            completion: mode == .complete ? .complete : .dataPreserved,
            audit: report,
            preservedKinds: preserved.sorted { $0.rawValue < $1.rawValue }
        )
    }

    public func unregisterHelper() {
        helperRegistration = .notRegistered
    }
}
