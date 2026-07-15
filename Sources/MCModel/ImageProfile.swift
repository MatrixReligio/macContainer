public struct ImageProfile: Codable, Equatable, Sendable {
    public let reference: String
    public let defaultCommand: [String]
    public let shells: [String]
    public let platform: String
    public let exposedPorts: [UInt16]

    public init(
        reference: String,
        defaultCommand: [String],
        shells: [String],
        platform: String,
        exposedPorts: [UInt16]
    ) {
        self.reference = reference
        self.defaultCommand = defaultCommand
        self.shells = shells
        self.platform = platform
        self.exposedPorts = exposedPorts
    }
}
