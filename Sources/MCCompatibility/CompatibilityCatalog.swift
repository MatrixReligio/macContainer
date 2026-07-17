import Foundation
import MCContracts

public struct CompatibilityCatalog: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let revision: String
    public let generatedAt: Date
    public let entries: [CompatibilityEntry]
    public let updateURL: URL?

    public init(
        schemaVersion: Int,
        revision: String,
        generatedAt: Date,
        entries: [CompatibilityEntry],
        updateURL: URL?
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.generatedAt = generatedAt
        self.entries = entries
        self.updateURL = updateURL
    }

    public static func bundled() throws -> Self {
        guard let url = Bundle.module.url(forResource: "catalog-v1", withExtension: "json") else {
            throw CompatibilityCatalogError.resourceMissing
        }
        return try decode(Data(contentsOf: url, options: [.mappedIfSafe]))
    }

    public static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Self.self, from: data).validated()
        } catch let error as CompatibilityCatalogError {
            throw error
        } catch {
            throw CompatibilityCatalogError.malformed
        }
    }

    public func entry(runtimeVersion: String) -> CompatibilityEntry? {
        entries.first { $0.runtimeVersion == runtimeVersion }
    }

    public func validated() throws -> Self {
        guard schemaVersion == 1, !revision.isEmpty else {
            throw CompatibilityCatalogError.invalidSchema
        }
        guard updateURL == nil else {
            throw CompatibilityCatalogError.remoteAuthorityForbidden
        }
        guard !entries.isEmpty else {
            throw CompatibilityCatalogError.emptyCatalog
        }

        var versions = Set<String>()
        var previousVersion: SemanticVersion?
        for entry in entries {
            guard versions.insert(entry.runtimeVersion).inserted else {
                throw CompatibilityCatalogError.duplicateRuntimeVersion(entry.runtimeVersion)
            }
            let runtimeVersion = try SemanticVersion(entry.runtimeVersion)
            if let previousVersion, previousVersion >= runtimeVersion {
                throw CompatibilityCatalogError.unsortedRuntimeVersions
            }
            previousVersion = runtimeVersion
            try validate(entry)
        }
        return self
    }

    private func validate(_ entry: CompatibilityEntry) throws {
        let runtime = try SemanticVersion(entry.runtimeVersion)
        let minimumApp = try SemanticVersion(entry.minimumAppVersion)
        let maximumApp = try SemanticVersion(entry.maximumAppVersion)
        guard minimumApp <= maximumApp else {
            throw CompatibilityCatalogError.invalidAppVersionRange(entry.runtimeVersion)
        }
        guard entry.package.runtimeVersion == entry.runtimeVersion,
              Self.isSHA256(entry.package.sha256),
              entry.package.installerTeamID.count == 10,
              !entry.package.assetName.isEmpty,
              !entry.package.signerCommonName.isEmpty,
              !entry.package.receiptIdentifier.isEmpty,
              (try? SemanticVersion(entry.adapterPackageVersion)) != nil,
              entry.minimumMacOSMajor >= 26
        else {
            throw CompatibilityCatalogError.invalidPackageIdentity(entry.runtimeVersion)
        }
        for source in entry.allowedUpgradeSources {
            guard let sourceVersion = try? SemanticVersion(source.runtimeVersion),
                  sourceVersion < runtime,
                  source.package.runtimeVersion == source.runtimeVersion,
                  source.package.assetName == "container-\(source.runtimeVersion)-installer-signed.pkg",
                  Self.isSHA256(source.package.sha256),
                  source.package.installerTeamID == entry.package.installerTeamID,
                  source.package.signerCommonName == entry.package.signerCommonName,
                  source.package.receiptIdentifier == entry.package.receiptIdentifier,
                  source.installLocation == "/usr/local",
                  source.requiredPreflightProbeIDs == ProbeID.baselineAllCases.map(\.rawValue),
                  source.storageMigration != .destructive
            else {
                throw CompatibilityCatalogError.invalidUpgradeSource(entry.runtimeVersion)
            }
        }
        guard entry.attestation.source == .embeddedPhysicalGate,
              !entry.attestation.id.isEmpty,
              entry.attestation.sourceCommit.count == 40,
              !entry.attestation.testPlanVersion.isEmpty
        else {
            throw CompatibilityCatalogError.invalidAttestation(entry.runtimeVersion)
        }
        guard entry.requiredProbeIDs == ProbeID.baselineAllCases.map(\.rawValue) else {
            throw CompatibilityCatalogError.invalidProbeSet(entry.runtimeVersion)
        }
        guard let reviewedCapabilityIDs = Self.reviewedCapabilityIDs[entry.runtimeVersion],
              entry.capabilityIDs == reviewedCapabilityIDs
        else {
            throw CompatibilityCatalogError.invalidCapabilitySet(entry.runtimeVersion)
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    private static let reviewedCapabilityIDs: [String: Set<String>] = {
        let version = RuntimeVersion(major: 1, minor: 1, patch: 0)
        guard let contract = try? ContractRepository.bundled(version: version) else { return [:] }
        return [version.description: Set(contract.operations.map(\.id))]
    }()
}

public enum CompatibilityCatalogError: Error, Equatable, Sendable {
    case duplicateRuntimeVersion(String)
    case emptyCatalog
    case invalidAppVersionRange(String)
    case invalidAttestation(String)
    case invalidCapabilitySet(String)
    case invalidPackageIdentity(String)
    case invalidProbeSet(String)
    case invalidRuntimeVersion(String)
    case invalidSchema
    case invalidUpgradeSource(String)
    case malformed
    case remoteAuthorityForbidden
    case resourceMissing
    case unsortedRuntimeVersions
}

struct SemanticVersion: Comparable, CustomStringConvertible, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ value: String) throws {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2])
        else {
            throw CompatibilityCatalogError.invalidRuntimeVersion(value)
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
