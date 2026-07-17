import Foundation
import MCSystemLifecycle

public enum AppEnvironmentMode: String, Sendable {
    case production
    case fakeRuntime
}

@MainActor
public struct AppEnvironment {
    public let mode: AppEnvironmentMode
    public let settings: SettingsStore
    public let languageController: LanguageController
    public let runtimeLifecycleService: any RuntimeLifecycleServicing
    public let runtimeUpdateAgentService: any RuntimeUpdateAgentRegistering
    public let runtimeUpdateManager: any RuntimeUpdateManaging
    public let runtimeResourceProvider: any RuntimeResourceProviding
    public let operationDispatcher: any OperationDispatching
    public let now: @Sendable () -> Date
    public let makeID: @Sendable () -> UUID

    public init(
        mode: AppEnvironmentMode = .production,
        settings: SettingsStore? = nil,
        languageController: LanguageController = LanguageController(),
        runtimeLifecycleService: (any RuntimeLifecycleServicing)? = nil,
        runtimeUpdateAgentService: (any RuntimeUpdateAgentRegistering)? = nil,
        runtimeUpdateManager: (any RuntimeUpdateManaging)? = nil,
        runtimeResourceProvider: (any RuntimeResourceProviding)? = nil,
        operationDispatcher: (any OperationDispatching)? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.mode = mode
        self.settings = settings ?? SettingsStore(
            updatePreferences: mode == .production ? RuntimeUpdatePreferencesStore() : nil
        )
        self.languageController = languageController
        self.runtimeLifecycleService = runtimeLifecycleService ?? (
            mode == .fakeRuntime
                ? SimulatedRuntimeLifecycleService()
                : ProductionRuntimeLifecycle()
        )
        self.runtimeUpdateAgentService = runtimeUpdateAgentService ?? (
            mode == .fakeRuntime
                ? SimulatedRuntimeUpdateAgentRegistrar()
                : RuntimeUpdateAgentRegistrar()
        )
        self.runtimeUpdateManager = runtimeUpdateManager ?? (
            mode == .fakeRuntime
                ? SimulatedRuntimeUpdateManager()
                : ProductionRuntimeUpdateManager()
        )
        self.runtimeResourceProvider = runtimeResourceProvider ?? (
            mode == .fakeRuntime
                ? SimulatedRuntimeResourceProvider()
                : ProductionRuntimeResourceProvider()
        )
        self.operationDispatcher = operationDispatcher ?? (
            mode == .fakeRuntime
                ? SimulatedOperationDispatcher()
                : BridgeOperationDispatcher()
        )
        self.now = now
        self.makeID = makeID
    }
}
