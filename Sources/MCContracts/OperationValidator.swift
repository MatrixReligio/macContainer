import Foundation
import MCModel

public struct OperationValidator: Sendable {
    public struct Context: Equatable, Sendable {
        public let runtimeVersion: RuntimeVersion
        public let macOSMajor: Int
        public let isAppleSilicon: Bool
        public let capabilities: Set<String>

        public init(
            runtimeVersion: RuntimeVersion,
            macOSMajor: Int,
            isAppleSilicon: Bool,
            capabilities: Set<String>
        ) {
            self.runtimeVersion = runtimeVersion
            self.macOSMajor = macOSMajor
            self.isAppleSilicon = isAppleSilicon
            self.capabilities = capabilities
        }
    }

    public init() {}

    public func validate(
        _ draft: OperationDraft,
        against operation: OperationContract,
        context: Context? = nil
    ) -> [ValidationIssue] {
        let parameters = Dictionary(uniqueKeysWithValues: operation.parameters.map { ($0.id, $0) })
        var issues = operationIssues(draft: draft, operation: operation, parameters: parameters)
        var typeCompatibleFieldIDs = Set<String>()

        for parameter in operation.parameters {
            guard let field = draft.fields[parameter.id], field.value.isProvided else {
                if parameter.required {
                    issues.append(issue(parameter, messageKey: "validation.required"))
                }
                continue
            }

            guard isCompatible(field.value, with: parameter) else {
                issues.append(issue(parameter, messageKey: "validation.type"))
                continue
            }

            typeCompatibleFieldIDs.insert(parameter.id)
            issues.append(contentsOf: rangeIssues(field.value, parameter: parameter))
            issues.append(contentsOf: grammarIssues(field.value, parameter: parameter))
        }

        issues.append(contentsOf: dependencyIssues(
            draft: draft,
            operation: operation,
            parameters: parameters,
            validFieldIDs: typeCompatibleFieldIDs
        ))
        issues.append(contentsOf: conflictIssues(
            draft: draft,
            operation: operation,
            validFieldIDs: typeCompatibleFieldIDs
        ))
        issues.append(contentsOf: rosettaIssues(draft: draft, validFieldIDs: typeCompatibleFieldIDs))

        if let context {
            issues.append(contentsOf: availabilityIssues(
                draft: draft,
                operation: operation,
                context: context,
                validFieldIDs: typeCompatibleFieldIDs
            ))
        }

        return issues.sorted()
    }

    private func operationIssues(
        draft: OperationDraft,
        operation: OperationContract,
        parameters: [String: ParameterContract]
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if draft.operationID != operation.id {
            issues.append(ValidationIssue(
                parameterID: draft.operationID,
                severity: .error,
                messageKey: "validation.operation.mismatch"
            ))
        }
        for fieldID in draft.fields.keys.sorted() where parameters[fieldID] == nil {
            issues.append(ValidationIssue(
                parameterID: fieldID,
                severity: .error,
                messageKey: "validation.parameter.unknown"
            ))
        }
        return issues
    }

    private func rangeIssues(_ value: FieldValue, parameter: ParameterContract) -> [ValidationIssue] {
        let isNegative = switch value {
        case let .integer(number), let .bytes(number): number < 0
        case let .duration(duration): duration.seconds < 0
        default: false
        }
        guard isNegative else {
            return []
        }
        return [issue(parameter, messageKey: "validation.range.nonnegative")]
    }

    private func grammarIssues(_ value: FieldValue, parameter: ParameterContract) -> [ValidationIssue] {
        guard let grammar = parameter.grammar else {
            return []
        }
        guard let expression = try? NSRegularExpression(pattern: grammar) else {
            return [issue(parameter, messageKey: "validation.contract.grammar")]
        }
        let invalid = value.validationStrings.contains { candidate in
            let range = NSRange(candidate.startIndex ..< candidate.endIndex, in: candidate)
            guard let match = expression.firstMatch(in: candidate, range: range) else {
                return true
            }
            return match.range != range
        }
        return invalid ? [issue(parameter, messageKey: "validation.grammar")] : []
    }

    private func dependencyIssues(
        draft: OperationDraft,
        operation: OperationContract,
        parameters: [String: ParameterContract],
        validFieldIDs: Set<String>
    ) -> [ValidationIssue] {
        operation.parameters.compactMap { parameter in
            guard
                validFieldIDs.contains(parameter.id),
                draft.fields[parameter.id]?.value.isActive == true,
                parameter.dependencies.contains(where: {
                    !dependencyIsSatisfied($0, draft: draft, parameters: parameters)
                })
            else {
                return nil
            }
            return issue(parameter, messageKey: "validation.dependency")
        }
    }

    private func dependencyIsSatisfied(
        _ dependency: String,
        draft: OperationDraft,
        parameters: [String: ParameterContract]
    ) -> Bool {
        let components = dependency.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let parameterID = String(components[0])
        guard let parameter = parameters[parameterID] else {
            return false
        }
        let value = effectiveValue(for: parameter, draft: draft)
        guard components.count == 2 else {
            return value?.isActive == true
        }
        return value?.dependencyValue == String(components[1])
    }

    private func effectiveValue(for parameter: ParameterContract, draft: OperationDraft) -> FieldValue? {
        if let value = draft.fields[parameter.id]?.value, value.isProvided {
            return value
        }
        guard let upstreamDefault = parameter.upstreamDefault else {
            return nil
        }
        return FieldValue(upstreamDefault: upstreamDefault, valueType: parameter.valueType)
    }

    private func conflictIssues(
        draft: OperationDraft,
        operation: OperationContract,
        validFieldIDs: Set<String>
    ) -> [ValidationIssue] {
        var seenPairs = Set<String>()
        var issues: [ValidationIssue] = []
        for parameter in operation.parameters where validFieldIDs.contains(parameter.id) {
            guard draft.fields[parameter.id]?.value.isActive == true else {
                continue
            }
            for conflictID in parameter.conflicts where draft.fields[conflictID]?.value.isActive == true {
                let pair = [parameter.id, conflictID].sorted().joined(separator: "\u{0}")
                guard seenPairs.insert(pair).inserted else {
                    continue
                }
                issues.append(issue(parameter, messageKey: "validation.conflict"))
            }
        }
        return issues
    }

    private func rosettaIssues(draft: OperationDraft, validFieldIDs: Set<String>) -> [ValidationIssue] {
        guard
            validFieldIDs.contains("rosetta"),
            draft.fields["rosetta"]?.value == .bool(true),
            draft.fields["platform"]?.value != .string("linux/amd64")
        else {
            return []
        }
        return [ValidationIssue(
            parameterID: "rosetta",
            severity: .error,
            messageKey: "validation.rosetta.platform"
        )]
    }

    private func availabilityIssues(
        draft: OperationDraft,
        operation: OperationContract,
        context: Context,
        validFieldIDs: Set<String>
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        for parameter in operation.parameters where validFieldIDs.contains(parameter.id) {
            guard draft.fields[parameter.id]?.value.isActive == true else {
                continue
            }
            let availability = parameter.availability
            if context.runtimeVersion < availability.minimumRuntime {
                issues.append(issue(parameter, messageKey: "validation.availability.runtime"))
            }
            if context.macOSMajor < availability.minimumMacOSMajor {
                issues.append(issue(parameter, messageKey: "validation.availability.macos"))
            }
            if availability.requiresAppleSilicon, !context.isAppleSilicon {
                issues.append(issue(parameter, messageKey: "validation.availability.architecture"))
            }
            if !Set(availability.requiredCapabilities).isSubset(of: context.capabilities) {
                issues.append(issue(parameter, messageKey: "validation.availability.capability"))
            }
        }
        return issues
    }

    private func isCompatible(_ value: FieldValue, with parameter: ParameterContract) -> Bool {
        switch (parameter.valueType, parameter.cardinality, value) {
        case (.boolean, .optional, .bool),
             (.boolean, .one, .bool),
             (.integer, .optional, .integer),
             (.integer, .one, .integer),
             (.bytes, .optional, .bytes),
             (.bytes, .one, .bytes),
             (.duration, .optional, .duration),
             (.duration, .one, .duration):
            true
        case (.string, .optional, .string),
             (.string, .one, .string):
            true
        case (.string, .optional, .secret),
             (.string, .one, .secret):
            parameter.availability.requiredCapabilities.contains("secureCredentialInput")
        case (.path, .optional, .path),
             (.path, .one, .path):
            true
        case (.url, .optional, .string),
             (.url, .one, .string),
             (.enumeration, .optional, .string),
             (.enumeration, .one, .string),
             (.platform, .optional, .string),
             (.platform, .one, .string),
             (.signal, .optional, .string),
             (.signal, .one, .string):
            true
        case (.string, .repeated, .strings),
             (.path, .repeated, .strings),
             (.platform, .repeated, .strings),
             (.keyValue, .repeated, .keyValues),
             (.portMapping, .repeated, .portMappings),
             (.mount, .repeated, .mounts):
            true
        default:
            false
        }
    }

    private func issue(_ parameter: ParameterContract, messageKey: String) -> ValidationIssue {
        ValidationIssue(
            parameterID: parameter.id,
            severity: .error,
            messageKey: messageKey,
            recoveryKey: parameter.recoveryKey
        )
    }
}

private extension FieldValue {
    init(upstreamDefault: ParameterValue, valueType: ParameterValueType) {
        switch upstreamDefault {
        case let .boolean(value):
            self = .bool(value)
        case let .integer(value) where valueType == .bytes:
            self = .bytes(value)
        case let .integer(value) where valueType == .duration:
            self = .duration(.seconds(value))
        case let .integer(value):
            self = .integer(value)
        case let .string(value):
            self = .string(value)
        case let .strings(values):
            self = .strings(values)
        }
    }

    var isProvided: Bool {
        switch self {
        case .none:
            false
        case let .string(value), let .path(value), let .secret(value):
            !value.isEmpty
        case let .strings(values):
            !values.isEmpty
        case let .keyValues(values):
            !values.isEmpty
        case let .portMappings(values):
            !values.isEmpty
        case let .mounts(values):
            !values.isEmpty
        default:
            true
        }
    }

    var isActive: Bool {
        if case let .bool(value) = self {
            return value
        }
        return isProvided
    }

    var dependencyValue: String {
        switch self {
        case let .bool(value):
            String(value)
        case let .integer(value), let .bytes(value):
            String(value)
        case let .duration(value):
            String(value.seconds)
        case let .string(value), let .path(value), let .secret(value):
            value
        case let .strings(values):
            values.joined(separator: ",")
        case let .keyValues(values):
            values.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        case let .portMappings(values):
            values.map(\.description).joined(separator: ",")
        case let .mounts(values):
            values.map(\.description).joined(separator: ",")
        case .none:
            ""
        }
    }

    var validationStrings: [String] {
        switch self {
        case let .bool(value):
            [String(value)]
        case let .integer(value), let .bytes(value):
            [String(value)]
        case let .duration(value):
            [String(value.seconds)]
        case let .string(value), let .path(value), let .secret(value):
            [value]
        case let .strings(values):
            values
        case let .keyValues(values):
            values.map { "\($0.key)=\($0.value)" }
        case let .portMappings(values):
            values.map(\.description)
        case let .mounts(values):
            values.map(\.description)
        case .none:
            []
        }
    }
}
