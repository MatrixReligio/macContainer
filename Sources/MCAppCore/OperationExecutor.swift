import Foundation
import MCContracts
import MCModel
import OSLog

public struct OperationDispatchResult: Equatable, Sendable {
    public let summary: String
    public let itemResults: [ActivityItemResult]

    public init(summary: String, itemResults: [ActivityItemResult] = []) {
        self.summary = summary
        self.itemResults = itemResults
    }
}

public protocol OperationDispatching: Sendable {
    func dispatch(_ draft: OperationDraft) async throws -> OperationDispatchResult
}

public struct SimulatedOperationDispatcher: OperationDispatching, Sendable {
    public init() {}

    public func dispatch(_ draft: OperationDraft) async throws -> OperationDispatchResult {
        OperationDispatchResult(summary: "Simulated \(draft.operationID) completed")
    }
}

public struct OperationExecutionResult: Equatable, Sendable {
    public let operationID: String
    public let activityID: UUID
    public let summary: String

    public init(operationID: String, activityID: UUID, summary: String) {
        self.operationID = operationID
        self.activityID = activityID
        self.summary = summary
    }
}

public enum OperationExecutorError: Error, Equatable, Sendable {
    case unknownOperation(String)
    case capabilityUnavailable(String)
    case validationFailed([ValidationIssue])
}

@MainActor
public final class OperationExecutor {
    private static let logger = Logger(subsystem: "container.matrixreligio.com", category: "operations")

    public let supportedOperationIDs: Set<String>

    private let contract: UpstreamContract
    private let capabilities: Set<String>
    private let dispatcher: any OperationDispatching
    private let activities: ActivityCenter
    private let validator: OperationValidator

    public init(
        contract: UpstreamContract,
        capabilities: Set<String>,
        dispatcher: any OperationDispatching,
        activities: ActivityCenter,
        validator: OperationValidator = OperationValidator()
    ) {
        self.contract = contract
        self.capabilities = capabilities
        self.dispatcher = dispatcher
        self.activities = activities
        self.validator = validator
        supportedOperationIDs = Set(contract.operations.map(\.id))
    }

    public func execute(_ draft: OperationDraft) async throws -> OperationExecutionResult {
        guard let operation = contract.operation(id: draft.operationID) else {
            throw OperationExecutorError.unknownOperation(draft.operationID)
        }
        guard capabilities.contains(operation.id) else {
            throw OperationExecutorError.capabilityUnavailable(operation.id)
        }

        let context = OperationValidator.Context(
            runtimeVersion: contract.runtimeVersion,
            macOSMajor: 26,
            isAppleSilicon: true,
            capabilities: capabilities
        )
        let issues = validator.validate(draft, against: operation, context: context)
        guard issues.isEmpty else {
            throw OperationExecutorError.validationFailed(issues)
        }

        let activityID = activities.start(
            titleKey: "activity.operation.\(operation.id)",
            cancellable: operation.risk != .readOnly
        )
        activities.update(activityID, phaseKey: "activity.phase.running")

        do {
            let dispatchResult = try await dispatcher.dispatch(draft)
            let outcome: ActivityOutcome = dispatchResult.itemResults.contains { $0.outcome == .failed }
                ? .partiallySucceeded
                : .succeeded
            activities.update(activityID, phaseKey: "activity.phase.completed")
            activities.finish(activityID, outcome: outcome, itemResults: dispatchResult.itemResults)
            return OperationExecutionResult(
                operationID: operation.id,
                activityID: activityID,
                summary: dispatchResult.summary
            )
        } catch {
            let mappedError = ErrorMapper().map(
                error,
                domain: Self.errorDomain(for: operation.domain),
                operationID: operation.id,
                activityID: activityID
            )
            Self.logger.error(
                "Operation \(operation.id, privacy: .public) failed: \(mappedError.diagnosticDetail, privacy: .public)"
            )
            activities.update(activityID, phaseKey: "activity.phase.failed")
            activities.finish(
                activityID,
                outcome: .failed,
                error: mappedError
            )
            throw error
        }
    }

    private static func errorDomain(for domain: OperationDomain) -> UserFacingErrorDomain {
        switch domain {
        case .containers: .container
        case .images: .image
        case .builder: .build
        case .networks: .network
        case .volumes: .volume
        case .registries: .registry
        case .machines: .machine
        case .system, .dns, .kernel, .configuration: .system
        case .core: .unknown
        }
    }
}
