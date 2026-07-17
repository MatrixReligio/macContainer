import CryptoKit
import Foundation
import MCCompatibility
import Security

public struct PhysicalAttestationMaterial: Sendable {
    public let attestationData: Data
    public let requiredOperationIDs: Set<String>

    public init(attestationData: Data, requiredOperationIDs: Set<String>) {
        self.attestationData = attestationData
        self.requiredOperationIDs = requiredOperationIDs
    }
}

public protocol PhysicalAttestationMaterialProviding: Sendable {
    func material(for entry: CompatibilityEntry) throws -> PhysicalAttestationMaterial?
}

private struct PhysicalAttestationPlanTest: Decodable {
    let id: String
}

private struct PhysicalAttestationPlan: Decodable {
    let schemaVersion: Int
    let tests: [PhysicalAttestationPlanTest]
}

public struct BundleAttestationMaterialProvider: PhysicalAttestationMaterialProviding, @unchecked Sendable {
    private let bundle: Bundle

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    public func material(for entry: CompatibilityEntry) throws -> PhysicalAttestationMaterial? {
        guard let attestationURL = resourceURL(
            name: "apple-container-\(entry.runtimeVersion)",
            extension: "json",
            subdirectory: "compatibility/attestations"
        ), let planURL = resourceURL(
            name: "physical-test-plan-v1",
            extension: "json",
            subdirectory: nil
        ) else {
            return nil
        }
        let plan = try JSONDecoder().decode(PhysicalAttestationPlan.self, from: Data(contentsOf: planURL))
        guard entry.attestation.testPlanVersion == "physical-v\(plan.schemaVersion)",
              plan.tests.isEmpty == false,
              Set(plan.tests.map(\.id)).count == plan.tests.count
        else {
            return nil
        }
        return try PhysicalAttestationMaterial(
            attestationData: Data(contentsOf: attestationURL, options: [.mappedIfSafe]),
            requiredOperationIDs: Set(plan.tests.map(\.id))
        )
    }

    private func resourceURL(name: String, extension: String, subdirectory: String?) -> URL? {
        bundle.url(forResource: name, withExtension: `extension`, subdirectory: subdirectory) ??
            bundle.url(forResource: name, withExtension: `extension`)
    }
}

public struct PhysicalAttestationApplicationIdentity: Equatable, Sendable {
    public let bundleIdentifier: String
    public let version: String
    public let build: String
    public let designatedRequirementHash: String

    public init(bundleIdentifier: String, version: String, build: String, designatedRequirementHash: String) {
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.build = build
        self.designatedRequirementHash = designatedRequirementHash
    }
}

public protocol PhysicalAppIdentityProviding: Sendable {
    func identity() throws -> PhysicalAttestationApplicationIdentity
}

public struct SystemPhysicalAppIdentityProvider: PhysicalAppIdentityProviding, Sendable {
    public init() {}

    public func identity() throws -> PhysicalAttestationApplicationIdentity {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else {
            throw PhysicalAppIdentityError.codeUnavailable
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode
        else {
            throw PhysicalAppIdentityError.codeUnavailable
        }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, SecCSFlags(), &requirement) == errSecSuccess,
              let requirement
        else {
            throw PhysicalAppIdentityError.requirementUnavailable
        }
        var requirementText: CFString?
        guard SecRequirementCopyString(requirement, SecCSFlags(), &requirementText) == errSecSuccess,
              let requirementText
        else {
            throw PhysicalAppIdentityError.requirementUnavailable
        }
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        else {
            throw PhysicalAppIdentityError.bundleIdentityUnavailable
        }
        let data = Data((requirementText as String).utf8)
        return PhysicalAttestationApplicationIdentity(
            bundleIdentifier: bundleIdentifier,
            version: version,
            build: build,
            designatedRequirementHash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }
}

public enum PhysicalAppIdentityError: Error, Equatable, Sendable {
    case bundleIdentityUnavailable
    case codeUnavailable
    case requirementUnavailable
}

public actor BundledPhysicalAttestationIDProvider: PhysicalAttestationIDProviding {
    public static let maximumAttestationAge: TimeInterval = 366 * 24 * 60 * 60

    private let materialProvider: any PhysicalAttestationMaterialProviding
    private let identityProvider: any PhysicalAppIdentityProviding
    private let configuredSigners: [TrustedAttestationSigner]?
    private let replayStore: any AttestationReplayChecking
    private let now: @Sendable () -> Date
    private var verifiedEntryIDs = Set<String>()

    public init(
        materialProvider: any PhysicalAttestationMaterialProviding = BundleAttestationMaterialProvider(),
        identityProvider: any PhysicalAppIdentityProviding = SystemPhysicalAppIdentityProvider(),
        trustedSigners: [TrustedAttestationSigner]? = nil,
        replayStore: any AttestationReplayChecking = InMemoryAttestationReplayStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.materialProvider = materialProvider
        self.identityProvider = identityProvider
        configuredSigners = trustedSigners
        self.replayStore = replayStore
        self.now = now
    }

    public func verifiedIDs(for entry: CompatibilityEntry) async -> Set<String> {
        if verifiedEntryIDs.contains(entry.attestation.id) {
            return [entry.attestation.id]
        }
        do {
            guard let material = try materialProvider.material(for: entry) else { return [] }
            let identity = try identityProvider.identity()
            let attestation = try PhysicalTestAttestation.decode(material.attestationData)
            let signers = try configuredSigners ?? TrustedAttestationSignerConfiguration.bundled().signers
            let expectations = PhysicalAttestationExpectations(
                sourceCommit: entry.attestation.sourceCommit,
                appBundleIdentifier: identity.bundleIdentifier,
                appVersion: identity.version,
                appBuild: identity.build,
                appDesignatedRequirementHash: identity.designatedRequirementHash,
                runtimeVersion: entry.runtimeVersion,
                runtimePackageSHA256: entry.package.sha256,
                testPlanVersion: entry.attestation.testPlanVersion,
                requiredOperationIDs: material.requiredOperationIDs,
                now: now(),
                maximumAge: Self.maximumAttestationAge
            )
            try await AttestationVerifier(
                trustedSigners: signers,
                replayStore: replayStore
            ).verify(attestation, expectations: expectations)
            verifiedEntryIDs.insert(entry.attestation.id)
            return [entry.attestation.id]
        } catch {
            return []
        }
    }
}
