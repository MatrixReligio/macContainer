import Foundation

public enum LifecycleKind: String, Codable, CaseIterable, Sendable {
    case install
    case upgrade
    case downgrade
    case rollback
    case uninstall
}

public enum LifecyclePhase: String, Codable, CaseIterable, Sendable {
    case began
    case intent
    case applied
    case verified
    case committed
    case rollingBack
    case rolledBack
    case failed

    public var isTerminal: Bool {
        self == .committed || self == .rolledBack || self == .failed
    }
}

public enum ResidueKind: String, Codable, CaseIterable, Sendable {
    case launchService
    case process
    case receipt
    case receiptPayload
    case applicationSupport
    case configuration
    case defaultsDomain
    case registryCredential
    case resolver
    case packetFilter
    case downloadedPackage
    case rollbackPoint
    case testFixture
    case downloadCache
    case runtimeOwnedDirectory
}

public struct RedactedLifecycleFailure: Codable, Equatable, Sendable {
    public let code: String
    public let redactedDetail: String

    public init(code: String, redactedDetail: String) {
        self.code = Self.sanitizeCode(code)
        self.redactedDetail = Self.sanitizeDetail(redactedDetail)
    }

    private static func sanitizeCode(_ value: String) -> String {
        let allowed = value.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "-" || scalar == "_"
        }
        let result = String(String.UnicodeScalarView(allowed)).prefix(96)
        return result.isEmpty ? "lifecycle.failed" : String(result)
    }

    private static func sanitizeDetail(_ value: String) -> String {
        let lowercased = value.lowercased()
        let sensitiveMarkers = [
            "password", "passwd", "secret", "credential", "authorization", "bearer ",
            "private key", "/private/var/folders/", "/var/folders/"
        ]
        guard !sensitiveMarkers.contains(where: lowercased.contains) else {
            return "<redacted>"
        }

        let singleLine = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return String(singleLine.prefix(512))
    }
}

public enum LifecycleAction: Codable, Equatable, Sendable {
    case cleanStaging
    case installPackage(digest: String)
    case retainRollbackPoint(identifier: UUID)
    case stopServices(labels: [String])
    case removePayload(manifestID: String)
    case removeReceipt(identifier: String)
    case removeUserArtifact(kind: ResidueKind)
    case restoreRollbackPoint(identifier: UUID)
}

public struct LifecycleEvent: Codable, Equatable, Sendable {
    public let sequence: UInt64
    public let transactionID: UUID
    public let kind: LifecycleKind
    public let phase: LifecyclePhase
    public let targetVersion: String?
    public let action: LifecycleAction?
    public let failure: RedactedLifecycleFailure?
    public let timestamp: Date

    public init(
        sequence: UInt64,
        transactionID: UUID,
        kind: LifecycleKind,
        phase: LifecyclePhase,
        targetVersion: String?,
        action: LifecycleAction?,
        failure: RedactedLifecycleFailure?,
        timestamp: Date
    ) {
        self.sequence = sequence
        self.transactionID = transactionID
        self.kind = kind
        self.phase = phase
        self.targetVersion = targetVersion
        self.action = action
        self.failure = failure
        self.timestamp = timestamp
    }
}
