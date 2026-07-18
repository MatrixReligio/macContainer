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
    public let machineTerminalOpener: any MachineTerminalOpening
    public let containerTerminalOpener: any ContainerTerminalOpening
    public let machineImagePreparer: any MachineImagePreparing
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
        machineTerminalOpener: (any MachineTerminalOpening)? = nil,
        containerTerminalOpener: (any ContainerTerminalOpening)? = nil,
        machineImagePreparer: (any MachineImagePreparing)? = nil,
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
        self.machineTerminalOpener = machineTerminalOpener ?? (
            mode == .fakeRuntime
                ? SimulatedMachineTerminalOpener()
                : ProductionMachineTerminalOpener()
        )
        self.containerTerminalOpener = containerTerminalOpener ?? (
            mode == .fakeRuntime
                ? SimulatedContainerTerminalOpener()
                : ProductionContainerTerminalOpener()
        )
        self.machineImagePreparer = machineImagePreparer ?? (
            mode == .fakeRuntime
                ? SimulatedMachineImagePreparer()
                : ProductionMachineImagePreparer()
        )
        self.now = now
        self.makeID = makeID
    }
}
