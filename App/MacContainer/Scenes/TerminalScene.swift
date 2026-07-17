import Foundation
import MCAppCore
import MCModel
import SwiftUI

struct TerminalScene: View {
    private let controller: TerminalSessionController

    init(session: any ProcessSession) {
        controller = TerminalSessionController(session: session)
    }

    var body: some View {
        TerminalSessionView(controller: controller)
    }
}

final class TerminalAuditSession: ProcessSession, @unchecked Sendable {
    let id = "terminal-audit"
    let output: AsyncThrowingStream<ProcessOutputChunk, any Error>
    private let continuation: AsyncThrowingStream<ProcessOutputChunk, any Error>.Continuation

    init() {
        let stream = AsyncThrowingStream<ProcessOutputChunk, any Error>.makeStream()
        output = stream.stream
        continuation = stream.continuation
        continuation.yield(.terminal(Data("MacContainer secure session\r\n".utf8)))
    }

    func send(_: Data) async throws {}
    func resize(columns _: Int, rows _: Int) async throws {}

    func wait() async throws -> ProcessExit {
        ProcessExit(code: 0)
    }

    func terminate(signal _: String) async throws {
        continuation.finish()
    }

    func detach() async throws {
        continuation.finish()
    }
}
