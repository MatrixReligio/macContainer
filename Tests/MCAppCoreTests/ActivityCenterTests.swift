import Foundation
@testable import MCAppCore
import MCModel
import Testing

@MainActor
@Suite("Activity Center")
struct ActivityCenterTests {
    @Test
    func `publishes progress and completion`() {
        let center = ActivityCenter()
        let id = center.start(titleKey: "activity.image.pull", cancellable: true)

        center.update(id, phaseKey: "activity.phase.downloading", completed: 50, total: 100)

        #expect(center.activities[id]?.progress == 0.5)
        #expect(center.activities[id]?.phaseKey == "activity.phase.downloading")
        center.finish(id, outcome: .succeeded)
        #expect(center.activities[id]?.outcome == .succeeded)
        #expect(center.activities[id]?.phaseKey == "activity.phase.completed")
        #expect(center.hasOwnedTask(for: id) == false)
    }

    @Test func `terminal outcomes replace stale preparing phase`() {
        let center = ActivityCenter()
        let failed = center.start(titleKey: "activity.images.refresh")
        let cancelled = center.start(titleKey: "activity.machines.refresh")

        center.finish(failed, outcome: .failed)
        center.finish(cancelled, outcome: .cancelled)

        #expect(center.activities[failed]?.phaseKey == "activity.phase.failed")
        #expect(center.activities[cancelled]?.phaseKey == "activity.phase.cancelled")
    }

    @Test
    func `clamps progress and computes elapsed time`() {
        let startedAt = Date(timeIntervalSince1970: 100)
        let center = ActivityCenter(now: { Date(timeIntervalSince1970: 160) })
        let id = center.start(titleKey: "activity.build", startedAt: startedAt)

        center.update(id, completed: 200, total: 100)

        #expect(center.activities[id]?.progress == 1)
        #expect(center.activities[id]?.elapsed == 60)
    }

    @Test
    func `cancellation propagates to owned task`() async {
        let center = ActivityCenter()
        let recorder = CancellationRecorder()
        let id = center.start(titleKey: "activity.build", cancellable: true) {
            await withTaskCancellationHandler {
                try? await Task.sleep(for: .seconds(30))
            } onCancel: {
                recorder.record()
            }
        }

        await Task.yield()
        center.cancel(id)
        await recorder.wait()

        #expect(recorder.wasCancelled)
        #expect(center.activities[id]?.outcome == .cancelled)
        #expect(center.hasOwnedTask(for: id) == false)
    }

    @Test
    func `retry starts a replacement activity`() throws {
        let center = ActivityCenter()
        let id = center.start(titleKey: "activity.pull")
        center.finish(
            id,
            outcome: .failed,
            error: UserFacingError(code: "offline", messageKey: "error.offline")
        )

        let replacement = try #require(center.retry(id))

        #expect(replacement != id)
        #expect(center.activities[replacement]?.titleKey == "activity.pull")
        #expect(center.activities[replacement]?.retryOf == id)
    }

    @Test
    func `preserves structured partial batch results`() {
        let center = ActivityCenter()
        let id = center.start(titleKey: "activity.batch")
        center.finish(
            id,
            outcome: .partiallySucceeded,
            itemResults: [
                ActivityItemResult(resourceID: "one", outcome: .succeeded),
                ActivityItemResult(
                    resourceID: "two",
                    outcome: .failed,
                    error: UserFacingError(code: "busy", messageKey: "error.busy")
                )
            ]
        )

        #expect(center.activities[id]?.itemResults.count == 2)
        #expect(center.activities[id]?.itemResults.last?.error?.code == "busy")
    }

    @Test
    func `completed owned task is released`() async {
        let center = ActivityCenter()
        let id = center.start(titleKey: "activity.quick") {}

        for _ in 0 ..< 20 where center.hasOwnedTask(for: id) {
            await Task.yield()
        }

        #expect(center.hasOwnedTask(for: id) == false)
    }
}

private final class CancellationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var wasCancelled: Bool {
        lock.withLock { cancelled }
    }

    func record() {
        lock.withLock { cancelled = true }
    }

    func wait() async {
        for _ in 0 ..< 100 where wasCancelled == false {
            await Task.yield()
        }
    }
}
