import Foundation

public enum ProbeID: String, Codable, CaseIterable, Sendable {
    case health
    case containers
    case images
    case builder
    case networks
    case volumes
    case registries
    case machines
    case diskUsage
    case configuration
    case capabilities

    public static let baselineAllCases = allCases
}

public struct RuntimePackageIdentity: Codable, Equatable, Sendable {
    public let runtimeVersion: String
    public let assetName: String
    public let sha256: String
    public let installerTeamID: String
    public let signerCommonName: String
    public let receiptIdentifier: String

    public init(
        runtimeVersion: String,
        assetName: String,
        sha256: String,
        installerTeamID: String,
        signerCommonName: String,
        receiptIdentifier: String
    ) {
        self.runtimeVersion = runtimeVersion
        self.assetName = assetName
        self.sha256 = sha256
        self.installerTeamID = installerTeamID
        self.signerCommonName = signerCommonName
        self.receiptIdentifier = receiptIdentifier
    }
}

public struct UpgradeSourceIdentity: Codable, Equatable, Sendable {
    public let runtimeVersion: String
    public let package: RuntimePackageIdentity
    public let installLocation: String
    public let requiredPreflightProbeIDs: [String]
    public let storageMigration: StorageMigrationClassification
    public let rollback: RollbackClassification

    public var packageSHA256: String {
        package.sha256
    }

    public init(
        runtimeVersion: String,
        package: RuntimePackageIdentity,
        installLocation: String,
        requiredPreflightProbeIDs: [String],
        storageMigration: StorageMigrationClassification,
        rollback: RollbackClassification
    ) {
        self.runtimeVersion = runtimeVersion
        self.package = package
        self.installLocation = installLocation
        self.requiredPreflightProbeIDs = requiredPreflightProbeIDs
        self.storageMigration = storageMigration
        self.rollback = rollback
    }
}

public enum StorageMigrationClassification: String, Codable, Sendable {
    case none
    case metadataOnly
    case destructive
}

public enum RollbackClassification: String, Codable, Sendable {
    case packageOnly
    case configurationAndMetadata
    case fullDataClone
}

public enum AttestationSource: String, Codable, Sendable {
    case embeddedPhysicalGate
}

public struct AttestationReference: Codable, Equatable, Sendable {
    public let id: String
    public let source: AttestationSource
    public let sourceCommit: String
    public let testPlanVersion: String

    public init(id: String, source: AttestationSource, sourceCommit: String, testPlanVersion: String) {
        self.id = id
        self.source = source
        self.sourceCommit = sourceCommit
        self.testPlanVersion = testPlanVersion
    }
}

public struct CompatibilityEntry: Codable, Equatable, Sendable {
    public let runtimeVersion: String
    public let package: RuntimePackageIdentity
    public let minimumAppVersion: String
    public let maximumAppVersion: String
    public let adapterPackageVersion: String
    public let capabilityIDs: Set<String>
    public let minimumMacOSMajor: Int
    public let requiredHardwareCapabilities: Set<String>
    public let storageMigration: StorageMigrationClassification
    public let rollback: RollbackClassification
    public let allowedUpgradeSources: [UpgradeSourceIdentity]
    public let requiredProbeIDs: [String]
    public let attestation: AttestationReference
    public let supersedesBlockedAttestationIDs: Set<String>

    public init(
        runtimeVersion: String,
        package: RuntimePackageIdentity,
        minimumAppVersion: String,
        maximumAppVersion: String,
        adapterPackageVersion: String,
        capabilityIDs: Set<String>,
        minimumMacOSMajor: Int,
        requiredHardwareCapabilities: Set<String>,
        storageMigration: StorageMigrationClassification,
        rollback: RollbackClassification,
        allowedUpgradeSources: [UpgradeSourceIdentity],
        requiredProbeIDs: [String],
        attestation: AttestationReference,
        supersedesBlockedAttestationIDs: Set<String> = []
    ) {
        self.runtimeVersion = runtimeVersion
        self.package = package
        self.minimumAppVersion = minimumAppVersion
        self.maximumAppVersion = maximumAppVersion
        self.adapterPackageVersion = adapterPackageVersion
        self.capabilityIDs = capabilityIDs
        self.minimumMacOSMajor = minimumMacOSMajor
        self.requiredHardwareCapabilities = requiredHardwareCapabilities
        self.storageMigration = storageMigration
        self.rollback = rollback
        self.allowedUpgradeSources = allowedUpgradeSources
        self.requiredProbeIDs = requiredProbeIDs
        self.attestation = attestation
        self.supersedesBlockedAttestationIDs = supersedesBlockedAttestationIDs
    }

    public func replacing(
        minimumAppVersion: String? = nil,
        maximumAppVersion: String? = nil,
        requiredProbeIDs: [String]? = nil
    ) -> Self {
        Self(
            runtimeVersion: runtimeVersion,
            package: package,
            minimumAppVersion: minimumAppVersion ?? self.minimumAppVersion,
            maximumAppVersion: maximumAppVersion ?? self.maximumAppVersion,
            adapterPackageVersion: adapterPackageVersion,
            capabilityIDs: capabilityIDs,
            minimumMacOSMajor: minimumMacOSMajor,
            requiredHardwareCapabilities: requiredHardwareCapabilities,
            storageMigration: storageMigration,
            rollback: rollback,
            allowedUpgradeSources: allowedUpgradeSources,
            requiredProbeIDs: requiredProbeIDs ?? self.requiredProbeIDs,
            attestation: attestation,
            supersedesBlockedAttestationIDs: supersedesBlockedAttestationIDs
        )
    }
}
