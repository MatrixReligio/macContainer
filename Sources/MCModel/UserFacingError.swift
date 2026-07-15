public struct UserFacingError: Error, Codable, Equatable, Sendable {
    public let code: String
    public let messageKey: String
    public let recoveryKey: String?
    public let redactedDetails: String?

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
    }
}
