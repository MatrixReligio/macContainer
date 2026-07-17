import Foundation
import MCModel
import Observation

@MainActor
@Observable
public final class ActivityCenter {
    public private(set) var activities: [UUID: ActivityRecord] = [:]

    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let makeID: @Sendable () -> UUID

    public init(
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.now = now
        self.makeID = makeID
    }

    @discardableResult
    public func start(
        titleKey: String,
        cancellable: Bool = false,
        startedAt: Date? = nil,
        retryOf: UUID? = nil,
        operation: (@Sendable () async -> Void)? = nil
    ) -> UUID {
        let id = makeID()
        let timestamp = now()
        activities[id] = ActivityRecord(
            id: id,
            titleKey: titleKey,
            startedAt: startedAt ?? timestamp,
            updatedAt: timestamp,
            isCancellable: cancellable,
            retryOf: retryOf
        )

        if let operation {
            tasks[id] = Task { [weak self] in
                await operation()
                self?.releaseTask(id)
            }
        }
        return id
    }

    public func update(
        _ id: UUID,
        phaseKey: String? = nil,
        completed: Int64? = nil,
        total: Int64? = nil
    ) {
        guard var activity = activities[id], activity.outcome == nil else { return }
        if let phaseKey {
            activity.phaseKey = phaseKey
        }
        if let completed {
            activity.completed = completed
        }
        if let total {
            activity.total = total
        }
        activity.updatedAt = now()
        activities[id] = activity
    }

    public func finish(
        _ id: UUID,
        outcome: ActivityOutcome,
        error: UserFacingError? = nil,
        itemResults: [ActivityItemResult] = []
    ) {
        guard var activity = activities[id] else { return }
        activity.outcome = outcome
        activity.error = error
        activity.itemResults = itemResults
        activity.isCancellable = false
        activity.updatedAt = now()
        activities[id] = activity
        tasks.removeValue(forKey: id)
    }

    public func cancel(_ id: UUID) {
        guard activities[id]?.isCancellable == true, activities[id]?.outcome == nil else { return }
        tasks[id]?.cancel()
        finish(id, outcome: .cancelled)
    }

    @discardableResult
    public func retry(_ id: UUID, operation: (@Sendable () async -> Void)? = nil) -> UUID? {
        guard let activity = activities[id], activity.outcome != nil else { return nil }
        return start(
            titleKey: activity.titleKey,
            cancellable: activity.isCancellable,
            retryOf: id,
            operation: operation
        )
    }

    public func hasOwnedTask(for id: UUID) -> Bool {
        tasks[id] != nil
    }

    public var hasActiveOperations: Bool {
        activities.values.contains { $0.outcome == nil }
    }

    private func releaseTask(_ id: UUID) {
        tasks.removeValue(forKey: id)
    }
}
