import Foundation
@testable import MCAppCore
import MCModel
import Testing

@Suite("Safe actionable error mapping")
struct ErrorMapperTests {
    @Test func `authentication failure removes headers and credentials and offers credential editing`() {
        let raw = TestFailure(
            "Authorization: Bearer abc.def.ghi; password=hunter2; credential=registry-token"
        )

        let mapped = ErrorMapper().map(raw, domain: .registry, operationID: "registries.login")

        #expect(mapped.retryIsSafe)
        #expect(mapped.recoveryActions.map(\.id).contains("edit-credentials"))
        #expect(mapped.diagnosticDetail.contains("abc.def.ghi") == false)
        #expect(mapped.diagnosticDetail.contains("hunter2") == false)
        #expect(mapped.diagnosticDetail.contains("registry-token") == false)
    }

    @Test func `environment usernames and private paths are redacted without losing useful context`() {
        let raw = TestFailure(
            "API_TOKEN=topsecret USER=alice url=https://alice:pass@example.com " +
                "path=/Users/alice/project temp=/private/var/folders/ab/cd/item failed to connect"
        )

        let mapped = ErrorMapper().map(raw, domain: .container, operationID: "core.run")

        for secret in ["topsecret", "alice:pass", "/Users/alice", "/private/var/folders/ab/cd/item"] {
            #expect(mapped.diagnosticDetail.contains(secret) == false)
        }
        #expect(mapped.diagnosticDetail.contains("failed to connect"))
        #expect(mapped.diagnosticDetail.contains("<home>"))
        #expect(mapped.diagnosticDetail.contains("<temporary>"))
    }

    @Test func `helper authorization failures are not blindly retryable and expose concrete recovery`() {
        let raw = TestFailure("Authorization denied at /var/folders/xy/token; password: admin-secret")

        let mapped = ErrorMapper().map(raw, domain: .helper, operationID: "runtime.install")

        #expect(mapped.retryIsSafe == false)
        #expect(mapped.recoveryActions.map(\.id) == ["review-authorization", "open-activity"])
        #expect(mapped.diagnosticDetail.contains("admin-secret") == false)
        #expect(mapped.diagnosticDetail.contains("/var/folders/") == false)
    }

    @Test func `mapping preserves operation activity and timestamp while destructive retries stay disabled`() throws {
        let activityID = try #require(UUID(uuidString: "6B63F91B-FC77-4B53-AE9F-A51ADAB43183"))
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let mapper = ErrorMapper(now: { timestamp })

        let mapped = mapper.map(
            TestFailure("Malformed upstream response: expected object, received null"),
            domain: .compatibility,
            operationID: "system.uninstall",
            activityID: activityID
        )

        #expect(mapped.domain == .compatibility)
        #expect(mapped.operationID == "system.uninstall")
        #expect(mapped.activityID == activityID)
        #expect(mapped.timestamp == timestamp)
        #expect(mapped.retryIsSafe == false)
        #expect(mapped.recoveryActions.map(\.id).contains("view-compatibility-report"))

        let encodedData = try JSONEncoder().encode(mapped)
        let encoded = try #require(String(data: encodedData, encoding: .utf8))
        #expect(encoded.contains("Malformed upstream response"))
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
