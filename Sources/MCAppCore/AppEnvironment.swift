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
    public let now: @Sendable () -> Date
    public let makeID: @Sendable () -> UUID

    public init(
        mode: AppEnvironmentMode = .production,
        settings: SettingsStore = SettingsStore(),
        languageController: LanguageController = LanguageController(),
        runtimeLifecycleService: (any RuntimeLifecycleServicing)? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.mode = mode
        self.settings = settings
        self.languageController = languageController
        self.runtimeLifecycleService = runtimeLifecycleService ?? (
            mode == .fakeRuntime
                ? SimulatedRuntimeLifecycleService()
                : ProductionRuntimeLifecycle()
        )
        self.now = now
        self.makeID = makeID
    }
}
