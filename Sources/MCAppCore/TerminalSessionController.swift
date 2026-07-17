import Foundation
import MCModel

public enum TerminalRenderEvent: Equatable, Sendable {
    case terminal(Data)
    case stdout(String)
    case stderr(String)
}

public enum TerminalCloseChoice: Equatable, Sendable {
    case detach
    case terminate(signal: String)
}

public actor TerminalSessionController {
    private let session: any ProcessSession
    private let resizeDebounce: Duration
    private var readerTask: Task<Void, Never>?
    private var resizeTask: Task<Void, Never>?
    private var isClosed = false

    public private(set) var readerIsActive = false

    public init(
        session: any ProcessSession,
        resizeDebounce: Duration = .milliseconds(75)
    ) {
        self.session = session
        self.resizeDebounce = resizeDebounce
    }

    public func start(
        onEvent: @escaping @Sendable (TerminalRenderEvent) async -> Void
    ) {
        guard readerTask == nil, !isClosed else { return }
        readerIsActive = true
        readerTask = Task { [session] in
            do {
                for try await chunk in session.output {
                    try Task.checkCancellation()
                    await onEvent(Self.renderEvent(from: chunk))
                }
            } catch {
                // Closing a session cancels the structured reader. The UI owns error presentation.
            }
            self.readerFinished()
        }
    }

    public func send(_ data: Data) async throws {
        guard !isClosed else { return }
        try await session.send(data)
    }

    public func requestResize(columns: Int, rows: Int) {
        guard !isClosed else { return }
        resizeTask?.cancel()
        let debounce = resizeDebounce
        let session = session
        resizeTask = Task {
            do {
                try await Task.sleep(for: debounce)
                try Task.checkCancellation()
                try await session.resize(columns: columns, rows: rows)
            } catch {
                // A later geometry or close intentionally cancels this request.
            }
        }
    }

    public func close(_ choice: TerminalCloseChoice) async throws {
        guard !isClosed else { return }
        switch choice {
        case .detach:
            try await session.detach()
        case let .terminate(signal):
            try await session.terminate(signal: signal)
        }

        isClosed = true
        resizeTask?.cancel()
        resizeTask = nil
        readerTask?.cancel()
        readerTask = nil
        readerIsActive = false
    }

    private func readerFinished() {
        readerTask = nil
        readerIsActive = false
    }

    private static func renderEvent(from chunk: ProcessOutputChunk) -> TerminalRenderEvent {
        switch chunk {
        case let .terminal(data):
            .terminal(data)
        case let .stdout(data):
            .stdout(safeText(from: data))
        case let .stderr(data):
            .stderr(safeText(from: data))
        }
    }

    private static func safeText(from data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        let bytes = data.map(\.self)
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: bytes, as: UTF8.self)
    }
}
