import Foundation
import Testing
@testable import MCContracts

@Suite("Upstream contract schema")
struct ContractRepositoryTests {
    private static let expectedOperationIDs = Set([
        "core.run", "core.build",
        "containers.create", "containers.start", "containers.stop", "containers.kill", "containers.delete", "containers.list", "containers.exec", "containers.export", "containers.logs", "containers.inspect", "containers.stats", "containers.copy", "containers.prune",
        "images.list", "images.pull", "images.push", "images.save", "images.load", "images.tag", "images.delete", "images.prune", "images.inspect",
        "builder.start", "builder.status", "builder.stop", "builder.delete",
        "networks.create", "networks.delete", "networks.prune", "networks.list", "networks.inspect",
        "volumes.create", "volumes.delete", "volumes.prune", "volumes.list", "volumes.inspect",
        "registries.login", "registries.logout", "registries.list",
        "machines.create", "machines.run", "machines.list", "machines.inspect", "machines.set", "machines.set-default", "machines.logs", "machines.stop", "machines.delete",
        "system.start", "system.stop", "system.status", "system.version", "system.logs", "system.disk-usage",
        "dns.create", "dns.delete", "dns.list",
        "kernel.set", "configuration.manage",
    ])

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

    @Test func bundledContractContainsEveryBuiltinOperationExactlyOnce() throws {
        let contract = try ContractRepository.bundled(
            version: RuntimeVersion(major: 1, minor: 1, patch: 0)
        )

        #expect(contract.operations.count == 61)
        #expect(Set(contract.operations.map(\.id)) == Self.expectedOperationIDs)
    }

    @Test func everyParameterHasCompleteMetadataAndUniqueOperationScope() throws {
        let contract = try ContractRepository.bundled(
            version: RuntimeVersion(major: 1, minor: 1, patch: 0)
        )

        for operation in contract.operations {
            #expect(Set(operation.parameters.map(\.id)).count == operation.parameters.count)
            for parameter in operation.parameters {
                #expect(parameter.labelKey.isEmpty == false)
                #expect(parameter.conciseHelpKey.isEmpty == false)
                #expect(parameter.detailedHelpKey.isEmpty == false)
                #expect(parameter.validationErrorKey.isEmpty == false)
                #expect(parameter.recoveryKey.isEmpty == false)
                #expect(parameter.acceptedValues.isEmpty == false || parameter.valueType == .boolean)
            }
        }
    }
}
