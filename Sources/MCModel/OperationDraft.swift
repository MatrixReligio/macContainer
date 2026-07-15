public struct OperationDraft: Codable, Equatable, Sendable {
    public let operationID: String
    public var fields: [String: DraftField]

    public init(operationID: String, fields: [String: DraftField]) {
        self.operationID = operationID
        self.fields = fields
    }
}

public struct DraftField: Codable, Equatable, Sendable {
    public var value: FieldValue
    public var source: ValueSource

    public init(value: FieldValue, source: ValueSource) {
        self.value = value
        self.source = source
    }
}

public enum ValueSource: String, Codable, CaseIterable, Hashable, Sendable {
    case upstreamDefault
    case scenarioRule
    case hostRecommendation
    case imageMetadata
    case userOverride
}
