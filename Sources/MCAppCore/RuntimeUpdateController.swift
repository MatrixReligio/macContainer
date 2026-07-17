import MCSystemLifecycle
import Observation

@MainActor
@Observable
public final class RuntimeUpdateController: RuntimeUpdateStateSink {
    public private(set) var state: RuntimeUpdateState
    public private(set) var isBusy = false

    @ObservationIgnored private let service: any RuntimeUpdateManaging

    public init(
        service: any RuntimeUpdateManaging,
        initialState: RuntimeUpdateState = .checking
    ) {
        self.service = service
        state = initialState
    }

    public func checkNow() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        state = await service.check(stateSink: self)
    }

    public func installAvailable() async {
        guard !isBusy, case .available = state else { return }
        isBusy = true
        defer { isBusy = false }
        state = await service.installAvailable(stateSink: self)
    }

    public func restoreLatestStatus() async {
        guard !isBusy, let latest = await service.latestStatus() else { return }
        state = latest.state
    }

    public func publish(_ state: RuntimeUpdateState) {
        self.state = state
    }

    public func setAuditState(_ state: RuntimeUpdateState) {
        self.state = state
    }
}

public actor SimulatedRuntimeUpdateManager: RuntimeUpdateManaging {
    public init() {}

    public func check(stateSink: any RuntimeUpdateStateSink) async -> RuntimeUpdateState {
        await stateSink.publish(.checking)
        return .checking
    }

    public func installAvailable(stateSink: any RuntimeUpdateStateSink) async -> RuntimeUpdateState {
        let state = RuntimeUpdateState.installing(.targetProbes)
        await stateSink.publish(state)
        return state
    }

    public func latestStatus() -> PersistedRuntimeUpdateStatus? {
        nil
    }
}
