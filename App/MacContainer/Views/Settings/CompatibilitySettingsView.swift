import SwiftUI

struct CompatibilitySettingsView: View {
    var body: some View {
        Form {
            Section("Policy") {
                Label("Fail closed for unknown runtime versions", systemImage: "lock.shield.fill")
                Text("Unknown, incomplete, or stale compatibility evidence blocks automatic installation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Required probe domains") {
                ForEach([
                    "Containers and processes", "Images and registries", "Builds and builders",
                    "Networks and DNS", "Volumes and persistence", "Machines and kernels",
                    "Configuration, system services, and cleanup"
                ], id: \.self) { domain in
                    Label(domain, systemImage: "checkmark.circle")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
