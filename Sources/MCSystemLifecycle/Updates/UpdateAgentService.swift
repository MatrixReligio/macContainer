import Foundation
import MCCompatibility

public struct HTTPValidators: Codable, Equatable, Sendable {
    public let etag: String?
    public let lastModified: String?

    public init(etag: String? = nil, lastModified: String? = nil) {
        self.etag = etag
        self.lastModified = lastModified
    }
}

public struct RuntimeReleaseCandidate: Codable, Equatable, Sendable {
    public let version: String
    public let packageURL: URL
    public let packageSHA256: String

    public init(version: String, packageURL: URL, packageSHA256: String) {
        self.version = version
        self.packageURL = packageURL
        self.packageSHA256 = packageSHA256
    }
}

public enum RuntimeReleaseDiscoveryResult: Equatable, Sendable {
    case available(RuntimeReleaseCandidate, validators: HTTPValidators)
    case notModified
    case offline
    case rateLimited(reset: Date)
}

public enum RuntimeUpdateState: Codable, Equatable, Sendable {
    case checking
    case available(version: String)
    case downloading(version: String)
    case pending(PendingReason)
    case installing(UpgradeStage)
    case held(HoldReason)
    case rolledBack(previousVersion: String, failedProbeID: ProbeID?)
    case recoveryRequired(code: String)
    case checkFailed(RuntimeUpdateCheckFailure)
    case upToDate
}

public enum RuntimeUpdateCheckFailure: String, Codable, Equatable, Sendable {
    case cancelled
    case internalFailure
    case noCandidate
    case offline
    case rateLimited
}

public enum UpdateAgentRunResult: Equatable, Sendable {
    case skippedUntil(Date)
    case offlineRetry(Date)
    case rateLimited(Date)
    case state(RuntimeUpdateState)
}

public struct UpdateAgentPersistentState: Codable, Equatable, Sendable {
    public var lastCheck: Date?
    public var validators: HTTPValidators?
    public var consecutiveOfflineFailures: Int
    public var nextAllowedCheck: Date?

    public init(
        lastCheck: Date? = nil,
        validators: HTTPValidators? = nil,
        consecutiveOfflineFailures: Int = 0,
        nextAllowedCheck: Date? = nil
    ) {
        self.lastCheck = lastCheck
        self.validators = validators
        self.consecutiveOfflineFailures = consecutiveOfflineFailures
        self.nextAllowedCheck = nextAllowedCheck
    }
}

public protocol UpdateAgentStateStoring: Sendable {
    func load() async throws -> UpdateAgentPersistentState
    func save(_ state: UpdateAgentPersistentState) async throws
}

public protocol RuntimeReleaseDiscovering: Sendable {
    func discover(validators: HTTPValidators?) async throws -> RuntimeReleaseDiscoveryResult
}

public protocol RuntimeUpdateCoordinating: Sendable {
    func process(_ candidate: RuntimeReleaseCandidate) async throws -> RuntimeUpdateState
}

public protocol UpdateAgentPresenting: Sendable {
    func isAppRunning() async -> Bool
    func publish(_ state: RuntimeUpdateState) async
    func notify(_ state: RuntimeUpdateState) async
}

public actor UpdateAgentService {
    private let schedule: UpdateSchedule
    private let stateStore: any UpdateAgentStateStoring
    private let discovery: any RuntimeReleaseDiscovering
    private let coordinator: any RuntimeUpdateCoordinating
    private let presenter: any UpdateAgentPresenting

    public init(
        schedule: UpdateSchedule = UpdateSchedule(),
        stateStore: any UpdateAgentStateStoring,
        discovery: any RuntimeReleaseDiscovering,
        coordinator: any RuntimeUpdateCoordinating,
        presenter: any UpdateAgentPresenting
    ) {
        self.schedule = schedule
        self.stateStore = stateStore
        self.discovery = discovery
        self.coordinator = coordinator
        self.presenter = presenter
    }

    public func check(
        trigger: UpdateCheckTrigger,
        now: Date = Date(),
        jitterSeconds: TimeInterval
    ) async throws -> UpdateAgentRunResult {
        try Task.checkCancellation()
        var persisted = try await stateStore.load()
        if trigger == .scheduled, let nextAllowed = persisted.nextAllowedCheck, now < nextAllowed {
            return .skippedUntil(nextAllowed)
        }
        guard schedule.isDue(
            now: now,
            lastCheck: persisted.lastCheck,
            jitterSeconds: jitterSeconds,
            trigger: trigger
        ) else {
            guard let lastCheck = persisted.lastCheck else { return .skippedUntil(now) }
            return .skippedUntil(schedule.nextEligibleDate(lastCheck: lastCheck, jitterSeconds: jitterSeconds))
        }

        await present(.checking, notifyWhenClosed: false)
        let discoveryResult = try await discovery.discover(validators: persisted.validators)
        try Task.checkCancellation()

        switch discoveryResult {
        case .notModified:
            persisted.lastCheck = now
            persisted.consecutiveOfflineFailures = 0
            persisted.nextAllowedCheck = nil
            try await stateStore.save(persisted)
            await present(.upToDate)
            return .state(.upToDate)
        case .offline:
            persisted.consecutiveOfflineFailures += 1
            let retry = schedule.offlineRetryDate(
                now: now,
                consecutiveFailures: persisted.consecutiveOfflineFailures
            )
            persisted.nextAllowedCheck = retry
            try await stateStore.save(persisted)
            await present(.checkFailed(.offline), notifyWhenClosed: false)
            return .offlineRetry(retry)
        case let .rateLimited(reset):
            persisted.nextAllowedCheck = reset
            try await stateStore.save(persisted)
            await present(.checkFailed(.rateLimited), notifyWhenClosed: false)
            return .rateLimited(reset)
        case let .available(candidate, validators):
            persisted.lastCheck = now
            persisted.validators = validators
            persisted.consecutiveOfflineFailures = 0
            persisted.nextAllowedCheck = nil
            try await stateStore.save(persisted)
            let state = try await coordinator.process(candidate)
            try Task.checkCancellation()
            await present(state)
            return .state(state)
        }
    }

    private func present(_ state: RuntimeUpdateState, notifyWhenClosed: Bool = true) async {
        if await presenter.isAppRunning() {
            await presenter.publish(state)
        } else if notifyWhenClosed {
            await presenter.notify(state)
        }
    }
}
