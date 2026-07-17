import Foundation

public struct PhysicalTestAttestation: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let nonce: UUID
    public let issuedAt: Date
    public let sourceCommit: String
    public let appBundleIdentifier: String
    public let appVersion: String
    public let appBuild: String
    public let appDesignatedRequirementHash: String
    public let runtimeVersion: String
    public let runtimePackageSHA256: String
    public let testPlanVersion: String
    public let hostModel: String
    public let macOSBuild: String
    public let operationResults: [String: Bool]
    public let residueCount: Int
    public let baselineRestored: Bool
    public let cleanupLedgerEmpty: Bool
    public let signerKeyID: String
    public let signature: String

    public init(
        schemaVersion: Int,
        nonce: UUID,
        issuedAt: Date,
        sourceCommit: String,
        appBundleIdentifier: String,
        appVersion: String,
        appBuild: String,
        appDesignatedRequirementHash: String,
        runtimeVersion: String,
        runtimePackageSHA256: String,
        testPlanVersion: String,
        hostModel: String,
        macOSBuild: String,
        operationResults: [String: Bool],
        residueCount: Int,
        baselineRestored: Bool,
        cleanupLedgerEmpty: Bool,
        signerKeyID: String,
        signature: String
    ) {
        self.schemaVersion = schemaVersion
        self.nonce = nonce
        self.issuedAt = issuedAt
        self.sourceCommit = sourceCommit
        self.appBundleIdentifier = appBundleIdentifier
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.appDesignatedRequirementHash = appDesignatedRequirementHash
        self.runtimeVersion = runtimeVersion
        self.runtimePackageSHA256 = runtimePackageSHA256
        self.testPlanVersion = testPlanVersion
        self.hostModel = hostModel
        self.macOSBuild = macOSBuild
        self.operationResults = operationResults
        self.residueCount = residueCount
        self.baselineRestored = baselineRestored
        self.cleanupLedgerEmpty = cleanupLedgerEmpty
        self.signerKeyID = signerKeyID
        self.signature = signature
    }

    public static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Self.self, from: data)
        } catch {
            throw AttestationVerificationError.malformed
        }
    }

    public func encoded() throws -> Data {
        let encoder = Self.encoder()
        do {
            return try encoder.encode(self)
        } catch {
            throw AttestationVerificationError.malformed
        }
    }

    public func canonicalSigningData() throws -> Data {
        try replacing(signature: "").encoded()
    }

    public func replacing(signature: String) -> Self {
        Self(
            schemaVersion: schemaVersion,
            nonce: nonce,
            issuedAt: issuedAt,
            sourceCommit: sourceCommit,
            appBundleIdentifier: appBundleIdentifier,
            appVersion: appVersion,
            appBuild: appBuild,
            appDesignatedRequirementHash: appDesignatedRequirementHash,
            runtimeVersion: runtimeVersion,
            runtimePackageSHA256: runtimePackageSHA256,
            testPlanVersion: testPlanVersion,
            hostModel: hostModel,
            macOSBuild: macOSBuild,
            operationResults: operationResults,
            residueCount: residueCount,
            baselineRestored: baselineRestored,
            cleanupLedgerEmpty: cleanupLedgerEmpty,
            signerKeyID: signerKeyID,
            signature: signature
        )
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

public struct PhysicalAttestationExpectations: Equatable, Sendable {
    public let sourceCommit: String
    public let appBundleIdentifier: String
    public let appVersion: String
    public let appBuild: String
    public let appDesignatedRequirementHash: String
    public let runtimeVersion: String
    public let runtimePackageSHA256: String
    public let testPlanVersion: String
    public let requiredOperationIDs: Set<String>
    public let now: Date
    public let maximumAge: TimeInterval
    public let futureTolerance: TimeInterval

    public init(
        sourceCommit: String,
        appBundleIdentifier: String,
        appVersion: String,
        appBuild: String,
        appDesignatedRequirementHash: String,
        runtimeVersion: String,
        runtimePackageSHA256: String,
        testPlanVersion: String,
        requiredOperationIDs: Set<String>,
        now: Date,
        maximumAge: TimeInterval,
        futureTolerance: TimeInterval = 300
    ) {
        self.sourceCommit = sourceCommit
        self.appBundleIdentifier = appBundleIdentifier
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.appDesignatedRequirementHash = appDesignatedRequirementHash
        self.runtimeVersion = runtimeVersion
        self.runtimePackageSHA256 = runtimePackageSHA256
        self.testPlanVersion = testPlanVersion
        self.requiredOperationIDs = requiredOperationIDs
        self.now = now
        self.maximumAge = maximumAge
        self.futureTolerance = futureTolerance
    }
}
