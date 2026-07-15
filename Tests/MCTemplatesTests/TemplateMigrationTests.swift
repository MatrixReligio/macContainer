import Foundation
import MCModel
@testable import MCTemplates
import Testing

@Suite("Template schema migration")
struct TemplateMigrationTests {
    @Test func `migrates version one memory mi B without loss`() throws {
        let old = Data(
            #"{"schemaVersion":1,"id":"dev","name":"Dev","operationID":"core.run","fields":{"memoryMiB":4096}}"#.utf8
        )

        let result = try TemplateMigrator.current.decodeAndMigrate(old)
        let migrated = try #require(result.document)

        #expect(migrated.schemaVersion == 2)
        #expect(migrated.fields["memory"]?.value == .bytes(4_294_967_296))
        #expect(migrated.fields["memory"]?.source == .userOverride)
    }

    @Test func `preserves every non migrated field exactly`() throws {
        let original = DraftField(value: .strings(["A=one", "B=two"]), source: .scenarioRule)
        let old = try versionOneData(fields: ["environment": original])

        let result = try TemplateMigrator.current.decodeAndMigrate(old)

        #expect(try #require(result.document).fields == ["environment": original])
    }

    @Test func `current version decodes without rewriting`() throws {
        let document = TemplateDocument(
            id: "current",
            name: "Current",
            operationID: "core.run",
            fields: ["image": DraftField(value: .string("alpine:latest"), source: .userOverride)]
        )
        let data = try JSONEncoder().encode(document)

        let result = try TemplateMigrator.current.decodeAndMigrate(data)

        #expect(result == .enabled(document))
    }

    @Test func `safely disables unknown future schema and preserves original bytes`() throws {
        let future = Data(#"{"schemaVersion":99,"id":"future"}"#.utf8)

        let result = try TemplateMigrator.current.decodeAndMigrate(future)
        let disabled = try #require(result.disabled)

        #expect(disabled.id == "future")
        #expect(disabled.detectedSchemaVersion == 99)
        #expect(disabled.originalBytes == future)
        #expect(disabled.reasonKey == "template.disabled.future-schema")
    }

    @Test func `safely disables overflow instead of producing invalid memory`() throws {
        let old = Data(
            """
            {"schemaVersion":1,"id":"huge","name":"Huge","operationID":"core.run",
            "fields":{"memoryMiB":9223372036854775807}}
            """.utf8
        )

        let result = try TemplateMigrator.current.decodeAndMigrate(old)
        let disabled = try #require(result.disabled)

        #expect(disabled.id == "huge")
        #expect(disabled.originalBytes == old)
        #expect(disabled.reasonKey == "template.disabled.migration-overflow")
    }

    @Test func `rejects corrupt documents without leaking decoder details`() {
        let corrupt = Data(#"{"schemaVersion":2,"id":"broken"}"#.utf8)

        #expect(throws: TemplateMigrationError.corruptDocument) {
            try TemplateMigrator.current.decodeAndMigrate(corrupt)
        }
    }

    @Test func `store returns future documents as disabled records`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainerTemplateMigrationTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let future = Data(#"{"schemaVersion":99,"id":"future"}"#.utf8)
        try future.write(to: root.appendingPathComponent("future.json"))
        let store = TemplateStore(root: root, fileSystem: LocalTemplateFileSystem())

        let record = try await store.loadRecord(id: "future")

        #expect(record.disabled?.originalBytes == future)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("future.json").path))
    }

    @Test func `store quarantines corrupt documents by rename without overwriting them`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainerTemplateQuarantineTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let corrupt = Data(#"{"schemaVersion":2,"id":"broken"}"#.utf8)
        let original = root.appendingPathComponent("broken.json")
        try corrupt.write(to: original)
        let quarantine = root.appendingPathComponent(".quarantine", isDirectory: true)
        try FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: true)
        let existing = quarantine.appendingPathComponent("broken.json.corrupt")
        let existingBytes = Data("existing evidence".utf8)
        try existingBytes.write(to: existing)
        let store = TemplateStore(root: root, fileSystem: LocalTemplateFileSystem())

        await #expect(throws: TemplateMigrationError.corruptDocument) {
            try await store.loadRecord(id: "broken")
        }

        let entries = try FileManager.default.contentsOfDirectory(at: quarantine, includingPropertiesForKeys: nil)
        let quarantined = quarantine.appendingPathComponent("broken.json.corrupt.1")
        #expect(entries.map(\.lastPathComponent).sorted() == ["broken.json.corrupt", "broken.json.corrupt.1"])
        #expect(try Data(contentsOf: existing) == existingBytes)
        #expect(try Data(contentsOf: quarantined) == corrupt)
        #expect(!FileManager.default.fileExists(atPath: original.path))
    }

    private func versionOneData(fields: [String: DraftField]) throws -> Data {
        var encodedFields: [String: Any] = [:]
        for (id, field) in fields {
            encodedFields[id] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(field))
        }
        return try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "id": "legacy",
            "name": "Legacy",
            "operationID": "core.run",
            "fields": encodedFields
        ])
    }
}

private extension TemplateMigrationResult {
    var document: TemplateDocument? {
        guard case let .enabled(document) = self else {
            return nil
        }
        return document
    }

    var disabled: DisabledTemplateDocument? {
        guard case let .disabled(document) = self else {
            return nil
        }
        return document
    }
}
