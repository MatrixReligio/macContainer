import Foundation

public struct ProbeRegistry: Sendable {
    public static var baseline: [any CompatibilityProbe] {
        ProbeID.baselineAllCases.map(BaselineProbe.init)
    }

    private let probes: [any CompatibilityProbe]
    private let timeout: Duration

    public init(
        probes: [any CompatibilityProbe] = Self.baseline,
        timeout: Duration = .seconds(20)
    ) {
        var seen = Set<ProbeID>()
        self.probes = probes.filter { seen.insert($0.id).inserted }
        self.timeout = timeout
    }

    public func runAll(context: ProbeContext) async -> ProbeReport {
        let orderedIDs = probes.map(\.id)
        var completed: [ProbeID: ProbeResult] = [:]

        await withTaskGroup(of: ProbeEvent.self) { group in
            for probe in probes {
                group.addTask {
                    await .result(probe.run(context: context))
                }
            }
            group.addTask {
                do {
                    try await ContinuousClock().sleep(for: timeout)
                } catch {
                    return .cancelledTimer
                }
                return .timeout
            }

            while let event = await group.next() {
                switch event {
                case let .result(result):
                    completed[result.id] = result
                    if completed.count == probes.count {
                        group.cancelAll()
                        return
                    }
                case .timeout:
                    group.cancelAll()
                    return
                case .cancelledTimer:
                    continue
                }
            }
        }

        let results = orderedIDs.map { id in
            completed[id] ?? ProbeResult(id: id, outcome: .failed("timeout"))
        }
        return ProbeReport(phase: context.phase, results: results)
    }
}

private enum ProbeEvent: Sendable {
    case result(ProbeResult)
    case timeout
    case cancelledTimer
}
