import CryptoKit
import Foundation

public struct TrustedAttestationSigner: Codable, Equatable, Sendable {
    public let keyID: String
    public let publicKeyDERBase64: String
    public let publicKeySHA256: String

    public init(keyID: String, publicKeyDERBase64: String, publicKeySHA256: String) {
        self.keyID = keyID
        self.publicKeyDERBase64 = publicKeyDERBase64
        self.publicKeySHA256 = publicKeySHA256
    }

    public func validated() throws -> Self {
        guard !keyID.isEmpty,
              let keyData = Data(base64Encoded: publicKeyDERBase64),
              (try? P256.Signing.PublicKey(derRepresentation: keyData)) != nil,
              Self.hexSHA256(keyData) == publicKeySHA256
        else {
            throw AttestationVerificationError.trustedSignerConfigurationInvalid
        }
        return self
    }

    public func replacing(publicKeySHA256: String) -> Self {
        Self(
            keyID: keyID,
            publicKeyDERBase64: publicKeyDERBase64,
            publicKeySHA256: publicKeySHA256
        )
    }

    fileprivate var publicKey: P256.Signing.PublicKey? {
        Data(base64Encoded: publicKeyDERBase64)
            .flatMap { try? P256.Signing.PublicKey(derRepresentation: $0) }
    }

    private static func hexSHA256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct TrustedAttestationSignerConfiguration: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let signers: [TrustedAttestationSigner]

    public init(schemaVersion: Int, signers: [TrustedAttestationSigner]) {
        self.schemaVersion = schemaVersion
        self.signers = signers
    }

    public static func bundled() throws -> Self {
        guard let url = Bundle.module.url(
            forResource: "trusted-attestation-signers",
            withExtension: "json"
        ) else {
            throw AttestationVerificationError.trustedSignerConfigurationInvalid
        }
        return try decode(Data(contentsOf: url, options: [.mappedIfSafe]))
    }

    public static func decode(_ data: Data) throws -> Self {
        do {
            let value = try JSONDecoder().decode(Self.self, from: data)
            guard value.schemaVersion == 1,
                  !value.signers.isEmpty,
                  Set(value.signers.map(\.keyID)).count == value.signers.count
            else {
                throw AttestationVerificationError.trustedSignerConfigurationInvalid
            }
            for signer in value.signers {
                _ = try signer.validated()
            }
            return value
        } catch let error as AttestationVerificationError {
            throw error
        } catch {
            throw AttestationVerificationError.trustedSignerConfigurationInvalid
        }
    }
}

public protocol AttestationReplayChecking: Sendable {
    func accept(nonce: UUID, issuedAt: Date) async throws -> Bool
}

public actor InMemoryAttestationReplayStore: AttestationReplayChecking {
    private var accepted = Set<UUID>()

    public init() {}

    public func accept(nonce: UUID, issuedAt _: Date) -> Bool {
        accepted.insert(nonce).inserted
    }
}

public struct AttestationVerifier: Sendable {
    private let trustedSigners: [String: TrustedAttestationSigner]
    private let replayStore: any AttestationReplayChecking

    public init(
        trustedSigners: [TrustedAttestationSigner],
        replayStore: any AttestationReplayChecking
    ) {
        self.trustedSigners = Dictionary(uniqueKeysWithValues: trustedSigners.map { ($0.keyID, $0) })
        self.replayStore = replayStore
    }

    public func verify(
        _ attestation: PhysicalTestAttestation,
        expectations: PhysicalAttestationExpectations
    ) async throws {
        try verifySignature(attestation)
        try verifyFreshness(attestation, expectations: expectations)
        try verifyIdentity(attestation, expectations: expectations)
        try verifyResults(attestation, expectations: expectations)
        guard try await replayStore.accept(nonce: attestation.nonce, issuedAt: attestation.issuedAt) else {
            throw AttestationVerificationError.replayedNonce
        }
    }

    private func verifySignature(_ attestation: PhysicalTestAttestation) throws {
        guard attestation.schemaVersion == 1 else {
            throw AttestationVerificationError.unsupportedSchema
        }
        guard let signer = trustedSigners[attestation.signerKeyID] else {
            throw AttestationVerificationError.untrustedSigner
        }
        let validatedSigner = try signer.validated()
        guard let publicKey = validatedSigner.publicKey,
              let signatureData = Data(base64Encoded: attestation.signature),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureData),
              try publicKey.isValidSignature(signature, for: attestation.canonicalSigningData())
        else {
            throw AttestationVerificationError.invalidSignature
        }
    }

    private func verifyFreshness(
        _ attestation: PhysicalTestAttestation,
        expectations: PhysicalAttestationExpectations
    ) throws {
        guard attestation.issuedAt <= expectations.now.addingTimeInterval(expectations.futureTolerance) else {
            throw AttestationVerificationError.invalidIssueTime
        }
        guard expectations.now.timeIntervalSince(attestation.issuedAt) <= expectations.maximumAge else {
            throw AttestationVerificationError.expired
        }
    }

    private func verifyIdentity(
        _ attestation: PhysicalTestAttestation,
        expectations: PhysicalAttestationExpectations
    ) throws {
        guard attestation.sourceCommit == expectations.sourceCommit else {
            throw AttestationVerificationError.sourceCommitMismatch
        }
        guard attestation.appBundleIdentifier == expectations.appBundleIdentifier,
              attestation.appVersion == expectations.appVersion,
              attestation.appBuild == expectations.appBuild,
              attestation.appDesignatedRequirementHash == expectations.appDesignatedRequirementHash
        else {
            throw AttestationVerificationError.appIdentityMismatch
        }
        guard attestation.runtimeVersion == expectations.runtimeVersion,
              attestation.runtimePackageSHA256 == expectations.runtimePackageSHA256
        else {
            throw AttestationVerificationError.runtimeIdentityMismatch
        }
        guard attestation.testPlanVersion == expectations.testPlanVersion else {
            throw AttestationVerificationError.testPlanMismatch
        }
        guard !attestation.hostModel.isEmpty, !attestation.macOSBuild.isEmpty else {
            throw AttestationVerificationError.hostIdentityMissing
        }
    }

    private func verifyResults(
        _ attestation: PhysicalTestAttestation,
        expectations: PhysicalAttestationExpectations
    ) throws {
        guard expectations.requiredOperationIDs.isSubset(of: attestation.operationResults.keys),
              attestation.operationResults.values.allSatisfy(\.self)
        else {
            throw AttestationVerificationError.operationFailed
        }
        guard attestation.residueCount == 0 else {
            throw AttestationVerificationError.residueDetected
        }
        guard attestation.baselineRestored, attestation.cleanupLedgerEmpty else {
            throw AttestationVerificationError.cleanupIncomplete
        }
    }
}

public enum AttestationVerificationError: String, Error, Equatable, Sendable {
    case appIdentityMismatch
    case cleanupIncomplete
    case expired
    case hostIdentityMissing
    case invalidIssueTime
    case invalidSignature
    case malformed
    case operationFailed
    case replayedNonce
    case replayStoreCorrupt
    case replayStoreUnsafe
    case residueDetected
    case runtimeIdentityMismatch
    case sourceCommitMismatch
    case testPlanMismatch
    case trustedSignerConfigurationInvalid
    case unsupportedSchema
    case untrustedSigner
}
