import Foundation
import MCModel
import Synchronization

public protocol ContainerProcessTransport: Sendable {
    var id: String { get }
    var terminal: Bool { get }
    var standardInput: FileHandle? { get }
    var standardOutput: FileHandle? { get }
    var standardError: FileHandle? { get }

    func start() async throws
    func resize(columns: Int, rows: Int) async throws
    func send(_ data: Data) async throws
    func wait() async throws -> Int32
    func terminate(signal: String) async throws
    func detach() async throws
}

public enum ContainerProcessError: Error, Equatable, Sendable {
    case invalidSignal(String)
    case detached
}

public struct ContainerProcessAdapter: ProcessSession, Sendable {
    public let id: String
    public let output: AsyncThrowingStream<ProcessOutputChunk, any Error>

    private let transport: any ContainerProcessTransport
    private let outputCoordinator: ProcessOutputCoordinator
    private let lifecycle: ProcessSessionLifecycle

    private init(transport: any ContainerProcessTransport) {
        id = transport.id
        self.transport = transport
        let outputCoordinator = ProcessOutputCoordinator(transport: transport)
        self.outputCoordinator = outputCoordinator
        output = outputCoordinator.stream
        lifecycle = ProcessSessionLifecycle()
    }

    public static func start(_ transport: any ContainerProcessTransport) async throws -> Self {
        let session = Self(transport: transport)
        try await transport.start()
        return session
    }

    public func send(_ data: Data) async throws {
        guard !lifecycle.isDetached else {
            throw ContainerProcessError.detached
        }
        try await transport.send(data)
    }

    public func resize(columns: Int, rows: Int) async throws {
        guard !lifecycle.isDetached else {
            throw ContainerProcessError.detached
        }
        try await transport.resize(
            columns: min(max(columns, 1), 1000),
            rows: min(max(rows, 1), 1000)
        )
    }

    public func wait() async throws -> ProcessExit {
        guard !lifecycle.isDetached else {
            throw ContainerProcessError.detached
        }
        return try await ProcessExit(code: transport.wait())
    }

    public func terminate(signal: String) async throws {
        guard !lifecycle.isDetached else {
            throw ContainerProcessError.detached
        }
        try await transport.terminate(signal: Self.normalizedSignal(signal))
    }

    public func detach() async throws {
        guard lifecycle.beginDetach() else {
            return
        }
        do {
            try await transport.detach()
            outputCoordinator.cancel()
            lifecycle.finishDetach()
        } catch {
            lifecycle.cancelDetach()
            throw error
        }
    }

    private static func normalizedSignal(_ signal: String) throws -> String {
        let normalized = signal.uppercased().hasPrefix("SIG")
            ? signal.uppercased()
            : "SIG\(signal.uppercased())"
        let supported: Set = [
            "SIGHUP", "SIGINT", "SIGQUIT", "SIGKILL", "SIGTERM", "SIGUSR1", "SIGUSR2",
            "SIGSTOP", "SIGCONT", "SIGWINCH"
        ]
        guard supported.contains(normalized) else {
            throw ContainerProcessError.invalidSignal(normalized)
        }
        return normalized
    }
}

private final class ProcessSessionLifecycle: Sendable {
    private enum State {
        case attached
        case detaching
        case detached
    }

    private let state = Mutex(State.attached)

    var isDetached: Bool {
        state.withLock { $0 != .attached }
    }

    func beginDetach() -> Bool {
        state.withLock { state in
            guard state == .attached else {
                return false
            }
            state = .detaching
            return true
        }
    }

    func finishDetach() {
        state.withLock { $0 = .detached }
    }

    func cancelDetach() {
        state.withLock { $0 = .attached }
    }
}

private final class ProcessOutputCoordinator: Sendable {
    private enum Kind: Sendable {
        case stdout
        case stderr
        case terminal

        func chunk(_ data: Data) -> ProcessOutputChunk {
            switch self {
            case .stdout: .stdout(data)
            case .stderr: .stderr(data)
            case .terminal: .terminal(data)
            }
        }
    }

    private struct Source: Sendable {
        let id: Int
        let kind: Kind
        let handle: FileHandle
    }

    private struct State: Sendable {
        var openSourceIDs: Set<Int>
        var finished = false
    }

    let stream: AsyncThrowingStream<ProcessOutputChunk, any Error>

    private let continuation: AsyncThrowingStream<ProcessOutputChunk, any Error>.Continuation
    private let sources: [Source]
    private let state: Mutex<State>

    init(transport: any ContainerProcessTransport) {
        let pair = AsyncThrowingStream<ProcessOutputChunk, any Error>.makeStream()
        stream = pair.stream
        continuation = pair.continuation

        var sources: [Source] = []
        if let standardOutput = transport.standardOutput {
            sources.append(
                Source(
                    id: 1,
                    kind: transport.terminal ? .terminal : .stdout,
                    handle: standardOutput
                )
            )
        }
        if !transport.terminal, let standardError = transport.standardError {
            sources.append(Source(id: 2, kind: .stderr, handle: standardError))
        }
        self.sources = sources
        state = Mutex(State(openSourceIDs: Set(sources.map(\.id))))

        pair.continuation.onTermination = { [weak self] _ in
            self?.cancel()
        }
        for source in sources {
            source.handle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    self?.finish(sourceID: source.id)
                    return
                }
                self?.yield(source.kind.chunk(data))
            }
        }
        if sources.isEmpty {
            finishStreamIfNeeded()
        }
    }

    func cancel() {
        let shouldFinish = state.withLock { state in
            guard !state.finished else {
                return false
            }
            state.finished = true
            state.openSourceIDs.removeAll()
            return true
        }
        guard shouldFinish else {
            return
        }
        closeSources()
        continuation.finish()
    }

    private func yield(_ chunk: ProcessOutputChunk) {
        let shouldYield = state.withLock { !$0.finished }
        if shouldYield {
            continuation.yield(chunk)
        }
    }

    private func finish(sourceID: Int) {
        let shouldFinish = state.withLock { state in
            guard !state.finished, state.openSourceIDs.remove(sourceID) != nil else {
                return false
            }
            return state.openSourceIDs.isEmpty
        }
        if let source = sources.first(where: { $0.id == sourceID }) {
            source.handle.readabilityHandler = nil
            try? source.handle.close()
        }
        if shouldFinish {
            finishStreamIfNeeded()
        }
    }

    private func finishStreamIfNeeded() {
        let shouldFinish = state.withLock { state in
            guard !state.finished else {
                return false
            }
            state.finished = true
            return true
        }
        if shouldFinish {
            continuation.finish()
        }
    }

    private func closeSources() {
        for source in sources {
            source.handle.readabilityHandler = nil
            try? source.handle.close()
        }
    }
}
