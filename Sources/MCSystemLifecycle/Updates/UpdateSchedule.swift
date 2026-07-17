import Foundation

public enum UpdateCheckTrigger: String, Codable, Equatable, Sendable {
    case scheduled
    case manual
}

public struct UpdateSchedule: Sendable {
    public let minimumInterval: TimeInterval
    public let maximumJitter: TimeInterval

    public init(minimumInterval: TimeInterval = 86400, maximumJitter: TimeInterval = 3600) {
        self.minimumInterval = max(86400, minimumInterval)
        self.maximumJitter = min(max(0, maximumJitter), 3600)
    }

    public func nextEligibleDate(lastCheck: Date, jitterSeconds: TimeInterval) -> Date {
        lastCheck.addingTimeInterval(minimumInterval + min(max(0, jitterSeconds), maximumJitter))
    }

    public func isDue(
        now: Date,
        lastCheck: Date?,
        jitterSeconds: TimeInterval,
        trigger: UpdateCheckTrigger = .scheduled
    ) -> Bool {
        guard trigger == .scheduled else { return true }
        guard let lastCheck else { return true }
        return now >= nextEligibleDate(lastCheck: lastCheck, jitterSeconds: jitterSeconds)
    }

    public func offlineRetryDate(now: Date, consecutiveFailures: Int) -> Date {
        let exponent = min(max(0, consecutiveFailures - 1), 6)
        let delay = min(86400, 900 * pow(2, Double(exponent)))
        return now.addingTimeInterval(delay)
    }
}
