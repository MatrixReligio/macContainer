import Foundation

public enum TemplateDocumentCodecError: Error, Equatable, Sendable {
    case corruptDocument
    case disabled(String)
    case secretField(String)
    case unsupportedSchemaVersion(Int)
    case invalidDocumentID(String)
}

public struct TemplateDocumentCodec: Sendable {
    private let migrator: TemplateMigrator

    public init(migrator: TemplateMigrator = .current) {
        self.migrator = migrator
    }

    public func `import`(_ data: Data) throws -> TemplateDocument {
        let result: TemplateMigrationResult
        do {
            result = try migrator.decodeAndMigrate(data)
        } catch {
            throw TemplateDocumentCodecError.corruptDocument
        }

        switch result {
        case let .disabled(document):
            throw TemplateDocumentCodecError.disabled(document.reasonKey)
        case let .enabled(document):
            try validate(document)
            return document
        }
    }

    public func export(_ document: TemplateDocument) throws -> Data {
        try validate(document)
        guard document.schemaVersion == TemplateDocument.currentSchemaVersion else {
            throw TemplateDocumentCodecError.unsupportedSchemaVersion(document.schemaVersion)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    private func validate(_ document: TemplateDocument) throws {
        guard Self.validDocumentID(document.id) else {
            throw TemplateDocumentCodecError.invalidDocumentID(document.id)
        }
        if let field = TemplateSecretPolicy.firstSensitiveField(in: document) {
            throw TemplateDocumentCodecError.secretField(field)
        }
    }

    private static func validDocumentID(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        guard
            (1 ... 64).contains(bytes.count),
            let first = bytes.first,
            first.isASCIILowercaseOrDigit
        else {
            return false
        }
        return bytes.allSatisfy { $0.isASCIILowercaseOrDigit || $0 == 45 }
    }
}

private extension UInt8 {
    var isASCIILowercaseOrDigit: Bool {
        (97 ... 122).contains(self) || (48 ... 57).contains(self)
    }
}
