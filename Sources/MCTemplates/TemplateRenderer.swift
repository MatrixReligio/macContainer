import MCContracts
import MCModel

public struct TemplateReview: Equatable, Sendable {
    public let draft: OperationDraft
    public let rows: [TemplateReviewRow]
    public let diffFromUpstream: [TemplateReviewRow]

    public init(
        draft: OperationDraft,
        rows: [TemplateReviewRow],
        diffFromUpstream: [TemplateReviewRow]
    ) {
        self.draft = draft
        self.rows = rows
        self.diffFromUpstream = diffFromUpstream
    }
}

public struct TemplateReviewRow: Identifiable, Equatable, Sendable {
    public var id: String {
        parameterID
    }

    public let parameterID: String
    public let value: FieldValue
    public let source: ValueSource
    public let sourceDescriptionKey: String
    public let upstreamDefault: ParameterValue?

    public init(
        parameterID: String,
        value: FieldValue,
        source: ValueSource,
        sourceDescriptionKey: String,
        upstreamDefault: ParameterValue?
    ) {
        self.parameterID = parameterID
        self.value = value
        self.source = source
        self.sourceDescriptionKey = sourceDescriptionKey
        self.upstreamDefault = upstreamDefault
    }
}

public enum TemplateRendererError: Error, Equatable, Sendable {
    case operationNotFound(String)
    case unknownParameter(templateID: String, parameterID: String)
    case draftOperationMismatch(expected: String, actual: String)
}

public struct TemplateRenderer: Sendable {
    private let contract: UpstreamContract

    public init(contract: UpstreamContract) {
        self.contract = contract
    }

    public func render(template: ScenarioTemplate, context: TemplateContext) throws -> TemplateReview {
        guard let operation = contract.operation(id: template.operationID) else {
            throw TemplateRendererError.operationNotFound(template.operationID)
        }
        let draft = try template.render(context)
        guard draft.operationID == template.operationID else {
            throw TemplateRendererError.draftOperationMismatch(
                expected: template.operationID,
                actual: draft.operationID
            )
        }

        let parameterIDs = Set(operation.parameters.map(\.id))
        if let unknown = draft.fields.keys.filter({ !parameterIDs.contains($0) }).min() {
            throw TemplateRendererError.unknownParameter(templateID: template.id, parameterID: unknown)
        }

        let rows = operation.parameters.compactMap { parameter -> TemplateReviewRow? in
            guard let field = draft.fields[parameter.id] else {
                return nil
            }
            return TemplateReviewRow(
                parameterID: parameter.id,
                value: field.value,
                source: field.source,
                sourceDescriptionKey: field.source.descriptionKey,
                upstreamDefault: parameter.upstreamDefault
            )
        }
        let diff = rows.filter { row in
            normalized(row.value) != row.upstreamDefault
        }
        return TemplateReview(draft: draft, rows: rows, diffFromUpstream: diff)
    }

    private func normalized(_ value: FieldValue) -> ParameterValue? {
        switch value {
        case let .bool(value):
            .boolean(value)
        case let .integer(value), let .bytes(value):
            .integer(value)
        case let .duration(value):
            .integer(value.seconds)
        case let .string(value), let .path(value), let .secret(value):
            .string(value)
        case let .strings(values):
            .strings(values)
        case let .keyValues(values):
            .strings(values.map { "\($0.key)=\($0.value)" })
        case let .portMappings(values):
            .strings(values.map(\.description))
        case let .mounts(values):
            .strings(values.map(\.description))
        case .none:
            nil
        }
    }
}

private extension ValueSource {
    var descriptionKey: String {
        switch self {
        case .upstreamDefault:
            "value.source.upstream"
        case .scenarioRule:
            "value.source.scenario"
        case .hostRecommendation:
            "value.source.host"
        case .imageMetadata:
            "value.source.image"
        case .userOverride:
            "value.source.user"
        }
    }
}
