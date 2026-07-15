import MCContracts
import MCModel
@testable import MCTemplates
import Testing

@Suite("Template review rendering")
struct TemplateRendererTests {
    @Test func `review rows explain every value in contract order`() throws {
        let contract = try reviewedContract()
        let review = try TemplateRenderer(contract: contract).render(
            template: BuiltInTemplates.quickRun,
            context: context
        )
        let operation = try #require(contract.operation(id: "core.run"))
        let expectedOrder = operation.parameters.map(\.id).filter { review.draft.fields[$0] != nil }

        #expect(review.rows.map(\.parameterID) == expectedOrder)
        #expect(!review.rows.isEmpty)
        #expect(review.rows.allSatisfy { !$0.sourceDescriptionKey.isEmpty })
        #expect(review.rows.contains {
            $0.parameterID == "memory" && $0.source == .hostRecommendation &&
                $0.sourceDescriptionKey == "value.source.host"
        })
        #expect(review.diffFromUpstream.contains { $0.parameterID == "memory" })
    }

    @Test func `normalized upstream defaults are excluded from diff`() throws {
        let review = try TemplateRenderer(contract: reviewedContract()).render(
            template: BuiltInTemplates.quickRun,
            context: context
        )

        #expect(review.rows.contains {
            $0.parameterID == "detach" && $0.value == .bool(false) && $0.upstreamDefault == .boolean(false)
        })
        #expect(!review.diffFromUpstream.contains { $0.parameterID == "detach" })
        #expect(review.diffFromUpstream.contains { $0.parameterID == "image" })
        #expect(review.diffFromUpstream.contains { $0.parameterID == "cpus" })
    }

    @Test func `maps every provenance to stable description key`() throws {
        let sources = ScenarioTemplate(
            id: "source-map",
            titleKey: "template.source-map.title",
            summaryKey: "template.source-map.summary",
            operationID: "core.run"
        ) { _ in
            OperationDraft(operationID: "core.run", fields: [
                "image": DraftField(value: .string("alpine:latest"), source: .userOverride),
                "detach": DraftField(value: .bool(false), source: .upstreamDefault),
                "cpus": DraftField(value: .integer(2), source: .hostRecommendation),
                "arguments": DraftField(value: .strings(["/bin/sh"]), source: .imageMetadata),
                "name": DraftField(value: .string("source-map"), source: .scenarioRule)
            ])
        }

        let rows = try TemplateRenderer(contract: reviewedContract()).render(template: sources, context: context).rows
        let keys = Dictionary(uniqueKeysWithValues: rows.map { ($0.source, $0.sourceDescriptionKey) })

        #expect(keys == [
            .upstreamDefault: "value.source.upstream",
            .scenarioRule: "value.source.scenario",
            .hostRecommendation: "value.source.host",
            .imageMetadata: "value.source.image",
            .userOverride: "value.source.user"
        ])
    }

    @Test func `rejects unknown operation field and draft mismatch`() throws {
        let renderer = try TemplateRenderer(contract: reviewedContract())
        let missing = ScenarioTemplate(
            id: "missing",
            titleKey: "missing.title",
            summaryKey: "missing.summary",
            operationID: "does.not.exist"
        ) { _ in
            OperationDraft(operationID: "does.not.exist", fields: [:])
        }
        #expect(throws: TemplateRendererError.operationNotFound("does.not.exist")) {
            try renderer.render(template: missing, context: context)
        }

        let unknown = ScenarioTemplate(
            id: "unknown",
            titleKey: "unknown.title",
            summaryKey: "unknown.summary",
            operationID: "core.run"
        ) { _ in
            OperationDraft(operationID: "core.run", fields: [
                "notInContract": DraftField(value: .bool(true), source: .scenarioRule)
            ])
        }
        #expect(throws: TemplateRendererError.unknownParameter(templateID: "unknown", parameterID: "notInContract")) {
            try renderer.render(template: unknown, context: context)
        }

        let mismatch = ScenarioTemplate(
            id: "mismatch",
            titleKey: "mismatch.title",
            summaryKey: "mismatch.summary",
            operationID: "core.run"
        ) { _ in
            OperationDraft(operationID: "containers.create", fields: [:])
        }
        #expect(throws: TemplateRendererError.draftOperationMismatch(
            expected: "core.run",
            actual: "containers.create"
        )) {
            try renderer.render(template: mismatch, context: context)
        }
    }

    @Test func `every built in produces transparent secret free rows`() throws {
        let renderer = try TemplateRenderer(contract: reviewedContract())

        for template in BuiltInTemplates.all {
            let review = try renderer.render(template: template, context: context)
            #expect(review.rows.count == review.draft.fields.count)
            #expect(review.rows.allSatisfy { !$0.value.containsSecret })
            #expect(Set(review.diffFromUpstream.map(\.parameterID)).isSubset(of: Set(review.rows.map(\.parameterID))))
        }
    }

    private var context: TemplateContext {
        TemplateContext(
            host: HostProfile(
                logicalCPUs: 8,
                physicalMemoryBytes: 16 * 1_073_741_824,
                chip: .appleSilicon,
                macOSMajor: 26,
                capabilities: ["rosetta"]
            ),
            image: ImageProfile(
                reference: "ghcr.io/example/app:1.0",
                defaultCommand: [],
                shells: ["/bin/sh"],
                platform: "linux/arm64",
                exposedPorts: [8080]
            ),
            selectedDirectory: "/Users/test/Project",
            selectedVolume: "app-data",
            hostPort: 18080
        )
    }

    private func reviewedContract() throws -> UpstreamContract {
        try ContractRepository.bundled(version: RuntimeVersion(major: 1, minor: 1, patch: 0))
    }
}
