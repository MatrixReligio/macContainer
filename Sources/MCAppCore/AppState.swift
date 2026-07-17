import MCContracts
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

public struct ResourceSelection: Equatable, Sendable {
    public let id: String
    public let name: String
    public let status: String
    public let kind: String

    public init(id: String, name: String, status: String, kind: String) {
        self.id = id
        self.name = name
        self.status = status
        self.kind = kind
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
}
