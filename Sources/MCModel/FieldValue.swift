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
