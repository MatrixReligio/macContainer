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

    public var runtimeUpdateMode: RuntimeUpdateMode {
        didSet { persistUpdatePreferences(changed: .mode) }
    }

    public var autoInstallCompatibleRuntimeUpdates: Bool {
        get { runtimeUpdateMode == .automaticWhenIdle }
        set { runtimeUpdateMode = newValue ? .automaticWhenIdle : .checkOnly }
    }

    public private(set) var updatePreferencesPersistenceFailed: Bool

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
            mode: autoInstallCompatibleRuntimeUpdates ? .automaticWhenIdle : .checkOnly
        )
        let loaded: RuntimeUpdatePreferences
        if let updatePreferences {
            do {
                loaded = try updatePreferences.load()
                updatePreferencesPersistenceFailed = false
            } catch {
                loaded = .safeDefaults
                updatePreferencesPersistenceFailed = true
            }
        } else {
            loaded = fallback
            updatePreferencesPersistenceFailed = false
        }
        self.automaticallyCheckRuntimeUpdates = loaded.automaticallyChecks
        runtimeUpdateMode = loaded.mode
        lastPersistedUpdatePreferences = loaded
    }

    private func persistUpdatePreferences(changed: UpdatePreferenceChange) {
        guard !normalizingUpdatePreferences else { return }
        normalizingUpdatePreferences = true
        defer { normalizingUpdatePreferences = false }

        switch changed {
        case .checks where !automaticallyCheckRuntimeUpdates:
            runtimeUpdateMode = .checkOnly
        case .mode:
            automaticallyCheckRuntimeUpdates = true
        default:
            break
        }

        let preferences = Self.preferences(
            checks: automaticallyCheckRuntimeUpdates,
            mode: runtimeUpdateMode
        )
        guard let updatePreferences else {
            lastPersistedUpdatePreferences = preferences
            updatePreferencesPersistenceFailed = false
            return
        }
        do {
            try updatePreferences.save(preferences)
            lastPersistedUpdatePreferences = preferences
            updatePreferencesPersistenceFailed = false
        } catch {
            automaticallyCheckRuntimeUpdates = lastPersistedUpdatePreferences.automaticallyChecks
            runtimeUpdateMode = lastPersistedUpdatePreferences.mode
            updatePreferencesPersistenceFailed = true
        }
    }

    private static func preferences(
        checks: Bool,
        mode: RuntimeUpdateMode
    ) -> RuntimeUpdatePreferences {
        .init(
            automaticallyChecks: mode == .automaticWhenIdle ? true : checks,
            mode: mode,
            consentVersion: mode == .automaticWhenIdle ? RuntimeUpdatePolicy.currentConsentVersion : nil
        )
    }
}

private enum UpdatePreferenceChange {
    case checks
    case mode
}
