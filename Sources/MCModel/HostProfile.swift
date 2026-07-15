public enum HostChip: String, Codable, Sendable {
    case appleSilicon
}

public struct HostProfile: Codable, Equatable, Sendable {
    public let logicalCPUs: Int
    public let physicalMemoryBytes: Int64
    public let chip: HostChip
    public let macOSMajor: Int
    public let capabilities: Set<String>

    public init(
        logicalCPUs: Int,
        physicalMemoryBytes: Int64,
        chip: HostChip,
        macOSMajor: Int,
        capabilities: Set<String>
    ) {
        self.logicalCPUs = logicalCPUs
        self.physicalMemoryBytes = physicalMemoryBytes
        self.chip = chip
        self.macOSMajor = macOSMajor
        self.capabilities = capabilities
    }
}
