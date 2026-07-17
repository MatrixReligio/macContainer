import Foundation
import MCCompatibility
@testable import MCSystemLifecycle
import Testing

@Suite("Least-privilege update agent service")
struct UpdateAgentServiceTests {
    @Test func `schedule enforces daily interval deterministic jitter and manual bypass`() {
        let schedule = UpdateSchedule()
        let last = Date(timeIntervalSince1970: 1000)

        #expect(schedule.nextEligibleDate(lastCheck: last, jitterSeconds: 0) == last.addingTimeInterval(86400))
        #expect(schedule.nextEligibleDate(lastCheck: last, jitterSeconds: 3600) == last.addingTimeInterval(90000))
        #expect(schedule.isDue(now: last.addingTimeInterval(86399), lastCheck: last, jitterSeconds: 0) == false)
        #expect(schedule.isDue(now: last, lastCheck: last, jitterSeconds: 3600, trigger: .manual))
    }

    @Test func `scheduled discovery coordinates available update and publishes to running app`() async throws {
        let fixture = AgentFixture(discovery: .available(.fixture), appRunning: true)

        let result = try await fixture.service.check(trigger: .scheduled, now: fixture.now, jitterSeconds: 0)

        #expect(result == .state(.pending(.workActive)))
        #expect(await fixture.discovery.requestCount == 1)
        #expect(await fixture.coordinator.candidates == [.fixture])
        #expect(await fixture.presenter.published == [.checking, .pending(.workActive)])
        #expect(await fixture.presenter.notifications.isEmpty)
    }

    @Test func `app not running receives redacted local notification`() async throws {
        let fixture = AgentFixture(discovery: .available(.fixture), appRunning: false)

        _ = try await fixture.service.check(trigger: .manual, now: fixture.now, jitterSeconds: 0)

        #expect(await fixture.presenter.published.isEmpty)
        #expect(await fixture.presenter.notifications == [.pending(.workActive)])
    }

    @Test func `not due offline and rate limit outcomes never reach coordinator`() async throws {
        let notDue = AgentFixture(discovery: .notModified, lastCheck: Date(timeIntervalSince1970: 9900))
        #expect(try await notDue.service.check(trigger: .scheduled, now: notDue.now, jitterSeconds: 0) ==
            .skippedUntil(Date(timeIntervalSince1970: 96300)))
        #expect(await notDue.discovery.requestCount == 0)

        let offline = AgentFixture(discovery: .offline)
        #expect(try await offline.service.check(trigger: .manual, now: offline.now, jitterSeconds: 0) ==
            .offlineRetry(Date(timeIntervalSince1970: 10900)))

        let reset = Date(timeIntervalSince1970: 20000)
        let limited = AgentFixture(discovery: .rateLimited(reset: reset))
        #expect(try await limited.service.check(trigger: .manual, now: limited.now, jitterSeconds: 0) ==
            .rateLimited(reset))
        #expect(await offline.coordinator.candidates.isEmpty)
        #expect(await limited.coordinator.candidates.isEmpty)
        #expect(await offline.presenter.published == [.checking, .checkFailed(.offline)])
        #expect(await limited.presenter.published == [.checking, .checkFailed(.rateLimited)])
    }

    @Test func `cancellation propagates and never reaches coordinator`() async throws {
        let fixture = AgentFixture(discovery: .delayed)
        let task = Task {
            try await fixture.service.check(trigger: .manual, now: fixture.now, jitterSeconds: 0)
        }
        await fixture.discovery.waitUntilRequested()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(await fixture.coordinator.candidates.isEmpty)
    }

    @Test func `production state store is private atomic and rejects redirection`() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: ".agent-state-test-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "state.json")
        let store = PrivateUpdateAgentStateStore(fileURL: file)
        let state = UpdateAgentPersistentState(lastCheck: Date(timeIntervalSince1970: 1))

        try await store.save(state)
        #expect(try await store.load() == state)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)

        try FileManager.default.removeItem(at: file)
        let target = root.appending(path: "redirected")
        try Data("{}".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        await #expect(throws: UpdateAgentFileError.unsafeState) {
            try await store.save(state)
        }
    }
}

private struct AgentFixture {
    let now = Date(timeIntervalSince1970: 10000)
    let store: MemoryAgentStateStore
    let discovery: RecordingReleaseDiscovery
    let coordinator = RecordingAgentCoordinator()
    let presenter: RecordingAgentPresenter
    let service: UpdateAgentService

    init(
        discovery outcome: RecordingReleaseDiscovery.Outcome,
        appRunning: Bool = true,
        lastCheck: Date? = nil
    ) {
        store = MemoryAgentStateStore(state: UpdateAgentPersistentState(lastCheck: lastCheck))
        discovery = RecordingReleaseDiscovery(outcome: outcome)
        presenter = RecordingAgentPresenter(appRunning: appRunning)
        service = UpdateAgentService(
            stateStore: store,
            discovery: discovery,
            coordinator: coordinator,
            presenter: presenter
        )
    }
}

private actor MemoryAgentStateStore: UpdateAgentStateStoring {
    var state: UpdateAgentPersistentState

    init(state: UpdateAgentPersistentState) {
        self.state = state
    }

    func load() -> UpdateAgentPersistentState {
        state
    }

    func save(_ state: UpdateAgentPersistentState) {
        self.state = state
    }
}

private actor RecordingReleaseDiscovery: RuntimeReleaseDiscovering {
    enum Outcome: Sendable {
        case available(RuntimeReleaseCandidate)
        case notModified
        case offline
        case rateLimited(reset: Date)
        case delayed
    }

    let outcome: Outcome
    var requestCount = 0
    private var requested = false

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func discover(validators _: HTTPValidators?) async throws -> RuntimeReleaseDiscoveryResult {
        requestCount += 1
        requested = true
        switch outcome {
        case let .available(candidate): return .available(candidate, validators: .init(etag: "v1"))
        case .notModified: return .notModified
        case .offline: return .offline
        case let .rateLimited(reset): return .rateLimited(reset: reset)
        case .delayed:
            try await ContinuousClock().sleep(for: .seconds(30))
            return .notModified
        }
    }

    func waitUntilRequested() async {
        while !requested {
            await Task.yield()
        }
    }
}

private actor RecordingAgentCoordinator: RuntimeUpdateCoordinating {
    var candidates: [RuntimeReleaseCandidate] = []

    func process(_ candidate: RuntimeReleaseCandidate) async -> RuntimeUpdateState {
        candidates.append(candidate)
        return .pending(.workActive)
    }
}

private actor RecordingAgentPresenter: UpdateAgentPresenting {
    let appRunning: Bool
    var published: [RuntimeUpdateState] = []
    var notifications: [RuntimeUpdateState] = []

    init(appRunning: Bool) {
        self.appRunning = appRunning
    }

    func isAppRunning() -> Bool {
        appRunning
    }

    func publish(_ state: RuntimeUpdateState) {
        published.append(state)
    }

    func notify(_ state: RuntimeUpdateState) {
        notifications.append(state)
    }
}

private extension RuntimeReleaseCandidate {
    static let fixture = Self(
        version: "1.1.0",
        packageURL: URL(string: "https://github.com/apple/container/releases/download/1.1.0/container.pkg")!,
        packageSHA256: "0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714"
    )
}
