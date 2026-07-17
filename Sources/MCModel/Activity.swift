import Foundation

public enum ActivityOutcome: String, Codable, Equatable, Sendable {
    case succeeded
    case partiallySucceeded
    case failed
    case cancelled
}

public struct ActivityItemResult: Codable, Equatable, Sendable {
    public let resourceID: String
    public let outcome: ActivityOutcome
    public let error: UserFacingError?

    public init(resourceID: String, outcome: ActivityOutcome, error: UserFacingError? = nil) {
        self.resourceID = resourceID
        self.outcome = outcome
        self.error = error
    }
}

public struct ActivityRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let titleKey: String
    public var phaseKey: String
    public var completed: Int64?
    public var total: Int64?
    public let startedAt: Date
    public var updatedAt: Date
    public var outcome: ActivityOutcome?
    public var error: UserFacingError?
    public var isCancellable: Bool
    public var itemResults: [ActivityItemResult]
    public var retryOf: UUID?

    public init(
        id: UUID,
        titleKey: String,
        phaseKey: String = "activity.phase.preparing",
        completed: Int64? = nil,
        total: Int64? = nil,
        startedAt: Date,
        updatedAt: Date,
        outcome: ActivityOutcome? = nil,
        error: UserFacingError? = nil,
        isCancellable: Bool = false,
        itemResults: [ActivityItemResult] = [],
        retryOf: UUID? = nil
    ) {
        self.id = id
        self.titleKey = titleKey
        self.phaseKey = phaseKey
        self.completed = completed
        self.total = total
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.outcome = outcome
        self.error = error
        self.isCancellable = isCancellable
        self.itemResults = itemResults
        self.retryOf = retryOf
    }

    public var progress: Double? {
        guard let completed, let total, total > 0 else { return nil }
        return min(1, max(0, Double(completed) / Double(total)))
    }

    public var elapsed: TimeInterval {
        max(0, updatedAt.timeIntervalSince(startedAt))
    }
}
