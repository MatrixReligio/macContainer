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
}
