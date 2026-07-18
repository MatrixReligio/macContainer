import MCContracts
import MCModel
import MCSystemLifecycle
import Observation
import SwiftUI

public enum AppRoute: String, CaseIterable, Codable, Sendable {
    case overview
    case containers
    case images
    case builds
    case machines
    case networks
    case volumes
    case registries
    case system
}

public enum HealthState: String, Codable, Sendable {
    case healthy
    case attention
    case unavailable
    case checking
}

public enum CreationIntent: String, Codable, Sendable {
    case workload
    case container
    case machine
}

public struct ResourceSelection: Equatable, Sendable {
    public let id: String
    public let name: String
    public let status: String
    public let kind: String
    public let detail: String
    public let attributes: [String: String]

    public init(
        id: String,
        name: String,
        status: String,
        kind: String,
        detail: String = "",
        attributes: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.kind = kind
        self.detail = detail
        self.attributes = attributes
    }
}

@MainActor
@Observable
public final class AppState {
    public var selection: AppRoute = .overview {
        didSet {
            if selection != oldValue {
                selectedResource = nil
            }
        }
    }

    public var columnVisibility: NavigationSplitViewVisibility = .all
    public var activityCenterPresented = false
    public var simpleModePresented = false
    public var simpleModeInitialTemplateID = "quick-run"
    public var creationIntent: CreationIntent = .workload
    public var health: HealthState = .checking
    public var hasUnsavedWork = false
    public var selectedResource: ResourceSelection?
    public let activities: ActivityCenter
    public let appUpdates: AppUpdateController
    public let runtimeLifecycle: RuntimeLifecycleController
    public let runtimeUpdateAgentRegistration: RuntimeUpdateAgentRegistrationController
    public let runtimeUpdates: RuntimeUpdateController
    public let resourceBrowser: RuntimeResourceBrowserController
    public let operationExecutor: OperationExecutor
    public let environment: AppEnvironment

    public init(environment: AppEnvironment = AppEnvironment()) {
        self.environment = environment
        activities = ActivityCenter(now: environment.now, makeID: environment.makeID)
        appUpdates = AppUpdateController(
            automaticallyChecksForUpdates: environment.mode == .production
        )
        runtimeLifecycle = RuntimeLifecycleController(service: environment.runtimeLifecycleService)
        runtimeUpdateAgentRegistration = RuntimeUpdateAgentRegistrationController(
            service: environment.runtimeUpdateAgentService
        )
        runtimeUpdates = RuntimeUpdateController(
            service: environment.runtimeUpdateManager,
            initialState: environment.mode == .fakeRuntime
                ? .available(version: "1.1.0")
                : .checking
        )
        resourceBrowser = RuntimeResourceBrowserController(
            provider: environment.runtimeResourceProvider,
            activities: activities
        )
        let contract: UpstreamContract
        do {
            contract = try ContractRepository.bundled(
                version: RuntimeVersion(major: 1, minor: 1, patch: 0)
            )
        } catch {
            preconditionFailure("Bundled Apple container contract is unavailable: \(error)")
        }
        operationExecutor = OperationExecutor(
            contract: contract,
            capabilities: Set(contract.operations.map(\.id)),
            dispatcher: environment.operationDispatcher,
            activities: activities
        )
        health = environment.mode == .fakeRuntime ? .healthy : .checking
    }

    public func executeOperation(_ draft: OperationDraft) async throws -> OperationExecutionResult {
        if draft.operationID == "machines.create", case let .string(imageReference)? = draft.fields["image"]?.value {
            try await environment.machineImagePreparer.prepareIfNeeded(imageReference: imageReference)
        }
        let result = try await operationExecutor.execute(draft)
        if let route = Self.resourceRoute(after: draft.operationID) {
            await resourceBrowser.refresh(route)
        }
        return result
    }

    public func refreshOverview() async {
        await resourceBrowser.refreshOverview()
        let runtime = resourceBrowser.resources(for: .system).first
        health = switch runtime?.status {
        case "Running": .healthy
        case "Starting", "Stopping": .attention
        case nil: .unavailable
        default: .unavailable
        }
    }

    public func openMachineTerminal(machineID: String) async throws -> TerminalSessionController {
        let session = try await environment.machineTerminalOpener.open(machineID: machineID)
        return TerminalSessionController(session: session)
    }

    public func openContainerTerminal(containerID: String) async throws -> TerminalSessionController {
        let session = try await environment.containerTerminalOpener.open(containerID: containerID)
        return TerminalSessionController(session: session)
    }

    public static func resourceRoute(after operationID: String) -> AppRoute? {
        switch operationID {
        case "core.run", "containers.create": .containers
        case "machines.create": .machines
        case "networks.create": .networks
        case "volumes.create": .volumes
        case "images.pull", "core.build": .images
        case "registries.login": .registries
        default: nil
        }
    }
}
