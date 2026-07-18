import Foundation

public final class HelperClient: @unchecked Sendable {
    public static let machServiceName = "container.matrixreligio.com.helper"

    private let connectionFactory: @Sendable () -> NSXPCConnection

    public init(
        connectionFactory: @escaping @Sendable () -> NSXPCConnection = {
            NSXPCConnection(machServiceName: HelperClient.machServiceName, options: .privileged)
        }
    ) {
        self.connectionFactory = connectionFactory
    }

    public func makeAuthenticatedConnection() -> NSXPCConnection {
        let connection = connectionFactory()
        connection.setCodeSigningRequirement(CodeSigningRequirements.helper)
        return connection
    }

    public func perform(
        _ request: PrivilegedRequest,
        packageFile: FileHandle? = nil
    ) async throws -> PrivilegedResponse {
        let requestData = try PrivilegedRequestCodec.encode(request)
        let connection = makeAuthenticatedConnection()
        connection.remoteObjectInterface = PrivilegedHelperXPC.interface()

        return try await withCheckedThrowingContinuation { continuation in
            let gate = HelperClientReplyGate(continuation: continuation)
            connection.interruptionHandler = {
                gate.fail(HelperClientError.connectionInterrupted)
            }
            connection.invalidationHandler = {
                gate.fail(HelperClientError.connectionInvalidated)
            }
            connection.activate()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                _ = error
                gate.fail(HelperClientError.connectionInvalidated)
                connection.invalidate()
            }) as? MCPrivilegedHelperXPCProtocol else {
                gate.fail(HelperClientError.proxyUnavailable)
                connection.invalidate()
                return
            }
            proxy.perform(requestData, packageFile: packageFile) { responseData, error in
                defer { connection.invalidate() }
                if let error {
                    gate.fail(error)
                    return
                }
                guard let responseData else {
                    gate.fail(HelperClientError.emptyResponse)
                    return
                }
                do {
                    try gate.succeed(PrivilegedResponseCodec.decode(responseData))
                } catch {
                    gate.fail(error)
                }
            }
        }
    }
}

extension HelperClient: InstallPrivilegedHelping {
    public func install(_ package: VerifiedRuntimePackage) async throws {
        try package.openFile.revalidateIdentity()
        let descriptor = try package.openFile.duplicateFileDescriptor()
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        _ = try await perform(
            .installVerifiedPackage(.init(
                runtimeVersion: package.runtimeVersion,
                sha256: package.sha256
            )),
            packageFile: handle
        )
    }
}

public enum HelperClientError: Error, Equatable, Sendable {
    case connectionInterrupted
    case connectionInvalidated
    case emptyResponse
    case proxyUnavailable
}

private final class HelperClientReplyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<PrivilegedResponse, any Error>?

    init(continuation: CheckedContinuation<PrivilegedResponse, any Error>) {
        self.continuation = continuation
    }

    func succeed(_ response: PrivilegedResponse) {
        take()?.resume(returning: response)
    }

    func fail(_ error: any Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<PrivilegedResponse, any Error>? {
        lock.withLock {
            defer { continuation = nil }
            return continuation
        }
    }
}
