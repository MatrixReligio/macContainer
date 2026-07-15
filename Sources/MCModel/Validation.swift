public enum ValidationSeverity: Int, Codable, Comparable, Sendable {
    case error = 0
    case warning = 1
    case information = 2

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct ValidationIssue: Codable, Equatable, Comparable, Sendable {
    public let parameterID: String
    public let severity: ValidationSeverity
    public let messageKey: String
    public let recoveryKey: String?

    public init(
        parameterID: String,
        severity: ValidationSeverity,
        messageKey: String,
        recoveryKey: String? = nil
    ) {
        self.parameterID = parameterID
        self.severity = severity
        self.messageKey = messageKey
        self.recoveryKey = recoveryKey
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.severity, lhs.parameterID, lhs.messageKey) <
            (rhs.severity, rhs.parameterID, rhs.messageKey)
    }
}
