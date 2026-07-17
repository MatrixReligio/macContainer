import Foundation
import MCModel

public enum CompatibilityDecision: Equatable, Sendable {
    case allow(CompatibilityEntry)
    case hold(HoldReason)
}

public enum HoldReason: String, Codable, Equatable, Sendable {
    case unknownRuntime
    case appVersionOutsideRange
    case unsupportedHost
    case packageIdentityMismatch
    case previousRollback
    case explicitConsentRequired
    case missingPhysicalAttestation
    case catalogInvalid
}

public struct CompatibilityDecisionInput: Sendable {
    public let catalog: CompatibilityCatalog?
    public let targetRuntimeVersion: String
    public let appVersion: String
    public let host: HostProfile
    public let package: RuntimePackageIdentity
    public let installedRuntimeVersion: String
    public let installedPackageSHA256: String
    public let verifiedAttestationIDs: Set<String>
    public let blockedAttestationID: String?
    public let destructiveMigrationConsent: Bool

    public init(
        catalog: CompatibilityCatalog?,
        targetRuntimeVersion: String,
        appVersion: String,
        host: HostProfile,
        package: RuntimePackageIdentity,
        installedRuntimeVersion: String,
        installedPackageSHA256: String,
        verifiedAttestationIDs: Set<String>,
        blockedAttestationID: String?,
        destructiveMigrationConsent: Bool
    ) {
        self.catalog = catalog
        self.targetRuntimeVersion = targetRuntimeVersion
        self.appVersion = appVersion
        self.host = host
        self.package = package
        self.installedRuntimeVersion = installedRuntimeVersion
        self.installedPackageSHA256 = installedPackageSHA256
        self.verifiedAttestationIDs = verifiedAttestationIDs
        self.blockedAttestationID = blockedAttestationID
        self.destructiveMigrationConsent = destructiveMigrationConsent
    }
}

public struct CompatibilityDecisionEngine: Sendable {
    public init() {}

    public func decide(_ input: CompatibilityDecisionInput) -> CompatibilityDecision {
        guard let catalog = input.catalog, (try? catalog.validated()) != nil else {
            return .hold(.catalogInvalid)
        }
        guard let entry = catalog.entry(runtimeVersion: input.targetRuntimeVersion) else {
            return .hold(.unknownRuntime)
        }
        guard isAppVersion(input.appVersion, within: entry) else {
            return .hold(.appVersionOutsideRange)
        }
        guard input.host.macOSMajor >= entry.minimumMacOSMajor,
              entry.requiredHardwareCapabilities.isSubset(of: input.host.capabilities)
        else {
            return .hold(.unsupportedHost)
        }
        guard input.package == entry.package,
              entry.allowedUpgradeSources.contains(where: {
                  $0.runtimeVersion == input.installedRuntimeVersion &&
                      $0.packageSHA256 == input.installedPackageSHA256
              })
        else {
            return .hold(.packageIdentityMismatch)
        }
        guard input.verifiedAttestationIDs.contains(entry.attestation.id) else {
            return .hold(.missingPhysicalAttestation)
        }
        if let blockedAttestationID = input.blockedAttestationID {
            if !entry.supersedesBlockedAttestationIDs.contains(blockedAttestationID) {
                return .hold(.previousRollback)
            }
        }
        guard entry.storageMigration != .destructive || input.destructiveMigrationConsent else {
            return .hold(.explicitConsentRequired)
        }
        return .allow(entry)
    }

    private func isAppVersion(_ value: String, within entry: CompatibilityEntry) -> Bool {
        guard let current = try? SemanticVersion(value),
              let minimum = try? SemanticVersion(entry.minimumAppVersion),
              let maximum = try? SemanticVersion(entry.maximumAppVersion)
        else {
            return false
        }
        return minimum <= current && current <= maximum
    }
}
