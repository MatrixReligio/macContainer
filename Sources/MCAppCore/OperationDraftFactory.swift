import MCContracts
import MCModel

public struct OperationDraftFactory: Sendable {
    public init() {}

    public func makeDraft(for operation: OperationContract) -> OperationDraft {
        let fields = operation.parameters.reduce(into: [String: DraftField]()) { result, parameter in
            result[parameter.id] = DraftField(
                value: initialValue(for: parameter),
                source: parameter.upstreamDefault == nil ? .userOverride : .upstreamDefault
            )
        }
        return OperationDraft(operationID: operation.id, fields: fields)
    }

    // The exhaustive switch intentionally mirrors every persisted upstream default representation.
    // swiftlint:disable:next cyclomatic_complexity
    private func initialValue(for parameter: ParameterContract) -> FieldValue {
        guard let value = parameter.upstreamDefault else { return .none }
        switch value {
        case let .boolean(boolean):
            return .bool(boolean)
        case let .integer(integer) where parameter.valueType == .bytes:
            return .bytes(integer)
        case let .integer(integer) where parameter.valueType == .duration:
            return .duration(.seconds(integer))
        case let .integer(integer):
            return .integer(integer)
        case let .string(string) where parameter.valueType == .path:
            return .path(string)
        case let .string(string):
            return .string(string)
        case let .strings(strings) where parameter.valueType == .keyValue:
            return .keyValues(strings.compactMap(parseKeyValue))
        case .strings where parameter.valueType == .portMapping:
            return .portMappings([])
        case .strings where parameter.valueType == .mount:
            return .mounts([])
        case let .strings(strings):
            return .strings(strings)
        }
    }

    private func parseKeyValue(_ value: String) -> KeyValue? {
        let parts = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard let key = parts.first, key.isEmpty == false else { return nil }
        return KeyValue(key: String(key), value: parts.count == 2 ? String(parts[1]) : "")
    }
}
