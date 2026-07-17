import CryptoKit
import Foundation
@testable import MCCompatibility
import Testing

@Suite("Signed physical compatibility attestations")
struct AttestationVerifierTests {
    @Test func `valid exact attestation is accepted once`() async throws {
        let fixture = try AttestationFixture()
        let attestation = try fixture.signed()

        try await fixture.verifier.verify(attestation, expectations: fixture.expectations)
        await #expect(throws: AttestationVerificationError.replayedNonce) {
            try await fixture.verifier.verify(attestation, expectations: fixture.expectations)
        }
    }

    @Test func `wrong signer and altered signature fail before acceptance`() async throws {
        let fixture = try AttestationFixture()
        let otherKey = P256.Signing.PrivateKey()
        let untrusted = try fixture.signed(key: otherKey, signerKeyID: "other")
        await #expect(throws: AttestationVerificationError.untrustedSigner) {
            try await fixture.verifier.verify(untrusted, expectations: fixture.expectations)
        }

        let valid = try fixture.signed()
        let altered = valid.replacing(signature: Data("not-a-signature".utf8).base64EncodedString())
        await #expect(throws: AttestationVerificationError.invalidSignature) {
            try await fixture.verifier.verify(altered, expectations: fixture.expectations)
        }
    }

    @Test func `source app runtime and test plan must match exactly`() async throws {
        for mismatch in AttestationMismatch.identityCases {
            let fixture = try AttestationFixture()
            let attestation = try fixture.signed(mismatch: mismatch)
            await #expect(throws: mismatch.expectedError) {
                try await fixture.verifier.verify(attestation, expectations: fixture.expectations)
            }
        }
    }

    @Test func `failed operation residue and incomplete cleanup are rejected`() async throws {
        for mismatch in AttestationMismatch.cleanupCases {
            let fixture = try AttestationFixture()
            let attestation = try fixture.signed(mismatch: mismatch)
            await #expect(throws: mismatch.expectedError) {
                try await fixture.verifier.verify(attestation, expectations: fixture.expectations)
            }
        }
    }

    @Test func `expired and future attestations are rejected`() async throws {
        let expired = try AttestationFixture(issuedAt: Date(timeIntervalSince1970: 100))
        await #expect(throws: AttestationVerificationError.expired) {
            try await expired.verifier.verify(expired.signed(), expectations: expired.expectations)
        }

        let future = try AttestationFixture(issuedAt: Date(timeIntervalSince1970: 2_000_400))
        await #expect(throws: AttestationVerificationError.invalidIssueTime) {
            try await future.verifier.verify(future.signed(), expectations: future.expectations)
        }
    }

    @Test func `trusted signer configuration verifies its own key hash`() throws {
        let fixture = try AttestationFixture()
        #expect(try fixture.signer.validated().keyID == "physical-test-fixture")
        #expect(throws: AttestationVerificationError.trustedSignerConfigurationInvalid) {
            _ = try fixture.signer.replacing(publicKeySHA256: String(repeating: "0", count: 64)).validated()
        }
    }

    @Test func `bundled signer is immutable and cryptographically self consistent`() throws {
        let configuration = try TrustedAttestationSignerConfiguration.bundled()
        #expect(configuration.signers.map(\.keyID) == ["matrixreligio-physical-2026-07"])
        #expect(try configuration.signers[0].validated() == configuration.signers[0])
    }

    @Test func `persistent replay store survives reopen and rejects redirection`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "attestation-replay-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "nonces.json")
        let nonce = UUID()
        let issuedAt = Date(timeIntervalSince1970: 123)

        #expect(try await PersistentAttestationReplayStore(fileURL: file).accept(
            nonce: nonce,
            issuedAt: issuedAt
        ))
        #expect(try await PersistentAttestationReplayStore(fileURL: file).accept(
            nonce: nonce,
            issuedAt: issuedAt
        ) == false)
        let mode = try #require(FileManager.default
            .attributesOfItem(atPath: file.path)[.posixPermissions] as? Int)
        #expect(mode == 0o600)

        let redirected = root.appending(path: "redirected.json")
        try FileManager.default.createSymbolicLink(at: redirected, withDestinationURL: file)
        await #expect(throws: AttestationVerificationError.replayStoreUnsafe) {
            _ = try await PersistentAttestationReplayStore(fileURL: redirected).accept(
                nonce: UUID(),
                issuedAt: issuedAt
            )
        }
    }
}

private struct AttestationFixture {
    let privateKey = P256.Signing.PrivateKey()
    let signer: TrustedAttestationSigner
    let expectations: PhysicalAttestationExpectations
    let verifier: AttestationVerifier
    let issuedAt: Date

    init(issuedAt: Date = Date(timeIntervalSince1970: 1_999_000)) throws {
        self.issuedAt = issuedAt
        let publicDER = privateKey.publicKey.derRepresentation
        signer = TrustedAttestationSigner(
            keyID: "physical-test-fixture",
            publicKeyDERBase64: publicDER.base64EncodedString(),
            publicKeySHA256: SHA256.hash(data: publicDER).map { String(format: "%02x", $0) }.joined()
        )
        expectations = PhysicalAttestationExpectations(
            sourceCommit: "5973b9cc626a3e7a499bb316a958237ebe14e2ed",
            appBundleIdentifier: "container.matrixreligio.com",
            appVersion: "0.1.0",
            appBuild: "1",
            appDesignatedRequirementHash: String(repeating: "a", count: 64),
            runtimeVersion: "1.1.0",
            runtimePackageSHA256: "0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714",
            testPlanVersion: "physical-v1",
            requiredOperationIDs: ["install", "upgrade", "uninstall"],
            now: Date(timeIntervalSince1970: 2_000_000),
            maximumAge: 3600,
            futureTolerance: 300
        )
        verifier = AttestationVerifier(
            trustedSigners: [signer],
            replayStore: InMemoryAttestationReplayStore()
        )
    }

    func signed(
        mismatch: AttestationMismatch? = nil,
        key: P256.Signing.PrivateKey? = nil,
        signerKeyID: String = "physical-test-fixture"
    ) throws -> PhysicalTestAttestation {
        let base = PhysicalTestAttestation(
            schemaVersion: 1,
            nonce: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            issuedAt: issuedAt,
            sourceCommit: mismatch == .sourceCommit ? String(repeating: "b", count: 40) : expectations.sourceCommit,
            appBundleIdentifier: mismatch == .appBundle ? "invalid.example" : expectations.appBundleIdentifier,
            appVersion: mismatch == .appVersion ? "9.9.9" : expectations.appVersion,
            appBuild: mismatch == .appBuild ? "999" : expectations.appBuild,
            appDesignatedRequirementHash: mismatch == .appIdentity
                ? String(repeating: "b", count: 64) : expectations.appDesignatedRequirementHash,
            runtimeVersion: mismatch == .runtimeVersion ? "9.9.9" : expectations.runtimeVersion,
            runtimePackageSHA256: mismatch == .runtimeDigest
                ? String(repeating: "0", count: 64) : expectations.runtimePackageSHA256,
            testPlanVersion: mismatch == .testPlan ? "physical-v999" : expectations.testPlanVersion,
            hostModel: "Mac16,6",
            macOSBuild: "25F70",
            operationResults: mismatch == .failedOperation
                ? ["install": true, "upgrade": false, "uninstall": true]
                : ["install": true, "upgrade": true, "uninstall": true],
            residueCount: mismatch == .residue ? 1 : 0,
            baselineRestored: mismatch != .baseline,
            cleanupLedgerEmpty: mismatch != .ledger,
            signerKeyID: signerKeyID,
            signature: ""
        )
        let signingKey = key ?? privateKey
        let signature = try signingKey.signature(for: base.canonicalSigningData()).derRepresentation
        return base.replacing(signature: signature.base64EncodedString())
    }
}

private enum AttestationMismatch: CaseIterable, Equatable {
    case sourceCommit
    case appBundle
    case appVersion
    case appBuild
    case appIdentity
    case runtimeVersion
    case runtimeDigest
    case testPlan
    case failedOperation
    case residue
    case baseline
    case ledger

    static let identityCases: [Self] = [
        .sourceCommit, .appBundle, .appVersion, .appBuild, .appIdentity,
        .runtimeVersion, .runtimeDigest, .testPlan
    ]
    static let cleanupCases: [Self] = [.failedOperation, .residue, .baseline, .ledger]

    var expectedError: AttestationVerificationError {
        switch self {
        case .sourceCommit: .sourceCommitMismatch
        case .appBundle, .appVersion, .appBuild, .appIdentity: .appIdentityMismatch
        case .runtimeVersion, .runtimeDigest: .runtimeIdentityMismatch
        case .testPlan: .testPlanMismatch
        case .failedOperation: .operationFailed
        case .residue: .residueDetected
        case .baseline, .ledger: .cleanupIncomplete
        }
    }
}
