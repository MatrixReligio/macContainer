import SwiftUI

struct DefaultsSettingsView: View {
    var body: some View {
        Form {
            Section("Safe defaults") {
                accessibleDefault("Network exposure", value: "Localhost only")
                accessibleDefault("Workspace sharing", value: "Selected folder only")
                accessibleDefault("High-impact capabilities", value: "Off")
                accessibleDefault("Resource sizing", value: "Host-aware")
            }
            Section("Templates") {
                Text("Eight built-in scenarios are immutable. Imported templates are migrated and checked for secrets.")
                Button("Open Template Library") {}
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func accessibleDefault(_ label: String, value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(Color(nsColor: .labelColor))
        }
    }
}
