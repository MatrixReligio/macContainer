import MCAppCore
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var settings = state.environment.settings

        Form {
            Section("Experience") {
                Toggle("Use Simple Mode for new workloads", isOn: $settings.simpleModeEnabled)
                Text("Advanced controls remain one click away and preserve every value you entered.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Label("No analytics or telemetry are sent by default.", systemImage: "hand.raised.fill")
                Text("Runtime checks download only signed catalog metadata and packages you approve.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
