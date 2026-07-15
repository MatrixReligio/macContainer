import Foundation
import MCModel

public struct DisabledTemplateDocument: Equatable, Sendable {
    public let id: String?
    public let detectedSchemaVersion: Int?
    public let originalBytes: Data
    public let reasonKey: String

    public init(id: String?, detectedSchemaVersion: Int?, originalBytes: Data, reasonKey: String) {
        self.id = id
        self.detectedSchemaVersion = detectedSchemaVersion
        self.originalBytes = originalBytes
        self.reasonKey = reasonKey
    }
}

public enum TemplateMigrationResult: Equatable, Sendable {
    case enabled(TemplateDocument)
    case disabled(DisabledTemplateDocument)

    public var id: String? {
        switch self {
        case let .enabled(document):
            document.id
        case let .disabled(document):
            document.id
        }
    }
}

public enum TemplateMigrationError: Error, Equatable, Sendable {
    case corruptDocument
}

public struct TemplateMigrator: Sendable {
    public static let current = Self()
    public static let currentVersion = TemplateDocument.currentSchemaVersion

    public init() {}

    public func decodeAndMigrate(_ data: Data) throws -> TemplateMigrationResult {
        let envelope: TemplateEnvelope
        do {
            envelope = try JSONDecoder().decode(TemplateEnvelope.self, from: data)
        } catch {
            throw TemplateMigrationError.corruptDocument
        }

        switch envelope.schemaVersion {
        case Self.currentVersion:
            return try .enabled(decodeCurrent(data))
        case 1:
            return try migrateVersionOne(data, envelope: envelope)
        case let version where version > Self.currentVersion:
            return disabled(
                data,
                envelope: envelope,
                reasonKey: "template.disabled.future-schema"
            )
        default:
            return disabled(
                data,
                envelope: envelope,
                reasonKey: "template.disabled.unsupported-schema"
            )
        }
    }

    private func decodeCurrent(_ data: Data) throws -> TemplateDocument {
        do {
            return try JSONDecoder().decode(TemplateDocument.self, from: data)
        } catch {
            throw TemplateMigrationError.corruptDocument
        }
    }

    private func migrateVersionOne(
        _ data: Data,
        envelope: TemplateEnvelope
    ) throws -> TemplateMigrationResult {
        let legacy: TemplateDocumentV1
        do {
            legacy = try JSONDecoder().decode(TemplateDocumentV1.self, from: data)
        } catch {
            throw TemplateMigrationError.corruptDocument
        }

        var fields: [String: DraftField] = [:]
        for (id, value) in legacy.fields where id != "memoryMiB" {
            let encoded: Data
            do {
                encoded = try JSONEncoder().encode(value)
                fields[id] = try JSONDecoder().decode(DraftField.self, from: encoded)
            } catch {
                throw TemplateMigrationError.corruptDocument
            }
        }

        if let memoryValue = legacy.fields["memoryMiB"] {
            guard case let .integer(memoryMiB) = memoryValue else {
                throw TemplateMigrationError.corruptDocument
            }
            guard fields["memory"] == nil else {
                return disabled(
                    data,
                    envelope: envelope,
                    reasonKey: "template.disabled.migration-conflict"
                )
            }
            let (bytes, overflow) = memoryMiB.multipliedReportingOverflow(by: 1_048_576)
            guard memoryMiB >= 0, !overflow else {
                return disabled(
                    data,
                    envelope: envelope,
                    reasonKey: "template.disabled.migration-overflow"
                )
            }
            fields["memory"] = DraftField(value: .bytes(bytes), source: .userOverride)
        }

        return .enabled(
            TemplateDocument(
                id: legacy.id,
                name: legacy.name,
                operationID: legacy.operationID,
                fields: fields
            )
        )
    }

    private func disabled(
        _ data: Data,
        envelope: TemplateEnvelope,
        reasonKey: String
    ) -> TemplateMigrationResult {
        .disabled(
            DisabledTemplateDocument(
                id: envelope.id,
                detectedSchemaVersion: envelope.schemaVersion,
                originalBytes: data,
                reasonKey: reasonKey
            )
        )
    }
}

private struct TemplateEnvelope: Decodable {
    let schemaVersion: Int
    let id: String?
}

private struct TemplateDocumentV1: Decodable {
    let id: String
    let name: String
    let operationID: String
    let fields: [String: JSONValue]
}

private enum JSONValue: Codable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case double(Double)
    case string(String)
    case array([Self])
    case object([String: Self])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([Self].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: Self].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }
}
