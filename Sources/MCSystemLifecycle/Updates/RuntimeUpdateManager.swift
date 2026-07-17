import Foundation

public protocol RuntimeUpdateCoordinatorProviding: Sendable {
    func coordinator(
        mode: RuntimeUpdateMode,
        stateSink: any RuntimeUpdateStateSink
    ) async throws -> any RuntimeUpdateCoordinating
}

public protocol RuntimeUpdateManaging: Sendable {
    func check(stateSink: any RuntimeUpdateStateSink) async -> RuntimeUpdateState
    func installAvailable(stateSink: any RuntimeUpdateStateSink) async -> RuntimeUpdateState
    func latestStatus() async -> PersistedRuntimeUpdateStatus?
}

public struct ProductionUpdateCoordinatorProvider: RuntimeUpdateCoordinatorProviding, Sendable {
    public init() {}

    public func coordinator(
        mode: RuntimeUpdateMode,
        stateSink: any RuntimeUpdateStateSink
    ) async throws -> any RuntimeUpdateCoordinating {
        try ProductionUpdateCoordinatorFactory.make(
            stateSink: stateSink,
            preferences: FixedRuntimeUpdatePreferencesProvider(mode: mode)
        )
    }
}

public struct FixedRuntimeUpdatePreferencesProvider: RuntimeUpdatePreferencesPersisting, Sendable {
    private let preferences: RuntimeUpdatePreferences

    public init(mode: RuntimeUpdateMode) {
        preferences = .init(
            automaticallyChecks: true,
            mode: mode,
            consentVersion: mode == .automaticWhenIdle
                ? RuntimeUpdatePolicy.currentConsentVersion
                : nil
        )
    }

    public func load() -> RuntimeUpdatePreferences {
        preferences
    }

    public func save(_: RuntimeUpdatePreferences) {}
}

public actor ProductionRuntimeUpdateManager: RuntimeUpdateManaging {
    private let discovery: any RuntimeReleaseDiscovering
    private let coordinatorProvider: any RuntimeUpdateCoordinatorProviding
    private let statusStore: any RuntimeUpdateStatusStoring
    private let now: @Sendable () -> Date
    private var candidate: RuntimeReleaseCandidate?

    public init(
        discovery: any RuntimeReleaseDiscovering = GitHubRuntimeReleaseDiscovery(),
        coordinatorProvider: any RuntimeUpdateCoordinatorProviding =
            ProductionUpdateCoordinatorProvider(),
        statusStore: any RuntimeUpdateStatusStoring = RuntimeUpdateStatusStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.discovery = discovery
        self.coordinatorProvider = coordinatorProvider
        self.statusStore = statusStore
        self.now = now
    }

    public func check(stateSink: any RuntimeUpdateStateSink) async -> RuntimeUpdateState {
        let sink = DurableRuntimeUpdateSink(external: stateSink, store: statusStore, now: now)
        await sink.publish(.checking)
        do {
            let discovered = try await discovery.discover(validators: nil)
            try Task.checkCancellation()
            switch discovered {
            case let .available(candidate, _):
                self.candidate = candidate
                let coordinator = try await coordinatorProvider.coordinator(
                    mode: .checkOnly,
                    stateSink: sink
                )
                return try await coordinator.process(candidate)
            case .notModified:
                return await finish(.upToDate, sink: sink)
            case .offline:
                return await finish(.checkFailed(.offline), sink: sink)
            case .rateLimited:
                return await finish(.checkFailed(.rateLimited), sink: sink)
            }
        } catch is CancellationError {
            return await finish(.checkFailed(.cancelled), sink: sink)
        } catch {
            return await finish(.checkFailed(.internalFailure), sink: sink)
        }
    }

    public func installAvailable(stateSink: any RuntimeUpdateStateSink) async -> RuntimeUpdateState {
        let sink = DurableRuntimeUpdateSink(external: stateSink, store: statusStore, now: now)
        let candidate: RuntimeReleaseCandidate
        if let cached = self.candidate {
            candidate = cached
        } else {
            await sink.publish(.checking)
            do {
                let discovered = try await discovery.discover(validators: nil)
                guard case let .available(value, _) = discovered else {
                    return await finish(Self.failure(for: discovered), sink: sink)
                }
                candidate = value
                self.candidate = value
            } catch is CancellationError {
                return await finish(.checkFailed(.cancelled), sink: sink)
            } catch {
                return await finish(.checkFailed(.internalFailure), sink: sink)
            }
        }
        do {
            let coordinator = try await coordinatorProvider.coordinator(
                mode: .automaticWhenIdle,
                stateSink: sink
            )
            return try await coordinator.process(candidate)
        } catch is CancellationError {
            return await finish(.checkFailed(.cancelled), sink: sink)
        } catch {
            return await finish(.checkFailed(.internalFailure), sink: sink)
        }
    }

    public func latestStatus() async -> PersistedRuntimeUpdateStatus? {
        try? await statusStore.load()
    }

    private func finish(
        _ state: RuntimeUpdateState,
        sink: DurableRuntimeUpdateSink
    ) async -> RuntimeUpdateState {
        await sink.publish(state)
        return state
    }

    private static func failure(for result: RuntimeReleaseDiscoveryResult) -> RuntimeUpdateState {
        switch result {
        case .available: .checkFailed(.internalFailure)
        case .notModified: .checkFailed(.noCandidate)
        case .offline: .checkFailed(.offline)
        case .rateLimited: .checkFailed(.rateLimited)
        }
    }
}

private struct DurableRuntimeUpdateSink: RuntimeUpdateStateSink, Sendable {
    let external: any RuntimeUpdateStateSink
    let store: any RuntimeUpdateStatusStoring
    let now: @Sendable () -> Date

    func publish(_ state: RuntimeUpdateState) async {
        try? await store.save(.init(state: state, updatedAt: now()))
        await external.publish(state)
    }
}
