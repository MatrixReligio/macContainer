import Foundation
import MCContracts
import Testing

@Suite("Direct runtime bridge coverage")
struct BridgeCoverageTests {
    @Test func `every contract operation has exactly one direct bridge action`() throws {
        let contract = try ContractRepository.bundled(
            version: RuntimeVersion(major: 1, minor: 1, patch: 0)
        )
        let map = try BridgeMap.bundled110()
        let entriesByOperation = Dictionary(grouping: map.entries, by: \.operationID)

        #expect(map.schemaVersion == 1)
        #expect(map.runtimeVersion == "1.1.0")
        #expect(Set(map.entries.map(\.operationID)) == Set(contract.operations.map(\.id)))
        #expect(entriesByOperation.values.allSatisfy { $0.count == 1 })
        #expect(map.entries.allSatisfy { $0.backend != "commandLine" })
    }

    @Test func `every mapping names its implementation evidence`() throws {
        let map = try BridgeMap.bundled110()

        for entry in map.entries {
            #expect(entry.appProtocolMethod.isEmpty == false)
            #expect(entry.productionAdapterType.isEmpty == false)
            #expect(entry.upstreamAction.isEmpty == false)
            #expect(entry.focusedTest.isEmpty == false)
            #expect(entry.cancellationBehavior.isEmpty == false)
            #expect(entry.lockKey.isEmpty == false)
            #expect(BridgeBackend.allCases.contains(entry.backend))
        }
    }
}

private struct BridgeMap: Decodable {
    let schemaVersion: Int
    let runtimeVersion: String
    let entries: [BridgeEntry]

    static func bundled110() throws -> Self {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot
            .appendingPathComponent("Config/contracts/apple-container-1.1.0-bridge-map.json")
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

private struct BridgeEntry: Decodable {
    let operationID: String
    let appProtocolMethod: String
    let productionAdapterType: String
    let upstreamAction: String
    let focusedTest: String
    let cancellationBehavior: String
    let lockKey: String
    let backend: String
}

private enum BridgeBackend {
    static let allCases: Set<String> = [
        "directSwiftAPI",
        "directXPC",
        "Security.framework",
        "nativeServiceManagement"
    ]
}
