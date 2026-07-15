import Foundation
import MCModel

public protocol NetworkBackend: Sendable {
    func create(_ request: NetworkCreateRequest) async throws -> NetworkDetail
    func delete(id: String) async throws
    func prune() async throws -> PruneResult
    func list() async throws -> [NetworkDetail]
    func inspect(id: String) async throws -> NetworkDetail
}

public enum NetworkAdapterError: Error, Equatable, Sendable {
    case duplicateName(String)
    case identifierNotFound(String)
    case ambiguousIdentifier(String)
}

public struct NetworkAdapter: NetworkOperations, Sendable {
    private let client: any NetworkBackend
    private let coordinator: OperationCoordinator

    public init(
        client: any NetworkBackend = AppleNetworkBackend(),
        coordinator: OperationCoordinator = OperationCoordinator()
    ) {
        self.client = client
        self.coordinator = coordinator
    }

    public func create(_ request: NetworkCreateRequest) async throws -> NetworkSummary {
        try await coordinator.withLock(.network(request.name)) {
            let existing = try await client.list()
            guard !existing.contains(where: { $0.summary.name == request.name }) else {
                throw NetworkAdapterError.duplicateName(request.name)
            }
            return try await client.create(request).summary
        }
    }

    public func delete(ids: [String]) async throws -> [BatchItemResult] {
        let inventory = try await client.list()
        var results: [BatchItemResult] = []
        results.reserveCapacity(ids.count)
        for requestedID in ids {
            try Task.checkCancellation()
            let network: NetworkDetail
            do {
                network = try Self.resolve(requestedID, inventory: inventory)
            } catch {
                results.append(Self.failure(id: requestedID, error: error))
                continue
            }
            guard !network.summary.builtIn else {
                results.append(
                    BatchItemResult(
                        id: requestedID,
                        succeeded: false,
                        error: UserFacingError(
                            code: "network.builtin.protected",
                            messageKey: "error.network.builtin.protected"
                        )
                    )
                )
                continue
            }
            do {
                try await coordinator.withLock(.network(network.summary.id)) {
                    try await client.delete(id: network.summary.id)
                }
                results.append(BatchItemResult(id: requestedID, succeeded: true))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                results.append(Self.failure(id: requestedID, error: error))
            }
        }
        return results
    }

    public func prune() async throws -> PruneResult {
        try await coordinator.withLock(.lifecycle) {
            try await client.prune()
        }
    }

    public func list() async throws -> [NetworkSummary] {
        try await client.list().map(\.summary)
    }

    public func inspect(id: String) async throws -> NetworkDetail {
        let resolved = try await Self.resolve(id, inventory: client.list())
        return try await client.inspect(id: resolved.summary.id)
    }

    private static func resolve(
        _ requestedID: String,
        inventory: [NetworkDetail]
    ) throws -> NetworkDetail {
        if let exact = inventory.first(where: { $0.summary.id == requestedID }) {
            return exact
        }
        let matches = inventory.filter { $0.summary.id.hasPrefix(requestedID) }
        switch matches.count {
        case 0: throw NetworkAdapterError.identifierNotFound(requestedID)
        case 1: return matches[0]
        default: throw NetworkAdapterError.ambiguousIdentifier(requestedID)
        }
    }

    private static func failure(id: String, error: any Error) -> BatchItemResult {
        let code = switch error {
        case NetworkAdapterError.identifierNotFound: "network.identifier.not-found"
        case NetworkAdapterError.ambiguousIdentifier: "network.identifier.ambiguous"
        default: "network.delete.failed"
        }
        return BatchItemResult(
            id: id,
            succeeded: false,
            error: UserFacingError(
                code: code,
                messageKey: "error.\(code)",
                redactedDetails: String(describing: type(of: error))
            )
        )
    }
}
