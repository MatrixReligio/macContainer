import SwiftUI

struct AdvancedSettingsView: View {
    @State private var retainDiagnostics = true

    var body: some View {
        SettingsForm {
            Section("Diagnostics") {
                Toggle("Retain redacted compatibility and rollback diagnostics", isOn: $retainDiagnostics)
                Text("Passwords, tokens, credentials, authorization data, and private temporary paths are redacted.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
            }
            Section("Recovery") {
                Button("Open Activity Center") {}
                Button("Re-run residue audit") {}
            }
        }
    }
}
