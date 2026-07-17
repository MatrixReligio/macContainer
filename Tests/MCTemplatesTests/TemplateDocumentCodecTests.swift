import Foundation
import MCModel
@testable import MCTemplates
import Testing

@Suite("Template import and export codec")
struct TemplateDocumentCodecTests {
    @Test func `round trips a current secret free document deterministically`() throws {
        let document = TemplateDocument(
            id: "safe-template",
            name: "Safe template",
            operationID: "core.run",
            fields: [
                "image": DraftField(value: .string("alpine:latest"), source: .userOverride),
                "cpus": DraftField(value: .integer(2), source: .hostRecommendation)
            ]
        )

        let data = try TemplateDocumentCodec().export(document)
        let imported = try TemplateDocumentCodec().import(data)

        #expect(imported == document)
        #expect(String(data: data, encoding: .utf8)?.contains("\"schemaVersion\":2") == true)
    }

    @Test func `rejects secrets corrupt bytes and future schemas`() throws {
        let secret = TemplateDocument(
            id: "unsafe-template",
            name: "Unsafe",
            operationID: "core.run",
            fields: ["apiToken": DraftField(value: .secret("do-not-export"), source: .userOverride)]
        )

        #expect(throws: TemplateDocumentCodecError.secretField("apiToken")) {
            try TemplateDocumentCodec().export(secret)
        }
        #expect(throws: TemplateDocumentCodecError.corruptDocument) {
            try TemplateDocumentCodec().import(Data("not-json".utf8))
        }
        #expect(throws: TemplateDocumentCodecError.disabled("template.disabled.future-schema")) {
            try TemplateDocumentCodec().import(Data(#"{"schemaVersion":99,"id":"future"}"#.utf8))
        }
    }
}
