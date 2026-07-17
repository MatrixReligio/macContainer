import Foundation
import MCSystemLifecycle
import Observation

@MainActor
@Observable
public final class SettingsStore {
    public var simpleModeEnabled: Bool
    public var automaticallyCheckRuntimeUpdates: Bool {
        didSet { persistUpdatePreferences(changed: .checks) }
    }
    public var autoInstallCompatibleRuntimeUpdates: Bool {
        didSet { persistUpdatePreferences(changed: .automaticInstall) }
    }
    public private(set) var runtimeUpdatePreferencesPersistenceFailed: Bool

    @ObservationIgnored private let updatePreferences: (any RuntimeUpdatePreferencesPersisting)?
    @ObservationIgnored private var normalizingUpdatePreferences = false
    @ObservationIgnored private var lastPersistedUpdatePreferences: RuntimeUpdatePreferences

    public init(
        simpleModeEnabled: Bool = true,
        automaticallyCheckRuntimeUpdates: Bool = true,
        autoInstallCompatibleRuntimeUpdates: Bool = false,
        updatePreferences: (any RuntimeUpdatePreferencesPersisting)? = nil
    ) {
        self.simpleModeEnabled = simpleModeEnabled
        self.updatePreferences = updatePreferences
        let fallback = Self.preferences(
            checks: automaticallyCheckRuntimeUpdates,
            automaticInstall: autoInstallCompatibleRuntimeUpdates
        )
        let loaded: RuntimeUpdatePreferences
        if let updatePreferences {
            do {
                loaded = try updatePreferences.load()
                runtimeUpdatePreferencesPersistenceFailed = false
            } catch {
                loaded = .safeDefaults
                runtimeUpdatePreferencesPersistenceFailed = true
            }
        } else {
            loaded = fallback
            runtimeUpdatePreferencesPersistenceFailed = false
        }
        self.automaticallyCheckRuntimeUpdates = loaded.automaticallyChecks
        self.autoInstallCompatibleRuntimeUpdates = loaded.mode == .automaticWhenIdle
        lastPersistedUpdatePreferences = loaded
    }

    private func persistUpdatePreferences(changed: UpdatePreferenceChange) {
        guard !normalizingUpdatePreferences else { return }
        normalizingUpdatePreferences = true
        defer { normalizingUpdatePreferences = false }

        switch changed {
        case .checks where !automaticallyCheckRuntimeUpdates:
            autoInstallCompatibleRuntimeUpdates = false
        case .automaticInstall where autoInstallCompatibleRuntimeUpdates:
            automaticallyCheckRuntimeUpdates = true
        default:
            break
        }

        let preferences = Self.preferences(
            checks: automaticallyCheckRuntimeUpdates,
            automaticInstall: autoInstallCompatibleRuntimeUpdates
        )
        guard let updatePreferences else {
            lastPersistedUpdatePreferences = preferences
            runtimeUpdatePreferencesPersistenceFailed = false
            return
        }
        do {
            try updatePreferences.save(preferences)
            lastPersistedUpdatePreferences = preferences
            runtimeUpdatePreferencesPersistenceFailed = false
        } catch {
            automaticallyCheckRuntimeUpdates = lastPersistedUpdatePreferences.automaticallyChecks
            autoInstallCompatibleRuntimeUpdates =
                lastPersistedUpdatePreferences.mode == .automaticWhenIdle
            runtimeUpdatePreferencesPersistenceFailed = true
        }
    }

    private static func preferences(
        checks: Bool,
        automaticInstall: Bool
    ) -> RuntimeUpdatePreferences {
        .init(
            automaticallyChecks: automaticInstall ? true : checks,
            mode: automaticInstall ? .automaticWhenIdle : .checkOnly,
            consentVersion: automaticInstall ? RuntimeUpdatePolicy.currentConsentVersion : nil
        )
    }
}

private enum UpdatePreferenceChange {
    case checks
    case automaticInstall
}
