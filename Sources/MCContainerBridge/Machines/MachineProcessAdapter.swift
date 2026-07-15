import Foundation
import MCModel

public struct MachineProcessAdapter: ProcessSession, Sendable {
    public let id: String
    public let output: AsyncThrowingStream<ProcessOutputChunk, any Error>

    private let base: ContainerProcessAdapter

    private init(base: ContainerProcessAdapter) {
        self.base = base
        id = base.id
        output = base.output
    }

    public static func start(_ transport: any ContainerProcessTransport) async throws -> Self {
        let base = try await ContainerProcessAdapter.start(transport)
        return Self(base: base)
    }

    public func send(_ data: Data) async throws {
        try await base.send(data)
    }

    public func resize(columns: Int, rows: Int) async throws {
        try await base.resize(columns: columns, rows: rows)
    }

    public func wait() async throws -> ProcessExit {
        try await base.wait()
    }

    public func terminate(signal: String) async throws {
        try await base.terminate(signal: signal)
    }

    public func detach() async throws {
        try await base.detach()
    }
}
