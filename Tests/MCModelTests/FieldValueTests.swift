import Foundation
@testable import MCModel
import Testing

@Suite("Typed fields")
struct FieldValueTests {
    @Test func `stable display and redaction`() {
        #expect(FieldValue.bool(true).displayValue == "true")
        #expect(FieldValue.integer(42).displayValue == "42")
        #expect(FieldValue.bytes(2 * 1_073_741_824).displayValue == "2 GiB")
        #expect(FieldValue.bytes(1500).displayValue == "1500 bytes")
        #expect(FieldValue.duration(.seconds(10)).displayValue == "10s")
        #expect(FieldValue.string("value").displayValue == "value")
        #expect(FieldValue.strings(["one", "two"]).displayValue == "one, two")
        #expect(FieldValue.path("/workspace").displayValue == "/workspace")
        #expect(FieldValue.secret("token").displayValue == "••••••")
        #expect(FieldValue.none.displayValue.isEmpty)

        #expect(FieldValue.secret("token").containsSecret)
        #expect(!FieldValue.string("token").containsSecret)
    }

    @Test func `structured values have unambiguous display`() {
        let keyValues = FieldValue.keyValues([
            KeyValue(key: "MODE", value: "test"),
            KeyValue(key: "PORT", value: "8080")
        ])
        let ports = FieldValue.portMappings([
            PortMapping(hostAddress: "127.0.0.1", hostPort: 8080, containerPort: 80, protocolName: "tcp")
        ])
        let mounts = FieldValue.mounts([
            Mount(source: "/host", destination: "/container", readOnly: true)
        ])

        #expect(keyValues.displayValue == "MODE=test, PORT=8080")
        #expect(ports.displayValue == "127.0.0.1:8080:80/tcp")
        #expect(mounts.displayValue == "/host:/container:ro")
    }

    @Test func `every value round trips through JSON`() throws {
        let values: [FieldValue] = [
            .bool(false),
            .integer(-7),
            .bytes(4096),
            .duration(.seconds(30)),
            .string("text"),
            .strings(["a", "b"]),
            .keyValues([KeyValue(key: "key", value: "value")]),
            .path("/tmp"),
            .secret("redacted-at-display-time"),
            .portMappings([PortMapping(hostAddress: nil, hostPort: 443, containerPort: 8443, protocolName: "tcp")]),
            .mounts([Mount(source: "/a", destination: "/b", readOnly: false)]),
            .none
        ]

        let encoded = try JSONEncoder().encode(values)
        #expect(try JSONDecoder().decode([FieldValue].self, from: encoded) == values)
    }

    @Test func `external JSON uses one stable key per value`() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let fixtures: [(FieldValue, String)] = [
            (.bool(true), #"{"bool":true}"#),
            (.integer(42), #"{"integer":42}"#),
            (.bytes(4096), #"{"bytes":4096}"#),
            (.duration(.seconds(30)), #"{"duration":{"seconds":30}}"#),
            (.string("value"), #"{"string":"value"}"#),
            (.strings(["a", "b"]), #"{"strings":["a","b"]}"#),
            (.path("/tmp"), #"{"path":"/tmp"}"#),
            (.none, #"{"none":true}"#)
        ]

        for (value, expectedJSON) in fixtures {
            let data = try encoder.encode(value)
            #expect(String(data: data, encoding: .utf8) == expectedJSON)
            #expect(try JSONDecoder().decode(FieldValue.self, from: Data(expectedJSON.utf8)) == value)
        }
    }

    @Test func `external JSON rejects ambiguous multiple value keys`() {
        let ambiguous = Data(#"{"bool":true,"integer":1}"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FieldValue.self, from: ambiguous)
        }
    }

    @Test func `errors sort before warnings and information`() {
        let issues = [
            ValidationIssue(parameterID: "memory", severity: .warning, messageKey: "warning"),
            ValidationIssue(parameterID: "network", severity: .information, messageKey: "information"),
            ValidationIssue(parameterID: "image", severity: .error, messageKey: "error"),
            ValidationIssue(parameterID: "cpu", severity: .error, messageKey: "error")
        ].sorted()

        #expect(issues.map(\.severity) == [.error, .error, .warning, .information])
        #expect(issues.map(\.parameterID) == ["cpu", "image", "memory", "network"])
    }
}
