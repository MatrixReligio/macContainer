import MCModel

public protocol BuilderBackend: Sendable {
    func start(resources: RuntimeResources) async throws -> BuilderSummary
    func status() async throws -> BuilderSummary
    func stop() async throws
    func delete() async throws
}

public struct BuilderAdapter: BuilderOperations, Sendable {
    private let client: any BuilderBackend
    private let coordinator: OperationCoordinator

    public init(
        client: any BuilderBackend = AppleBuilderBackend(),
        coordinator: OperationCoordinator = OperationCoordinator()
    ) {
        self.client = client
        self.coordinator = coordinator
    }

    public func start(_ request: BuilderStartRequest) async throws -> BuilderSummary {
        try await coordinator.withLock(.builder) {
            try await client.start(resources: request.resources)
        }
    }

    public func status() async throws -> BuilderSummary {
        try await client.status()
    }

    public func stop() async throws {
        try await coordinator.withLock(.builder) {
            try await client.stop()
        }
    }

    public func delete() async throws {
        try await coordinator.withLock(.builder) {
            try await client.delete()
        }
    }
}
