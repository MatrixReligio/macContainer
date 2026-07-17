import Foundation
import Observation

@MainActor
@Observable
public final class SettingsStore {
    public var simpleModeEnabled: Bool
    public var automaticallyCheckRuntimeUpdates: Bool
    public var autoInstallCompatibleRuntimeUpdates: Bool

    public init(
        simpleModeEnabled: Bool = true,
        automaticallyCheckRuntimeUpdates: Bool = true,
        autoInstallCompatibleRuntimeUpdates: Bool = false
    ) {
        self.simpleModeEnabled = simpleModeEnabled
        self.automaticallyCheckRuntimeUpdates = automaticallyCheckRuntimeUpdates
        self.autoInstallCompatibleRuntimeUpdates = autoInstallCompatibleRuntimeUpdates
    }
}
