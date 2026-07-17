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
                .fontWeight(.semibold)
                .foregroundStyle(Color(nsColor: .labelColor))
            Link("contact@matrixreligio.com", destination: URL(string: "mailto:contact@matrixreligio.com")!)
                .accessibilityLabel("Email Matrix Religio support")
                .accessibilityHint("Opens a message to contact at matrixreligio dot com")
            Text("Apache License 2.0")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(nsColor: .labelColor))
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
