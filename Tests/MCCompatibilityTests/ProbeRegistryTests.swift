@testable import MCCompatibility
import MCContracts
import MCModel
import Testing
import TestSupport

@Suite("Compatibility probe registry")
struct ProbeRegistryTests {
    @Test func `baseline contains every required domain exactly once`() {
        #expect(ProbeRegistry.baseline.map(\.id) == ProbeID.baselineAllCases)
    }

    @Test func `runner executes all probes and preserves stable failures`() async {
        let probes: [any CompatibilityProbe] = ProbeID.baselineAllCases.map { id in
            FakeProbe(id: id, outcome: [.images, .machines].contains(id) ? .failed("decode") : .passed)
        }
        let report = await ProbeRegistry(probes: probes).runAll(context: .fixture)

        #expect(report.results.map(\.id) == ProbeID.baselineAllCases)
        #expect(report.results.count == ProbeID.baselineAllCases.count)
        #expect(report.isCompatible == false)
        #expect(report.results.first { $0.id == .images }?.outcome == .failed("decode"))
        #expect(report.results.first { $0.id == .machines }?.outcome == .failed("decode"))
    }

    @Test func `timeout cancels unfinished probes and reports every result`() async {
        let probes: [any CompatibilityProbe] = [
            FakeProbe(id: .health, outcome: .passed),
            FakeProbe(id: .images, outcome: .passed, delay: .seconds(5))
        ]
        let report = await ProbeRegistry(probes: probes, timeout: .milliseconds(20)).runAll(context: .fixture)

        #expect(report.results.map(\.id) == [.health, .images])
        #expect(report.results[0].outcome == .passed)
        #expect(report.results[1].outcome == .failed("timeout"))
        #expect(report.isCompatible == false)
    }

    @Test func `production baseline uses direct read APIs and no secret details`() async throws {
        let bridge = FakeRuntimeBridge()
        let contract = try ContractRepository.bundled(version: RuntimeVersion(major: 1, minor: 1, patch: 0))
        let context = ProbeContext(
            bridge: bridge,
            expectedRuntimeVersion: "1.1.0",
            expectedCapabilityIDs: Set(contract.operations.map(\.id)),
            enabledCapabilityIDs: Set(contract.operations.map(\.id)),
            phase: .preflight
        )

        let report = await ProbeRegistry().runAll(context: context)
        let invocations = await bridge.recordedInvocations().map(\.operationID)

        #expect(report.isCompatible)
        #expect(report.results.allSatisfy { $0.outcome == .passed })
        #expect(Set(invocations).isSuperset(of: [
            "system.status", "system.version", "containers.list", "images.list", "builder.status",
            "networks.list", "volumes.list", "registries.list", "machines.list", "system.disk-usage",
            "configuration.load", "configuration.validate"
        ]))
        #expect(String(describing: report).contains("password") == false)
    }

    @Test func `missing capability and stopped postflight fail closed`() async {
        let missingCapability = ProbeContext(
            bridge: FakeRuntimeBridge(),
            expectedRuntimeVersion: "1.1.0",
            expectedCapabilityIDs: ["containers.list"],
            enabledCapabilityIDs: [],
            phase: .preflight
        )
        let postflight = ProbeContext(
            bridge: FakeRuntimeBridge(),
            expectedRuntimeVersion: "1.1.0",
            expectedCapabilityIDs: ["containers.list"],
            enabledCapabilityIDs: ["containers.list"],
            phase: .postflight
        )

        #expect(
            await BaselineProbe(.capabilities).run(context: missingCapability).outcome ==
                .failed("invalid-response")
        )
        #expect(await BaselineProbe(.health).run(context: postflight).outcome == .failed("invalid-response"))
    }
}

private struct FakeProbe: CompatibilityProbe {
    let id: ProbeID
    let outcome: ProbeOutcome
    let delay: Duration

    init(id: ProbeID, outcome: ProbeOutcome, delay: Duration = .zero) {
        self.id = id
        self.outcome = outcome
        self.delay = delay
    }

    func run(context _: ProbeContext) async -> ProbeResult {
        do {
            try await ContinuousClock().sleep(for: delay)
            return ProbeResult(id: id, outcome: outcome)
        } catch {
            return ProbeResult(id: id, outcome: .failed("cancelled"))
        }
    }
}

private extension ProbeContext {
    static var fixture: Self {
        Self(
            bridge: FakeRuntimeBridge(),
            expectedRuntimeVersion: "1.1.0",
            expectedCapabilityIDs: [],
            enabledCapabilityIDs: [],
            phase: .preflight
        )
    }
}
