@testable import MCContainerBridge
import Testing

@Suite("Operation coordinator")
struct OperationCoordinatorTests {
    @Test func `same resource serializes while different resources overlap`() async throws {
        let coordinator = OperationCoordinator()
        let recorder = ConcurrencyRecorder()

        async let first: Void = coordinator.withLock(.container("one")) {
            try await recorder.hold(group: "one")
        }
        async let second: Void = coordinator.withLock(.container("one")) {
            try await recorder.hold(group: "one")
        }
        async let third: Void = coordinator.withLock(.container("two")) {
            try await recorder.hold(group: "two")
        }
        _ = try await (first, second, third)

        #expect(await recorder.maximum(for: "one") == 1)
        #expect(await recorder.globalMaximum >= 2)
    }

    @Test func `cancelled waiter never owns lock`() async throws {
        let coordinator = OperationCoordinator()
        let gate = AsyncGate()
        let entered = EventRecorder()
        let owner = Task {
            try await coordinator.withLock(.lifecycle) {
                await entered.append("owner")
                try await gate.wait()
            }
        }
        await waitUntil { await entered.values == ["owner"] }
        let waiter = Task {
            try await coordinator.withLock(.lifecycle) {
                await entered.append("cancelled-waiter")
            }
        }

        waiter.cancel()
        await #expect(throws: CancellationError.self) {
            try await waiter.value
        }
        await gate.open()
        try await owner.value

        #expect(await entered.values == ["owner"])
    }

    @Test func `waiters acquire the same key in fifo order`() async throws {
        let coordinator = OperationCoordinator()
        let events = EventRecorder()
        let gate = AsyncGate()
        let owner = Task {
            try await coordinator.withLock(.volume("data")) {
                await events.append("owner")
                try await gate.wait()
            }
        }
        await waitUntil { await events.values == ["owner"] }
        let first = Task {
            try await coordinator.withLock(.volume("data")) {
                await events.append("first")
            }
        }
        await waitUntil { await coordinator.waitingCount(for: .volume("data")) == 1 }
        let second = Task {
            try await coordinator.withLock(.volume("data")) {
                await events.append("second")
            }
        }

        await gate.open()
        _ = try await (owner.value, first.value, second.value)

        #expect(await events.values == ["owner", "first", "second"])
    }

    @Test func `lifecycle conflicts globally while service and distinct resources may overlap`() async throws {
        let coordinator = OperationCoordinator()
        let lifecycleProbe = ConcurrencyRecorder()
        async let lifecycle: Void = coordinator.withLock(.lifecycle) {
            try await lifecycleProbe.hold(group: "lifecycle")
        }
        async let container: Void = coordinator.withLock(.container("one")) {
            try await lifecycleProbe.hold(group: "container")
        }
        _ = try await (lifecycle, container)
        #expect(await lifecycleProbe.globalMaximum == 1)

        let overlapProbe = ConcurrencyRecorder()
        async let service: Void = coordinator.withLock(.systemService) {
            try await overlapProbe.hold(group: "service")
        }
        async let network: Void = coordinator.withLock(.network("one")) {
            try await overlapProbe.hold(group: "network")
        }
        _ = try await (service, network)
        #expect(await overlapProbe.globalMaximum >= 2)
    }

    private func waitUntil(
        attempts: Int = 1000,
        condition: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0 ..< attempts {
            if await condition() {
                return
            }
            await Task.yield()
        }
        Issue.record("condition did not become true")
    }
}

private actor ConcurrencyRecorder {
    private var activeByGroup: [String: Int] = [:]
    private var maximumByGroup: [String: Int] = [:]
    private var active = 0
    private(set) var globalMaximum = 0

    func hold(group: String) async throws {
        active += 1
        activeByGroup[group, default: 0] += 1
        globalMaximum = max(globalMaximum, active)
        maximumByGroup[group] = max(maximumByGroup[group, default: 0], activeByGroup[group, default: 0])
        try await Task.sleep(for: .milliseconds(30))
        active -= 1
        activeByGroup[group, default: 0] -= 1
    }

    func maximum(for group: String) -> Int {
        maximumByGroup[group, default: 0]
    }
}

private actor EventRecorder {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async throws {
        try Task.checkCancellation()
        guard !isOpen else {
            return
        }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
        try Task.checkCancellation()
    }

    func open() {
        isOpen = true
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}
