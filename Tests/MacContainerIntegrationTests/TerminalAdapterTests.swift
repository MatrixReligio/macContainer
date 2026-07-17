import Foundation
import MCAppCore
import MCModel
import Testing

@Suite("Terminal session controller")
struct TerminalAdapterTests {
    @Test func `terminal bytes remain exact for utf8 invalid ansi and large chunks`() async throws {
        let session = FakeProcessSession()
        let events = EventCollector()
        let controller = TerminalSessionController(session: session, resizeDebounce: .milliseconds(30))
        await controller.start { event in
            await events.append(event)
        }
        let chunks = [
            Data("hello 你好".utf8),
            Data([0xFF, 0xFE, 0x80]),
            Data([0x1B, 0x5B, 0x32, 0x4A]),
            Data(repeating: 0x41, count: 1_048_576)
        ]

        for chunk in chunks {
            session.emit(.terminal(chunk))
        }
        await events.waitForCount(chunks.count)

        #expect(await events.values == chunks.map(TerminalRenderEvent.terminal))
        try await controller.close(.detach)
        #expect(await session.detachCount == 1)
        #expect(await controller.readerIsActive == false)
    }

    @Test func `plain process output stays separated and decodes malformed utf8 safely`() async throws {
        let session = FakeProcessSession()
        let events = EventCollector()
        let controller = TerminalSessionController(session: session)
        await controller.start { event in
            await events.append(event)
        }

        session.emit(.stdout(Data([0x4F, 0x4B, 0xFF])))
        session.emit(.stderr(Data("failure".utf8)))
        await events.waitForCount(2)

        #expect(await events.values == [.stdout("OK�"), .stderr("failure")])
        try await controller.close(.terminate(signal: "TERM"))
        #expect(await session.terminationSignals == ["TERM"])
    }

    @Test func `input is byte exact and resize is debounced to the last geometry`() async throws {
        let session = FakeProcessSession()
        let controller = TerminalSessionController(session: session, resizeDebounce: .milliseconds(30))
        let bytes = Data([0x00, 0x1B, 0x80, 0xFF])

        try await controller.send(bytes)
        await controller.requestResize(columns: 80, rows: 24)
        await controller.requestResize(columns: 100, rows: 30)
        await controller.requestResize(columns: 132, rows: 44)
        try await Task.sleep(for: .milliseconds(80))

        #expect(await session.sentData == [bytes])
        #expect(await session.resizeRequests == [.init(columns: 132, rows: 44)])
        try await controller.close(.detach)
    }
}

private actor EventCollector {
    private(set) var values: [TerminalRenderEvent] = []

    func append(_ event: TerminalRenderEvent) {
        values.append(event)
    }

    func waitForCount(_ count: Int) async {
        for _ in 0 ..< 100 where values.count < count {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private struct TerminalSize: Equatable, Sendable {
    let columns: Int
    let rows: Int
}

private final class FakeProcessSession: ProcessSession, @unchecked Sendable {
    let id = "terminal-fixture"
    let output: AsyncThrowingStream<ProcessOutputChunk, any Error>
    private let continuation: AsyncThrowingStream<ProcessOutputChunk, any Error>.Continuation
    private let state = FakeProcessState()

    init() {
        let stream = AsyncThrowingStream<ProcessOutputChunk, any Error>.makeStream()
        output = stream.stream
        continuation = stream.continuation
    }

    var sentData: [Data] {
        get async { await state.sentData }
    }

    var resizeRequests: [TerminalSize] {
        get async { await state.resizeRequests }
    }

    var terminationSignals: [String] {
        get async { await state.terminationSignals }
    }

    var detachCount: Int {
        get async { await state.detachCount }
    }

    func emit(_ chunk: ProcessOutputChunk) {
        continuation.yield(chunk)
    }

    func send(_ data: Data) async throws {
        await state.send(data)
    }

    func resize(columns: Int, rows: Int) async throws {
        await state.resize(columns: columns, rows: rows)
    }

    func wait() async throws -> ProcessExit {
        ProcessExit(code: 0)
    }

    func terminate(signal: String) async throws {
        await state.terminate(signal)
        continuation.finish()
    }

    func detach() async throws {
        await state.detach()
        continuation.finish()
    }
}

private actor FakeProcessState {
    private(set) var sentData: [Data] = []
    private(set) var resizeRequests: [TerminalSize] = []
    private(set) var terminationSignals: [String] = []
    private(set) var detachCount = 0

    func send(_ data: Data) {
        sentData.append(data)
    }

    func resize(columns: Int, rows: Int) {
        resizeRequests.append(.init(columns: columns, rows: rows))
    }

    func terminate(_ signal: String) {
        terminationSignals.append(signal)
    }

    func detach() {
        detachCount += 1
    }
}
