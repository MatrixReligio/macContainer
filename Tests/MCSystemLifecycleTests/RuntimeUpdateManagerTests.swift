import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("Runtime update manager")
struct RuntimeUpdateManagerTests {
    @Test func `manual check is check only and explicit install reuses reviewed candidate`() async {
        let discovery = ManagerDiscovery(result: .available(.fixture, validators: .init(etag: "v1")))
        let provider = ManagerCoordinatorProvider()
        let status = MemoryRuntimeUpdateStatusStore()
        let manager = ProductionRuntimeUpdateManager(
            discovery: discovery,
            coordinatorProvider: provider,
            statusStore: status
        )
        let sink = ManagerSink()

        #expect(await manager.check(stateSink: sink) == .available(version: "1.1.0"))
        #expect(await manager.installAvailable(stateSink: sink) == .upToDate)
        #expect(await provider.modes == [.checkOnly, .automaticWhenIdle])
        #expect(await discovery.requestCount == 1)
        #expect(await provider.candidates == [.fixture, .fixture])
    }

    @Test func `offline check publishes durable actionable state without coordinator`() async {
        let discovery = ManagerDiscovery(result: .offline)
        let provider = ManagerCoordinatorProvider()
        let status = MemoryRuntimeUpdateStatusStore()
        let manager = ProductionRuntimeUpdateManager(
            discovery: discovery,
            coordinatorProvider: provider,
            statusStore: status
        )
        let sink = ManagerSink()

        #expect(await manager.check(stateSink: sink) == .checkFailed(.offline))
        #expect(await sink.states == [.checking, .checkFailed(.offline)])
        #expect(await status.status?.state == .checkFailed(.offline))
        #expect(await provider.modes.isEmpty)
    }

    @Test func `install without cached candidate discovers before coordinating`() async {
        let discovery = ManagerDiscovery(result: .available(.fixture, validators: .init()))
        let provider = ManagerCoordinatorProvider()
        let manager = ProductionRuntimeUpdateManager(
            discovery: discovery,
            coordinatorProvider: provider,
            statusStore: MemoryRuntimeUpdateStatusStore()
        )

        #expect(await manager.installAvailable(stateSink: ManagerSink()) == .upToDate)
        #expect(await discovery.requestCount == 1)
        #expect(await provider.modes == [.automaticWhenIdle])
    }
}

private actor ManagerDiscovery: RuntimeReleaseDiscovering {
    let result: RuntimeReleaseDiscoveryResult
    var requestCount = 0

    init(result: RuntimeReleaseDiscoveryResult) {
        self.result = result
    }

    func discover(validators _: HTTPValidators?) -> RuntimeReleaseDiscoveryResult {
        requestCount += 1
        return result
    }
}

private actor ManagerCoordinatorProvider: RuntimeUpdateCoordinatorProviding {
    private(set) var modes: [RuntimeUpdateMode] = []
    private(set) var candidates: [RuntimeReleaseCandidate] = []

    func coordinator(
        mode: RuntimeUpdateMode,
        stateSink: any RuntimeUpdateStateSink
    ) -> any RuntimeUpdateCoordinating {
        modes.append(mode)
        return ManagerCoordinator(mode: mode, provider: self, sink: stateSink)
    }

    func record(_ candidate: RuntimeReleaseCandidate) {
        candidates.append(candidate)
    }
}

private struct ManagerCoordinator: RuntimeUpdateCoordinating {
    let mode: RuntimeUpdateMode
    let provider: ManagerCoordinatorProvider
    let sink: any RuntimeUpdateStateSink

    func process(_ candidate: RuntimeReleaseCandidate) async -> RuntimeUpdateState {
        await provider.record(candidate)
        let state: RuntimeUpdateState = mode == .checkOnly
            ? .available(version: candidate.version)
            : .upToDate
        await sink.publish(state)
        return state
    }
}

private actor ManagerSink: RuntimeUpdateStateSink {
    private(set) var states: [RuntimeUpdateState] = []
    func publish(_ state: RuntimeUpdateState) {
        states.append(state)
    }
}

private actor MemoryRuntimeUpdateStatusStore: RuntimeUpdateStatusStoring {
    var status: PersistedRuntimeUpdateStatus?
    func load() -> PersistedRuntimeUpdateStatus? {
        status
    }

    func save(_ status: PersistedRuntimeUpdateStatus) {
        self.status = status
    }
}

private extension RuntimeReleaseCandidate {
    static let fixture = Self(
        version: "1.1.0",
        packageURL: URL(string:
            "https://github.com/apple/container/releases/download/1.1.0/" +
                "container-1.1.0-installer-signed.pkg")!,
        packageSHA256: "0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714"
    )
}
