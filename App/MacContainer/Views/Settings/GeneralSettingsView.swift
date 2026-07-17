import AppKit
import MCAppCore
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var settings = state.environment.settings
        @Bindable var language = state.environment.languageController

        Form {
            Section("Experience") {
                Toggle("Use Simple Mode for new workloads", isOn: $settings.simpleModeEnabled)
                Text("Advanced controls remain one click away and preserve every value you entered.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
            }
            Section("Language") {
                Picker(
                    "Application language",
                    selection: Binding(
                        get: { language.pendingSelection ?? language.selection },
                        set: { requested in
                            language.request(
                                requested,
                                hasUnsavedWork: state.hasUnsavedWork,
                                hasActiveOperations: state.activities.hasActiveOperations
                            )
                        }
                    )
                ) {
                    ForEach(AppLanguage.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .accessibilityIdentifier("app-language-picker")

                if language.requiresRelaunch {
                    Text(languageChangeMessage(language.pendingResult))
                        .font(.subheadline.weight(.semibold))
                    HStack {
                        Button("Cancel") { language.cancelPendingChange() }
                            .accessibilityIdentifier("cancel-language-change")
                        Button("Relaunch") {
                            do {
                                try language.confirmForRelaunch(
                                    hasUnsavedWork: state.hasUnsavedWork,
                                    hasActiveOperations: state.activities.hasActiveOperations
                                )
                                NSApplication.shared.terminate(nil)
                            } catch {}
                        }
                        .disabled(language.pendingResult != .readyToRelaunch)
                        .accessibilityIdentifier("relaunch-for-language")
                    }
                }
            }
            Section("Privacy") {
                Label("No analytics or telemetry are sent by default.", systemImage: "hand.raised.fill")
                Text("Runtime checks download only signed catalog metadata and packages you approve.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func languageChangeMessage(_ result: LanguageChangeResult) -> String {
        switch result {
        case .noChange: "The current language remains active."
        case .saveBeforeRelaunch: "Save or discard the current draft before relaunching."
        case .waitForActivities: "Wait for active operations and terminals to finish before relaunching."
        case .readyToRelaunch: "Relaunch MacContainer to apply the selected language."
        }
    }
}
