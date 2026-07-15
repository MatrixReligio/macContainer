import MCModel

public enum WorkloadKind: String, Codable, CaseIterable, Sendable {
    case quick
    case development
    case database
    case builder
    case secure
    case machine
}

public struct ResourceRecommendation: Codable, Equatable, Sendable {
    public let cpuCount: Int
    public let memoryBytes: Int64
    public let reservedMemoryBytes: Int64

    public init(cpuCount: Int, memoryBytes: Int64, reservedMemoryBytes: Int64) {
        self.cpuCount = cpuCount
        self.memoryBytes = memoryBytes
        self.reservedMemoryBytes = reservedMemoryBytes
    }

    public var isRunnable: Bool {
        memoryBytes >= 512 * 1_048_576
    }
}

public enum ResourceRecommendationEngine {
    private static let gibibyte: Int64 = 1_073_741_824

    public static func recommend(for workload: WorkloadKind, host: HostProfile) -> ResourceRecommendation {
        let desired: (cpu: Int, memory: Int64) = switch workload {
        case .quick, .database, .builder, .secure:
            (2, 2 * gibibyte)
        case .development, .machine:
            (4, 4 * gibibyte)
        }
        let logicalCPUs = max(1, host.logicalCPUs)
        let physicalMemory = max(0, host.physicalMemoryBytes)
        let cpuReserve = logicalCPUs > 2 ? 1 : 0
        let cpuCeiling = logicalCPUs - cpuReserve
        let cpuCount = min(desired.cpu, cpuCeiling)
        let reservedMemory = max(4 * gibibyte, physicalMemory / 4)
        let availableMemory = physicalMemory >= reservedMemory ? physicalMemory - reservedMemory : 0
        let halfMemory = physicalMemory / 2
        let memoryBytes = max(0, min(desired.memory, halfMemory, availableMemory))

        return ResourceRecommendation(
            cpuCount: cpuCount,
            memoryBytes: memoryBytes,
            reservedMemoryBytes: reservedMemory
        )
    }
}
