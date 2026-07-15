import Foundation

public protocol ProcessSession: Sendable {
    var id: String { get }
    var output: AsyncThrowingStream<ProcessOutputChunk, any Error> { get }
    func send(_ data: Data) async throws
    func resize(columns: Int, rows: Int) async throws
    func wait() async throws -> ProcessExit
    func terminate(signal: String) async throws
    func detach() async throws
}

public enum ProcessOutputChunk: Equatable, Sendable {
    case stdout(Data)
    case stderr(Data)
    case terminal(Data)
}

public struct ProcessExit: Codable, Equatable, Sendable {
    public let code: Int32
    public let signal: String?

    public init(code: Int32, signal: String? = nil) {
        self.code = code
        self.signal = signal
    }
}
