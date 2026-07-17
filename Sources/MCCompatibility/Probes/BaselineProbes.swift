import Foundation
import MCModel

struct BaselineProbe: CompatibilityProbe {
    let id: ProbeID

    init(_ id: ProbeID) {
        self.id = id
    }

    func run(context: ProbeContext) async -> ProbeResult {
        do {
            try await runCheck(context: context)
            return ProbeResult(id: id, outcome: .passed)
        } catch is CancellationError {
            return ProbeResult(id: id, outcome: .failed("cancelled"))
        } catch {
            return ProbeResult(id: id, outcome: .failed("invalid-response"))
        }
    }

    private func runCheck(context: ProbeContext) async throws {
        switch id {
        case .health:
            try await checkHealth(context)
        case .containers:
            try await validate(context.bridge.containers.list(), key: { $0.id })
        case .images:
            try await validate(context.bridge.images.list(), key: { $0.reference })
        case .builder:
            let summary = try await context.bridge.builders.status()
            guard summary.state != .failed, summary.state != .unknown else {
                throw BaselineProbeError.invalidResponse
            }
        case .networks:
            try await validate(context.bridge.networks.list(), key: { $0.id })
        case .volumes:
            try await validate(context.bridge.volumes.list(), key: { $0.name })
        case .registries:
            try await validate(context.bridge.registries.list(), key: { $0.server })
        case .machines:
            try await validate(context.bridge.machines.list(), key: { $0.id })
        case .diskUsage, .configuration, .capabilities:
            try await runSystemCheck(context: context)
        }
    }

    private func runSystemCheck(context: ProbeContext) async throws {
        switch id {
        case .diskUsage:
            try await checkDiskUsage(context.bridge.system.diskUsage())
        case .configuration:
            let configuration = try await context.bridge.configuration.load()
            guard configuration.values.keys.allSatisfy({ !$0.isEmpty }) else {
                throw BaselineProbeError.invalidResponse
            }
            let issues = await context.bridge.configuration.validate(configuration)
            guard issues.isEmpty else {
                throw BaselineProbeError.invalidResponse
            }
        case .capabilities:
            guard !context.expectedCapabilityIDs.isEmpty,
                  context.expectedCapabilityIDs == context.enabledCapabilityIDs
            else {
                throw BaselineProbeError.invalidResponse
            }
        default:
            throw BaselineProbeError.invalidResponse
        }
    }

    private func checkHealth(_ context: ProbeContext) async throws {
        let status = try await context.bridge.system.status()
        let version = try await context.bridge.system.version()
        guard status.state != .failed,
              status.state != .unknown,
              context.phase != .postflight || status.state == .running,
              version.version == context.expectedRuntimeVersion
        else {
            throw BaselineProbeError.invalidResponse
        }
    }

    private func checkDiskUsage(_ usage: DiskUsageSummary) throws {
        guard usage.containersBytes >= 0,
              usage.imagesBytes >= 0,
              usage.volumesBytes >= 0,
              usage.reclaimableBytes >= 0
        else {
            throw BaselineProbeError.invalidResponse
        }
    }

    private func validate<Value>(
        _ values: [Value],
        key: (Value) -> String
    ) throws {
        let keys = values.map(key)
        guard keys.allSatisfy({ !$0.isEmpty }), Set(keys).count == keys.count else {
            throw BaselineProbeError.invalidResponse
        }
    }
}

private enum BaselineProbeError: Error {
    case invalidResponse
}
