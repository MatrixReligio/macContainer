import SwiftUI

struct DefaultsSettingsView: View {
    var body: some View {
        Form {
            Section("Safe defaults") {
                LabeledContent("Network exposure", value: "Localhost only")
                LabeledContent("Workspace sharing", value: "Selected folder only")
                LabeledContent("High-impact capabilities", value: "Off")
                LabeledContent("Resource sizing", value: "Host-aware")
            }
            Section("Templates") {
                Text("Eight built-in scenarios are immutable. Imported templates are migrated and checked for secrets.")
                Button("Open Template Library") {}
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
