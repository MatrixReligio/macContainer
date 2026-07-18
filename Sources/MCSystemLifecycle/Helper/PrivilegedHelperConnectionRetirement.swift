import Foundation

public final class PrivilegedHelperConnectionRetirement: @unchecked Sendable {
    public typealias Schedule = @Sendable (@escaping @Sendable () -> Void) -> Void

    private let lock = NSLock()
    private let schedule: Schedule
    private let terminate: @Sendable () -> Void
    private var activeConnections: Set<UUID> = []
    private var generation: UInt = 0

    public init(
        schedule: @escaping Schedule,
        terminate: @escaping @Sendable () -> Void
    ) {
        self.schedule = schedule
        self.terminate = terminate
    }

    public func acceptConnection() -> UUID {
        lock.withLock {
            generation &+= 1
            let identifier = UUID()
            activeConnections.insert(identifier)
            return identifier
        }
    }

    public func disconnect(_ identifier: UUID) {
        let retirementGeneration = lock.withLock { () -> UInt? in
            guard activeConnections.remove(identifier) != nil,
                  activeConnections.isEmpty
            else { return nil }
            generation &+= 1
            return generation
        }
        guard let retirementGeneration else { return }
        schedule { [weak self] in
            self?.retireIfIdle(generation: retirementGeneration)
        }
    }

    private func retireIfIdle(generation expectedGeneration: UInt) {
        let shouldTerminate = lock.withLock {
            activeConnections.isEmpty && generation == expectedGeneration
        }
        if shouldTerminate {
            terminate()
        }
    }
}
