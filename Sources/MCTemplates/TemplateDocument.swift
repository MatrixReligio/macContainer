import MCModel

public struct TemplateDocument: Codable, Identifiable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let id: String
    public var name: String
    public var operationID: String
    public var fields: [String: DraftField]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: String,
        name: String,
        operationID: String,
        fields: [String: DraftField]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.operationID = operationID
        self.fields = fields
    }
}
