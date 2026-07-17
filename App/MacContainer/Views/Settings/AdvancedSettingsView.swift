import SwiftUI

struct AdvancedSettingsView: View {
    @State private var retainDiagnostics = true

    var body: some View {
        Form {
            Section("Diagnostics") {
                Toggle("Retain redacted compatibility and rollback diagnostics", isOn: $retainDiagnostics)
                Text("Passwords, tokens, credentials, authorization data, and private temporary paths are redacted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Recovery") {
                Button("Open Activity Center") {}
                Button("Re-run residue audit") {}
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
