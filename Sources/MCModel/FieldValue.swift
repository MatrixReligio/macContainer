import Foundation

public enum FieldValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case integer(Int64)
    case bytes(Int64)
    case duration(DurationValue)
    case string(String)
    case strings([String])
    case keyValues([KeyValue])
    case path(String)
    case secret(String)
    case portMappings([PortMapping])
    case mounts([Mount])
    case none

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case bool
        case integer
        case bytes
        case duration
        case string
        case strings
        case keyValues
        case path
        case secret
        case portMappings
        case mounts
        case none
    }

    // The exhaustive switch keeps the persisted representation explicit and reviewable.
    // swiftlint:disable:next cyclomatic_complexity
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let presentKeys = CodingKeys.allCases.filter(container.contains)
        guard presentKeys.count == 1, let key = presentKeys.first else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "FieldValue requires exactly one supported key"
                )
            )
        }

        switch key {
        case .bool:
            self = try .bool(container.decode(Bool.self, forKey: key))
        case .integer:
            self = try .integer(container.decode(Int64.self, forKey: key))
        case .bytes:
            self = try .bytes(container.decode(Int64.self, forKey: key))
        case .duration:
            self = try .duration(container.decode(DurationValue.self, forKey: key))
        case .string:
            self = try .string(container.decode(String.self, forKey: key))
        case .strings:
            self = try .strings(container.decode([String].self, forKey: key))
        case .keyValues:
            self = try .keyValues(container.decode([KeyValue].self, forKey: key))
        case .path:
            self = try .path(container.decode(String.self, forKey: key))
        case .secret:
            self = try .secret(container.decode(String.self, forKey: key))
        case .portMappings:
            self = try .portMappings(container.decode([PortMapping].self, forKey: key))
        case .mounts:
            self = try .mounts(container.decode([Mount].self, forKey: key))
        case .none:
            guard try container.decode(Bool.self, forKey: key) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: container,
                    debugDescription: "FieldValue.none must be true"
                )
            }
            self = .none
        }
    }

    // The exhaustive switch keeps every schema key paired with its associated type.
    // swiftlint:disable:next cyclomatic_complexity
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .bool(value):
            try container.encode(value, forKey: .bool)
        case let .integer(value):
            try container.encode(value, forKey: .integer)
        case let .bytes(value):
            try container.encode(value, forKey: .bytes)
        case let .duration(value):
            try container.encode(value, forKey: .duration)
        case let .string(value):
            try container.encode(value, forKey: .string)
        case let .strings(value):
            try container.encode(value, forKey: .strings)
        case let .keyValues(value):
            try container.encode(value, forKey: .keyValues)
        case let .path(value):
            try container.encode(value, forKey: .path)
        case let .secret(value):
            try container.encode(value, forKey: .secret)
        case let .portMappings(value):
            try container.encode(value, forKey: .portMappings)
        case let .mounts(value):
            try container.encode(value, forKey: .mounts)
        case .none:
            try container.encode(true, forKey: .none)
        }
    }

    public var displayValue: String {
        switch self {
        case let .bool(value):
            String(value)
        case let .integer(value):
            String(value)
        case let .bytes(value) where value.isMultiple(of: 1_073_741_824):
            "\(value / 1_073_741_824) GiB"
        case let .bytes(value):
            "\(value) bytes"
        case let .duration(value):
            "\(value.seconds)s"
        case let .string(value), let .path(value):
            value
        case let .strings(values):
            values.joined(separator: ", ")
        case let .keyValues(values):
            values.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        case .secret:
            "••••••"
        case let .portMappings(values):
            values.map(\.description).joined(separator: ", ")
        case let .mounts(values):
            values.map(\.description).joined(separator: ", ")
        case .none:
            ""
        }
    }

    public var containsSecret: Bool {
        if case .secret = self {
            return true
        }
        return false
    }
}

public struct DurationValue: Codable, Equatable, Sendable {
    public let seconds: Int64

    public init(seconds: Int64) {
        self.seconds = seconds
    }

    public static func seconds(_ value: Int64) -> Self {
        Self(seconds: value)
    }
}

public struct KeyValue: Codable, Equatable, Sendable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public struct PortMapping: Codable, Equatable, Sendable, CustomStringConvertible {
    public let hostAddress: String?
    public let hostPort: UInt16
    public let containerPort: UInt16
    public let protocolName: String

    public init(hostAddress: String?, hostPort: UInt16, containerPort: UInt16, protocolName: String) {
        self.hostAddress = hostAddress
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.protocolName = protocolName
    }

    public var description: String {
        "\(hostAddress.map { "\($0):" } ?? "")\(hostPort):\(containerPort)/\(protocolName)"
    }
}

public struct Mount: Codable, Equatable, Sendable, CustomStringConvertible {
    public let source: String
    public let destination: String
    public let readOnly: Bool

    public init(source: String, destination: String, readOnly: Bool) {
        self.source = source
        self.destination = destination
        self.readOnly = readOnly
    }

    public var description: String {
        "\(source):\(destination)\(readOnly ? ":ro" : "")"
    }
}
