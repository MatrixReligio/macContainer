import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("MacContainer")
                .font(.largeTitle.bold())
            Text("Version 0.1.0")
                .foregroundStyle(.secondary)
            Link("contact@matrixreligio.com", destination: URL(string: "mailto:contact@matrixreligio.com")!)
            Text("Apache License 2.0")
                .font(.caption)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
