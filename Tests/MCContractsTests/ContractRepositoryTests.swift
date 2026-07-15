import Foundation
import Testing
@testable import MCContracts

@Suite("Upstream contract schema")
struct ContractRepositoryTests {
    @Test func semanticRuntimeVersionOrdersNumerically() {
        let older = RuntimeVersion(major: 1, minor: 0, patch: 9)
        let newer = RuntimeVersion(major: 1, minor: 1, patch: 0)

        #expect(older < newer)
        #expect(newer.description == "1.1.0")
    }

    @Test func decodesMinimalReviewedContract() throws {
        let data = Data(#"{"schemaVersion":1,"runtimeVersion":{"major":1,"minor":1,"patch":0},"sourceCommit":"608902412d61761ebd1efc285a9d0a1727e6e2c1","operations":[]}"#.utf8)

        let contract = try ContractRepository.decode(data)

        #expect(contract.schemaVersion == 1)
        #expect(contract.runtimeVersion.description == "1.1.0")
        #expect(contract.sourceCommit == "608902412d61761ebd1efc285a9d0a1727e6e2c1")
        #expect(contract.operations.isEmpty)
    }

    @Test func parameterValueUsesStableSingleKeyJSON() throws {
        let data = Data(#"{"integer":10}"#.utf8)

        let value = try JSONDecoder().decode(ParameterValue.self, from: data)
        let encoded = try JSONEncoder().encode(value)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Int])

        #expect(value == .integer(10))
        #expect(object == ["integer": 10])
    }
}
