import Foundation

public enum AppEnvironmentMode: String, Sendable {
    case production
    case fakeRuntime
}

@MainActor
public struct AppEnvironment {
    public let mode: AppEnvironmentMode
    public let settings: SettingsStore
    public let now: @Sendable () -> Date
    public let makeID: @Sendable () -> UUID

    public init(
        mode: AppEnvironmentMode = .production,
        settings: SettingsStore = SettingsStore(),
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.mode = mode
        self.settings = settings
        self.now = now
        self.makeID = makeID
    }
}
