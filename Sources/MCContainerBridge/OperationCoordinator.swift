import Foundation

public enum OperationLockKey: Hashable, Sendable {
    case lifecycle
    case systemService
    case container(String)
    case image(String)
    case builder
    case network(String)
    case volume(String)
    case registry(String)
    case machine(String)
}

public actor OperationCoordinator {
    private struct Waiter {
        let id: UUID
        let key: OperationLockKey
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var owners: [OperationLockKey: UUID] = [:]
    private var waiters: [Waiter] = []
    private var cancelledBeforeEnqueue = Set<UUID>()

    public init() {}

    public func withLock<Result: Sendable>(
        _ key: OperationLockKey,
        operation: @Sendable () async throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        let token = UUID()
        try await acquire(key, token: token)
        defer { release(key, token: token) }
        try Task.checkCancellation()
        return try await operation()
    }

    func waitingCount(for key: OperationLockKey) -> Int {
        waiters.count { $0.key == key }
    }

    private func acquire(_ key: OperationLockKey, token: UUID) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enqueue(key, token: token, continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancelWaiter(token) }
        }
    }

    private func enqueue(
        _ key: OperationLockKey,
        token: UUID,
        continuation: CheckedContinuation<Void, any Error>
    ) {
        if Task.isCancelled || cancelledBeforeEnqueue.remove(token) != nil {
            continuation.resume(throwing: CancellationError())
            return
        }

        if canAcquire(key), !waiters.contains(where: { conflicts($0.key, key) }) {
            owners[key] = token
            continuation.resume()
            return
        }
        waiters.append(Waiter(id: token, key: key, continuation: continuation))
    }

    private func cancelWaiter(_ token: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == token }) {
            let waiter = waiters.remove(at: index)
            waiter.continuation.resume(throwing: CancellationError())
            promoteWaiters()
        } else if !owners.values.contains(token) {
            cancelledBeforeEnqueue.insert(token)
        }
    }

    private func release(_ key: OperationLockKey, token: UUID) {
        guard owners[key] == token else {
            return
        }
        owners.removeValue(forKey: key)
        promoteWaiters()
    }

    private func promoteWaiters() {
        var index = 0
        while index < waiters.count {
            let waiter = waiters[index]
            let blockedByEarlierWaiter = waiters[..<index].contains { conflicts($0.key, waiter.key) }
            guard canAcquire(waiter.key), !blockedByEarlierWaiter else {
                index += 1
                continue
            }

            waiters.remove(at: index)
            if cancelledBeforeEnqueue.remove(waiter.id) != nil {
                waiter.continuation.resume(throwing: CancellationError())
                continue
            }
            owners[waiter.key] = waiter.id
            waiter.continuation.resume()
        }
    }

    private func canAcquire(_ key: OperationLockKey) -> Bool {
        !owners.keys.contains { conflicts($0, key) }
    }

    private func conflicts(_ lhs: OperationLockKey, _ rhs: OperationLockKey) -> Bool {
        if lhs == rhs {
            return true
        }
        if lhs == .lifecycle || rhs == .lifecycle {
            return true
        }
        return false
    }
}
