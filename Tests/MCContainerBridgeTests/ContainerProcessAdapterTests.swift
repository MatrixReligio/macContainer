import Foundation
@testable import MCContainerBridge
import MCModel
import Testing

@Suite("Container process adapter")
struct ContainerProcessAdapterTests {
    @Test func `binary stdout and stderr stay separate until EOF`() async throws {
        let transport = PipeProcessTransport(id: "exec", terminal: false, includeStandardError: true)
        let session = try await ContainerProcessAdapter.start(transport)
        let collector = Task { try await collect(session.output) }
        let stdout = Data([0x00, 0xFF, 0x41, 0x0A])
        let stderr = Data([0xFE, 0x42, 0x00])

        try await transport.writeStdout(stdout)
        try await transport.writeStderr(stderr)
        await transport.finishOutput()
        let chunks = try await collector.value

        #expect(chunks.compactMap(\.stdoutBytes).joined() == stdout)
        #expect(chunks.compactMap(\.stderrBytes).joined() == stderr)
        #expect(chunks.allSatisfy { $0.terminalBytes == nil })
    }

    @Test func `TTY output is emitted as one terminal stream`() async throws {
        let transport = PipeProcessTransport(id: "tty", terminal: true, includeStandardError: false)
        let session = try await ContainerProcessAdapter.start(transport)
        let collector = Task { try await collect(session.output) }
        let bytes = Data([0x1B, 0x5B, 0x32, 0x4A, 0xFF])

        try await transport.writeStdout(bytes)
        await transport.finishOutput()
        let chunks = try await collector.value

        #expect(chunks.compactMap(\.terminalBytes).joined() == bytes)
        #expect(chunks.allSatisfy { $0.stdoutBytes == nil && $0.stderrBytes == nil })
    }

    @Test func `send preserves binary bytes and resize clamps both dimensions`() async throws {
        let transport = PipeProcessTransport(id: "interactive", terminal: true, includeStandardError: false)
        let session = try await ContainerProcessAdapter.start(transport)
        let bytes = Data([0x00, 0x80, 0xFF])

        try await session.send(bytes)
        try await session.resize(columns: 0, rows: 50000)

        #expect(await transport.sentData == [bytes])
        #expect(await transport.resizeRequests == [TerminalDimensions(columns: 1, rows: 1000)])
        try await session.detach()
    }

    @Test func `wait starts exactly once and preserves the signed exit code`() async throws {
        let transport = PipeProcessTransport(
            id: "wait",
            terminal: false,
            includeStandardError: true,
            exitCode: 137
        )
        let session = try await ContainerProcessAdapter.start(transport)

        let result = try await session.wait()

        #expect(result == ProcessExit(code: 137))
        #expect(await transport.startedCount == 1)
        #expect(await transport.waitCount == 1)
        try await session.detach()
    }

    @Test func `termination validates and normalizes signals before transport access`() async throws {
        let transport = PipeProcessTransport(id: "signal", terminal: false, includeStandardError: true)
        let session = try await ContainerProcessAdapter.start(transport)

        try await session.terminate(signal: "term")
        await #expect(throws: ContainerProcessError.invalidSignal("SIGNOPE")) {
            try await session.terminate(signal: "SIGNOPE")
        }

        #expect(await transport.terminationSignals == ["SIGTERM"])
        try await session.detach()
    }

    @Test func `detach is idempotent and finishes readers`() async throws {
        let transport = PipeProcessTransport(id: "detach", terminal: false, includeStandardError: true)
        let session = try await ContainerProcessAdapter.start(transport)
        let collector = Task { try await collect(session.output) }

        try await session.detach()
        try await session.detach()

        #expect(try await collector.value.isEmpty)
        #expect(await transport.detachCount == 1)
    }

    private func collect(
        _ stream: AsyncThrowingStream<ProcessOutputChunk, any Error>
    ) async throws -> [ProcessOutputChunk] {
        var result: [ProcessOutputChunk] = []
        for try await chunk in stream {
            result.append(chunk)
        }
        return result
    }
}

private struct TerminalDimensions: Equatable, Sendable {
    let columns: Int
    let rows: Int
}

private actor PipeProcessTransport: ContainerProcessTransport {
    nonisolated let id: String
    nonisolated let terminal: Bool
    nonisolated let standardInput: FileHandle? = nil
    nonisolated let standardOutput: FileHandle?
    nonisolated let standardError: FileHandle?

    private let stdoutPipe = Pipe()
    private let stderrPipe: Pipe?
    private let exitCode: Int32
    private var isDetached = false

    private(set) var startedCount = 0
    private(set) var waitCount = 0
    private(set) var sentData: [Data] = []
    private(set) var resizeRequests: [TerminalDimensions] = []
    private(set) var terminationSignals: [String] = []
    private(set) var detachCount = 0

    init(
        id: String,
        terminal: Bool,
        includeStandardError: Bool,
        exitCode: Int32 = 0
    ) {
        self.id = id
        self.terminal = terminal
        self.exitCode = exitCode
        standardOutput = stdoutPipe.fileHandleForReading
        let stderrPipe = includeStandardError ? Pipe() : nil
        self.stderrPipe = stderrPipe
        standardError = stderrPipe?.fileHandleForReading
    }

    func start() async throws {
        startedCount += 1
    }

    func resize(columns: Int, rows: Int) async throws {
        resizeRequests.append(TerminalDimensions(columns: columns, rows: rows))
    }

    func send(_ data: Data) async throws {
        sentData.append(data)
    }

    func wait() async throws -> Int32 {
        waitCount += 1
        return exitCode
    }

    func terminate(signal: String) async throws {
        terminationSignals.append(signal)
    }

    func detach() async throws {
        guard !isDetached else {
            return
        }
        isDetached = true
        detachCount += 1
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe?.fileHandleForWriting.close()
    }

    func writeStdout(_ data: Data) throws {
        try stdoutPipe.fileHandleForWriting.write(contentsOf: data)
    }

    func writeStderr(_ data: Data) throws {
        try stderrPipe?.fileHandleForWriting.write(contentsOf: data)
    }

    func finishOutput() {
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe?.fileHandleForWriting.close()
    }
}

private extension ProcessOutputChunk {
    var stdoutBytes: Data? {
        guard case let .stdout(data) = self else { return nil }
        return data
    }

    var stderrBytes: Data? {
        guard case let .stderr(data) = self else { return nil }
        return data
    }

    var terminalBytes: Data? {
        guard case let .terminal(data) = self else { return nil }
        return data
    }
}

private extension [Data] {
    func joined() -> Data {
        reduce(into: Data()) { $0.append($1) }
    }
}
