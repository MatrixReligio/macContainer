import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("Privileged helper connection retirement")
struct HelperConnectionRetirementTests {
    @Test func `last disconnected client retires the helper`() {
        let scheduler = RecordingRetirementScheduler()
        let retirement = PrivilegedHelperConnectionRetirement(
            schedule: scheduler.schedule,
            terminate: scheduler.terminate
        )
        let connection = retirement.acceptConnection()

        retirement.disconnect(connection)
        scheduler.runScheduled()

        #expect(scheduler.terminationCount == 1)
    }

    @Test func `a new client cancels pending retirement until every client disconnects`() {
        let scheduler = RecordingRetirementScheduler()
        let retirement = PrivilegedHelperConnectionRetirement(
            schedule: scheduler.schedule,
            terminate: scheduler.terminate
        )
        let first = retirement.acceptConnection()
        retirement.disconnect(first)
        let second = retirement.acceptConnection()

        scheduler.runScheduled()
        #expect(scheduler.terminationCount == 0)

        retirement.disconnect(second)
        scheduler.runScheduled()
        #expect(scheduler.terminationCount == 1)
    }
}

private final class RecordingRetirementScheduler: @unchecked Sendable {
    private let lock = NSLock()
    private var scheduled: [@Sendable () -> Void] = []
    private var storedTerminationCount = 0

    var terminationCount: Int {
        lock.withLock { storedTerminationCount }
    }

    func schedule(_ operation: @escaping @Sendable () -> Void) {
        lock.withLock { scheduled.append(operation) }
    }

    func terminate() {
        lock.withLock { storedTerminationCount += 1 }
    }

    func runScheduled() {
        let operations = lock.withLock {
            defer { scheduled.removeAll() }
            return scheduled
        }
        operations.forEach { $0() }
    }
}
