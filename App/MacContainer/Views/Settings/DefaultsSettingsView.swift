import SwiftUI

struct DefaultsSettingsView: View {
    @State private var libraryPresented = false

    var body: some View {
        SettingsForm {
            Section("Safe defaults") {
                accessibleDefault("Network exposure", value: "Localhost only")
                accessibleDefault("Workspace sharing", value: "Selected folder only")
                accessibleDefault("High-impact capabilities", value: "Off")
                accessibleDefault("Resource sizing", value: "Host-aware")
            }
            Section("Templates") {
                Text("Eight built-in scenarios are immutable. Imported templates are migrated and checked for secrets.")
                Button("Open Template Library") {
                    libraryPresented = true
                }
                .accessibilityIdentifier("open-template-library")
            }
        }
        .sheet(isPresented: $libraryPresented) {
            TemplateLibraryView(isPresented: $libraryPresented)
        }
    }

    private func accessibleDefault(
        _ label: LocalizedStringKey,
        value: LocalizedStringKey
    ) -> some View {
        LabeledContent(label) {
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(Color(nsColor: .labelColor))
        }
    }
}
