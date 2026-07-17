import Foundation
@testable import MCAppCore
import Testing

@Suite("Physical test authorization")
struct PhysicalTestAuthorizationTests {
    @Test func `rejects absent empty malformed and mismatched authorization`() {
        #expect(PhysicalTestAuthorization.validatedRunID(environment: [:]) == nil)
        #expect(PhysicalTestAuthorization.validatedRunID(environment: [
            "PHYSICAL_RUN_ID": "",
            "PHYSICAL_TEST_AUTHORIZATION": "",
            "PHYSICAL_RUN_ROOT": ""
        ]) == nil)
        #expect(PhysicalTestAuthorization.validatedRunID(environment: [
            "PHYSICAL_RUN_ID": "not-a-uuid",
            "PHYSICAL_TEST_AUTHORIZATION": "not-a-uuid",
            "PHYSICAL_RUN_ROOT": "/private/tmp/not-a-uuid"
        ]) == nil)

        let runID = UUID().uuidString.lowercased()
        #expect(PhysicalTestAuthorization.validatedRunID(environment: [
            "PHYSICAL_RUN_ID": runID,
            "PHYSICAL_TEST_AUTHORIZATION": UUID().uuidString.lowercased(),
            "PHYSICAL_RUN_ROOT": "/private/tmp/\(runID)"
        ]) == nil)
        #expect(PhysicalTestAuthorization.validatedRunID(environment: [
            "PHYSICAL_RUN_ID": runID,
            "PHYSICAL_TEST_AUTHORIZATION": runID,
            "PHYSICAL_RUN_ROOT": "/private/tmp/a-different-run"
        ]) == nil)
    }

    @Test func `accepts only canonical UUID authorization rooted in its run directory`() {
        let runID = UUID().uuidString.lowercased()
        let environment = [
            "PHYSICAL_RUN_ID": runID,
            "PHYSICAL_TEST_AUTHORIZATION": runID,
            "PHYSICAL_RUN_ROOT": "/private/tmp/maccontainer-tests/\(runID)/./"
        ]

        #expect(PhysicalTestAuthorization.validatedRunID(environment: environment) == runID)

        let uppercase = runID.uppercased()
        #expect(PhysicalTestAuthorization.validatedRunID(environment: [
            "PHYSICAL_RUN_ID": uppercase,
            "PHYSICAL_TEST_AUTHORIZATION": uppercase,
            "PHYSICAL_RUN_ROOT": "/private/tmp/maccontainer-tests/\(uppercase)"
        ]) == nil)
    }
}
