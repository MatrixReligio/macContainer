import Foundation

public struct RuntimeVersion: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }
}

public struct UpstreamContract: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let runtimeVersion: RuntimeVersion
    public let sourceCommit: String
    public let operations: [OperationContract]

    public init(
        schemaVersion: Int,
        runtimeVersion: RuntimeVersion,
        sourceCommit: String,
        operations: [OperationContract]
    ) {
        self.schemaVersion = schemaVersion
        self.runtimeVersion = runtimeVersion
        self.sourceCommit = sourceCommit
        self.operations = operations
    }

    public func operation(id: String) -> OperationContract? {
        operations.first { $0.id == id }
    }
}

public struct OperationContract: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let domain: OperationDomain
    public let nativeAction: String
    public let risk: RiskLevel
    public let parameters: [ParameterContract]

    public init(
        id: String,
        domain: OperationDomain,
        nativeAction: String,
        risk: RiskLevel,
        parameters: [ParameterContract]
    ) {
        self.id = id
        self.domain = domain
        self.nativeAction = nativeAction
        self.risk = risk
        self.parameters = parameters
    }
}

public enum OperationDomain: String, Codable, CaseIterable, Sendable {
    case core
    case containers
    case images
    case builder
    case networks
    case volumes
    case registries
    case machines
    case system
    case dns
    case kernel
    case configuration
}

public enum RiskLevel: String, Codable, Sendable {
    case readOnly
    case mutating
    case destructive
    case privileged
}

public struct ParameterContract: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let cliNames: [String]
    public let valueType: ParameterValueType
    public let cardinality: Cardinality
    public let required: Bool
    public let upstreamDefault: ParameterValue?
    public let acceptedValues: [String]
    public let grammar: String?
    public let dependencies: [String]
    public let conflicts: [String]
    public let availability: AvailabilityContract
    public let securityImpact: RiskLevel
    public let labelKey: String
    public let conciseHelpKey: String
    public let detailedHelpKey: String
    public let validationErrorKey: String
    public let recoveryKey: String

    public init(
        id: String,
        cliNames: [String],
        valueType: ParameterValueType,
        cardinality: Cardinality,
        required: Bool,
        upstreamDefault: ParameterValue?,
        acceptedValues: [String],
        grammar: String?,
        dependencies: [String],
        conflicts: [String],
        availability: AvailabilityContract,
        securityImpact: RiskLevel,
        labelKey: String,
        conciseHelpKey: String,
        detailedHelpKey: String,
        validationErrorKey: String,
        recoveryKey: String
    ) {
        self.id = id
        self.cliNames = cliNames
        self.valueType = valueType
        self.cardinality = cardinality
        self.required = required
        self.upstreamDefault = upstreamDefault
        self.acceptedValues = acceptedValues
        self.grammar = grammar
        self.dependencies = dependencies
        self.conflicts = conflicts
        self.availability = availability
        self.securityImpact = securityImpact
        self.labelKey = labelKey
        self.conciseHelpKey = conciseHelpKey
        self.detailedHelpKey = detailedHelpKey
        self.validationErrorKey = validationErrorKey
        self.recoveryKey = recoveryKey
    }
}

public enum ParameterValueType: String, Codable, Sendable {
    case boolean
    case integer
    case bytes
    case duration
    case string
    case path
    case url
    case enumeration
    case keyValue
    case portMapping
    case mount
    case platform
    case signal
}

public enum Cardinality: String, Codable, Sendable {
    case one
    case optional
    case repeated
}

public enum ParameterValue: Equatable, Sendable {
    case boolean(Bool)
    case integer(Int64)
    case string(String)
    case strings([String])
}

extension ParameterValue: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case boolean
        case integer
        case string
        case strings
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let presentKeys = CodingKeys.allCases.filter(container.contains)
        guard presentKeys.count == 1, let key = presentKeys.first else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "ParameterValue requires exactly one supported key"
                )
            )
        }

        switch key {
        case .boolean:
            self = try .boolean(container.decode(Bool.self, forKey: key))
        case .integer:
            self = try .integer(container.decode(Int64.self, forKey: key))
        case .string:
            self = try .string(container.decode(String.self, forKey: key))
        case .strings:
            self = try .strings(container.decode([String].self, forKey: key))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .boolean(value):
            try container.encode(value, forKey: .boolean)
        case let .integer(value):
            try container.encode(value, forKey: .integer)
        case let .string(value):
            try container.encode(value, forKey: .string)
        case let .strings(value):
            try container.encode(value, forKey: .strings)
        }
    }
}

public struct AvailabilityContract: Codable, Equatable, Sendable {
    public let minimumRuntime: RuntimeVersion
    public let minimumMacOSMajor: Int
    public let requiresAppleSilicon: Bool
    public let requiredCapabilities: [String]

    public init(
        minimumRuntime: RuntimeVersion,
        minimumMacOSMajor: Int,
        requiresAppleSilicon: Bool,
        requiredCapabilities: [String]
    ) {
        self.minimumRuntime = minimumRuntime
        self.minimumMacOSMajor = minimumMacOSMajor
        self.requiresAppleSilicon = requiresAppleSilicon
        self.requiredCapabilities = requiredCapabilities
    }
}
