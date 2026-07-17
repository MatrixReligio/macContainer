import Foundation
import MCContainerBridge

public enum ProbePhase: String, Codable, Equatable, Sendable {
    case preflight
    case postflight
}

public struct ProbeContext: Sendable {
    public let bridge: any RuntimeBridge
    public let expectedRuntimeVersion: String
    public let expectedCapabilityIDs: Set<String>
    public let enabledCapabilityIDs: Set<String>
    public let phase: ProbePhase

    public init(
        bridge: any RuntimeBridge,
        expectedRuntimeVersion: String,
        expectedCapabilityIDs: Set<String>,
        enabledCapabilityIDs: Set<String>,
        phase: ProbePhase
    ) {
        self.bridge = bridge
        self.expectedRuntimeVersion = expectedRuntimeVersion
        self.expectedCapabilityIDs = expectedCapabilityIDs
        self.enabledCapabilityIDs = enabledCapabilityIDs
        self.phase = phase
    }
}

public enum ProbeOutcome: Codable, Equatable, Sendable {
    case passed
    case failed(String)
}

public struct ProbeResult: Codable, Equatable, Sendable {
    public let id: ProbeID
    public let outcome: ProbeOutcome

    public init(id: ProbeID, outcome: ProbeOutcome) {
        self.id = id
        self.outcome = outcome
    }
}

public struct ProbeReport: Codable, Equatable, Sendable {
    public let phase: ProbePhase
    public let results: [ProbeResult]

    public init(phase: ProbePhase, results: [ProbeResult]) {
        self.phase = phase
        self.results = results
    }

    public var isCompatible: Bool {
        !results.isEmpty && results.allSatisfy { $0.outcome == .passed }
    }
}

public protocol CompatibilityProbe: Sendable {
    var id: ProbeID { get }
    func run(context: ProbeContext) async -> ProbeResult
}
