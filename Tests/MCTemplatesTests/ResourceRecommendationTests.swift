import Foundation
import MCModel
@testable import MCTemplates
import Testing

@Suite("Resource recommendations")
struct ResourceRecommendationTests {
    @Test(arguments: [
        RecommendationCase(logicalCPUs: 2, memoryGiB: 8, workload: .quick, cpuCount: 2, resultMemoryGiB: 2),
        RecommendationCase(logicalCPUs: 8, memoryGiB: 16, workload: .development, cpuCount: 4, resultMemoryGiB: 4),
        RecommendationCase(logicalCPUs: 4, memoryGiB: 8, workload: .database, cpuCount: 2, resultMemoryGiB: 2),
        RecommendationCase(logicalCPUs: 12, memoryGiB: 32, workload: .builder, cpuCount: 2, resultMemoryGiB: 2)
    ])
    func `exact caps`(input: RecommendationCase) {
        let result = ResourceRecommendationEngine.recommend(for: input.workload, host: input.host)

        #expect(result.cpuCount == input.cpuCount)
        #expect(result.memoryBytes == input.memoryBytes)
        #expect(result.cpuCount <= max(1, input.host.logicalCPUs - (input.host.logicalCPUs > 2 ? 1 : 0)))
        #expect(result.memoryBytes <= input.host.physicalMemoryBytes / 2)
        #expect(input.host.physicalMemoryBytes - result.memoryBytes >= max(4.gib, input.host.physicalMemoryBytes / 4))
    }

    @Test func `exhaustive host and workload invariants`() {
        for logicalCPUs in 1 ... 32 {
            for memoryGiB in 4 ... 128 {
                let host = HostProfile(
                    logicalCPUs: logicalCPUs,
                    physicalMemoryBytes: memoryGiB.gib,
                    chip: .appleSilicon,
                    macOSMajor: 26,
                    capabilities: ["rosetta"]
                )
                for workload in WorkloadKind.allCases {
                    let result = ResourceRecommendationEngine.recommend(for: workload, host: host)
                    let expectedReserve = max(4.gib, host.physicalMemoryBytes / 4)
                    let cpuCeiling = max(1, logicalCPUs - (logicalCPUs > 2 ? 1 : 0))

                    #expect(result.cpuCount >= 1)
                    #expect(result.cpuCount <= cpuCeiling)
                    #expect(result.memoryBytes >= 0)
                    #expect(result.memoryBytes <= host.physicalMemoryBytes / 2)
                    #expect(host.physicalMemoryBytes - result.memoryBytes >= expectedReserve)
                    #expect(result.reservedMemoryBytes == expectedReserve)
                    #expect(result.isRunnable == (result.memoryBytes >= 512.mib))
                }
            }
        }
    }

    @Test func `marks memory starved hosts not runnable`() {
        let starved = HostProfile(
            logicalCPUs: 4,
            physicalMemoryBytes: 4.gib + 256.mib,
            chip: .appleSilicon,
            macOSMajor: 26,
            capabilities: []
        )
        let minimallyRunnable = HostProfile(
            logicalCPUs: 4,
            physicalMemoryBytes: 4.gib + 512.mib,
            chip: .appleSilicon,
            macOSMajor: 26,
            capabilities: []
        )

        #expect(!ResourceRecommendationEngine.recommend(for: .quick, host: starved).isRunnable)
        #expect(ResourceRecommendationEngine.recommend(for: .quick, host: minimallyRunnable).isRunnable)
    }

    @Test func `host profile round trips with capabilities`() throws {
        let profile = HostProfile(
            logicalCPUs: 10,
            physicalMemoryBytes: 24.gib,
            chip: .appleSilicon,
            macOSMajor: 26,
            capabilities: ["rosetta", "nestedVirtualization"]
        )

        let data = try JSONEncoder().encode(profile)
        #expect(try JSONDecoder().decode(HostProfile.self, from: data) == profile)
    }

    @Test func `malformed host profile fails safe without overflow`() {
        let malformed = HostProfile(
            logicalCPUs: 0,
            physicalMemoryBytes: .min,
            chip: .appleSilicon,
            macOSMajor: 0,
            capabilities: []
        )

        let result = ResourceRecommendationEngine.recommend(for: .development, host: malformed)

        #expect(result.cpuCount == 1)
        #expect(result.memoryBytes == 0)
        #expect(!result.isRunnable)
    }
}

struct RecommendationCase: Sendable {
    let host: HostProfile
    let workload: WorkloadKind
    let cpuCount: Int
    let memoryBytes: Int64

    init(logicalCPUs: Int, memoryGiB: Int, workload: WorkloadKind, cpuCount: Int, resultMemoryGiB: Int) {
        host = HostProfile(
            logicalCPUs: logicalCPUs,
            physicalMemoryBytes: memoryGiB.gib,
            chip: .appleSilicon,
            macOSMajor: 26,
            capabilities: []
        )
        self.workload = workload
        self.cpuCount = cpuCount
        memoryBytes = resultMemoryGiB.gib
    }
}

private extension Int {
    var gib: Int64 {
        Int64(self) * 1_073_741_824
    }

    var mib: Int64 {
        Int64(self) * 1_048_576
    }
}
