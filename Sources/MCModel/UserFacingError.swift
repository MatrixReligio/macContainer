import Foundation

public enum UserFacingErrorDomain: String, Codable, CaseIterable, Sendable {
    case container
    case image
    case build
    case machine
    case network
    case volume
    case registry
    case system
    case lifecycle
    case compatibility
    case helper
    case unknown
}

public struct ErrorRecoveryAction: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let titleKey: String
    public let isDestructive: Bool

    public init(id: String, titleKey: String, isDestructive: Bool = false) {
        self.id = id
        self.titleKey = titleKey
        self.isDestructive = isDestructive
    }
}

public struct UserFacingError: Error, Codable, Equatable, Sendable {
    public let code: String
    public let messageKey: String
    public let recoveryKey: String?
    public let redactedDetails: String?

    public let domain: UserFacingErrorDomain
    public let operationID: String
    public let titleKey: String
    public let explanationKey: String
    public let diagnosticDetail: String
    public let retryIsSafe: Bool
    public let recoveryActions: [ErrorRecoveryAction]
    public let activityID: UUID?
    public let timestamp: Date

    public init(
        code: String,
        messageKey: String,
        recoveryKey: String? = nil,
        redactedDetails: String? = nil
    ) {
        self.code = code
        self.messageKey = messageKey
        self.recoveryKey = recoveryKey
        self.redactedDetails = redactedDetails
        domain = .unknown
        operationID = ""
        titleKey = messageKey
        explanationKey = messageKey
        diagnosticDetail = redactedDetails ?? ""
        retryIsSafe = false
        recoveryActions = recoveryKey.map {
            [ErrorRecoveryAction(id: "legacy-recovery", titleKey: $0)]
        } ?? []
        activityID = nil
        timestamp = Date(timeIntervalSince1970: 0)
    }

    public init(
        code: String,
        domain: UserFacingErrorDomain,
        operationID: String,
        titleKey: String,
        explanationKey: String,
        diagnosticDetail: String,
        retryIsSafe: Bool,
        recoveryActions: [ErrorRecoveryAction],
        activityID: UUID? = nil,
        timestamp: Date
    ) {
        self.code = code
        self.domain = domain
        self.operationID = operationID
        self.titleKey = titleKey
        self.explanationKey = explanationKey
        self.diagnosticDetail = diagnosticDetail
        self.retryIsSafe = retryIsSafe
        self.recoveryActions = recoveryActions
        self.activityID = activityID
        self.timestamp = timestamp

        messageKey = explanationKey
        recoveryKey = recoveryActions.first?.titleKey
        redactedDetails = diagnosticDetail
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case messageKey
        case recoveryKey
        case redactedDetails
        case domain
        case operationID
        case titleKey
        case explanationKey
        case diagnosticDetail
        case retryIsSafe
        case recoveryActions
        case activityID
        case timestamp
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        messageKey = try container.decode(String.self, forKey: .messageKey)
        recoveryKey = try container.decodeIfPresent(String.self, forKey: .recoveryKey)
        redactedDetails = try container.decodeIfPresent(String.self, forKey: .redactedDetails)
        domain = try container.decodeIfPresent(UserFacingErrorDomain.self, forKey: .domain) ?? .unknown
        operationID = try container.decodeIfPresent(String.self, forKey: .operationID) ?? ""
        titleKey = try container.decodeIfPresent(String.self, forKey: .titleKey) ?? messageKey
        explanationKey = try container.decodeIfPresent(String.self, forKey: .explanationKey) ?? messageKey
        diagnosticDetail = try container.decodeIfPresent(String.self, forKey: .diagnosticDetail) ??
            redactedDetails ?? ""
        retryIsSafe = try container.decodeIfPresent(Bool.self, forKey: .retryIsSafe) ?? false
        recoveryActions = try container.decodeIfPresent([ErrorRecoveryAction].self, forKey: .recoveryActions) ??
            recoveryKey.map { [ErrorRecoveryAction(id: "legacy-recovery", titleKey: $0)] } ?? []
        activityID = try container.decodeIfPresent(UUID.self, forKey: .activityID)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date(timeIntervalSince1970: 0)
    }
}
