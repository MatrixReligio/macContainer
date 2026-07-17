import MCSystemLifecycle
@testable import MCAppCore
import Testing

@MainActor
@Suite("Settings persistence")
struct SettingsStoreTests {
    @Test func `loads explicit automatic update consent`() {
        let persistence = RecordingPreferencesPersistence(value: .init(
            automaticallyChecks: true,
            mode: .automaticWhenIdle,
            consentVersion: RuntimeUpdatePolicy.currentConsentVersion
        ))

        let settings = SettingsStore(updatePreferences: persistence)

        #expect(settings.automaticallyCheckRuntimeUpdates)
        #expect(settings.autoInstallCompatibleRuntimeUpdates)
        #expect(!settings.runtimeUpdatePreferencesPersistenceFailed)
    }

    @Test func `enabling automatic updates forces checks and records current consent`() throws {
        let persistence = RecordingPreferencesPersistence(value: .safeDefaults)
        let settings = SettingsStore(updatePreferences: persistence)
        settings.automaticallyCheckRuntimeUpdates = false

        settings.autoInstallCompatibleRuntimeUpdates = true

        #expect(settings.automaticallyCheckRuntimeUpdates)
        #expect(settings.autoInstallCompatibleRuntimeUpdates)
        let saved = try #require(persistence.saved.last)
        #expect(saved.mode == .automaticWhenIdle)
        #expect(saved.consentVersion == RuntimeUpdatePolicy.currentConsentVersion)
    }

    @Test func `disabling checks also revokes automatic install consent`() throws {
        let automatic = RuntimeUpdatePreferences(
            automaticallyChecks: true,
            mode: .automaticWhenIdle,
            consentVersion: RuntimeUpdatePolicy.currentConsentVersion
        )
        let persistence = RecordingPreferencesPersistence(value: automatic)
        let settings = SettingsStore(updatePreferences: persistence)

        settings.automaticallyCheckRuntimeUpdates = false

        #expect(!settings.automaticallyCheckRuntimeUpdates)
        #expect(!settings.autoInstallCompatibleRuntimeUpdates)
        let saved = try #require(persistence.saved.last)
        #expect(saved == .init(automaticallyChecks: false, mode: .checkOnly, consentVersion: nil))
    }

    @Test func `failed save reverts setting and exposes failure`() {
        let persistence = RecordingPreferencesPersistence(value: .safeDefaults)
        let settings = SettingsStore(updatePreferences: persistence)
        persistence.failSaves = true

        settings.autoInstallCompatibleRuntimeUpdates = true

        #expect(!settings.autoInstallCompatibleRuntimeUpdates)
        #expect(settings.automaticallyCheckRuntimeUpdates)
        #expect(settings.runtimeUpdatePreferencesPersistenceFailed)
    }
}

private final class RecordingPreferencesPersistence: RuntimeUpdatePreferencesPersisting, @unchecked Sendable {
    var value: RuntimeUpdatePreferences
    var saved: [RuntimeUpdatePreferences] = []
    var failSaves = false

    init(value: RuntimeUpdatePreferences) {
        self.value = value
    }

    func load() throws -> RuntimeUpdatePreferences {
        value
    }

    func save(_ preferences: RuntimeUpdatePreferences) throws {
        if failSaves { throw RecordingPreferencesError.failed }
        value = preferences
        saved.append(preferences)
    }
}

private enum RecordingPreferencesError: Error {
    case failed
}
