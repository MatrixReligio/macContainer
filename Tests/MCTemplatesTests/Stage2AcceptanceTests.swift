import Foundation
import MCContracts
import MCModel
@testable import MCTemplates
import Testing

@Suite("Stage 2 template acceptance")
struct Stage2AcceptanceTests {
    @Test func `all built ins render byte identically one thousand times without sensitive material`() throws {
        let contract = try ContractRepository.bundled(version: RuntimeVersion(major: 1, minor: 1, patch: 0))
        let renderer = TemplateRenderer(contract: contract)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        for template in BuiltInTemplates.all {
            let baseline = try encodedDocument(for: template, renderer: renderer, encoder: encoder)
            for _ in 0 ..< 1000 {
                #expect(try encodedDocument(for: template, renderer: renderer, encoder: encoder) == baseline)
            }
            let lowercase = try #require(String(data: baseline, encoding: .utf8)).lowercased()
            for marker in sensitiveMarkers {
                #expect(!lowercase.contains(marker), "\(template.id) unexpectedly contains \(marker)")
            }
        }
    }

    private func encodedDocument(
        for template: ScenarioTemplate,
        renderer: TemplateRenderer,
        encoder: JSONEncoder
    ) throws -> Data {
        let review = try renderer.render(template: template, context: context)
        let document = TemplateDocument(
            id: template.id,
            name: template.titleKey,
            operationID: review.draft.operationID,
            fields: review.draft.fields
        )
        return try encoder.encode(document)
    }

    private var context: TemplateContext {
        TemplateContext(
            host: HostProfile(
                logicalCPUs: 8,
                physicalMemoryBytes: 16 * 1_073_741_824,
                chip: .appleSilicon,
                macOSMajor: 26,
                capabilities: ["rosetta", "nestedVirtualization"]
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

    private var sensitiveMarkers: [String] {
        [
            "password",
            "token=",
            "secret=",
            "-----begin private key-----",
            "-----begin rsa private key-----",
            "authorization:",
            #"\"auth\":"#,
            "bearer ",
            "basic "
        ]
    }
}
