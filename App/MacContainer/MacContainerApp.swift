import AppKit
import SwiftUI

@main
struct MacContainerApp: App {
    var body: some Scene {
        WindowGroup("MacContainer", id: "main-window") {
            ContentView()
        }
        .defaultSize(width: 1_080, height: 720)
    }
}

private struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 44, weight: .medium))
                .accessibilityHidden(true)
            Text("MacContainer")
                .font(.title)
            Text("Apple container management is being prepared.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowAccessibilityIdentifier("main-window"))
    }
}

private struct WindowAccessibilityIdentifier: NSViewRepresentable {
    let identifier: String

    init(_ identifier: String) {
        self.identifier = identifier
    }

    func makeNSView(context: Context) -> IdentifierView {
        IdentifierView(identifier: identifier)
    }

    func updateNSView(_ nsView: IdentifierView, context: Context) {
        nsView.accessibilityID = identifier
        nsView.applyIdentifier()
    }

    @MainActor
    final class IdentifierView: NSView {
        var accessibilityID: String

        init(identifier: String) {
            accessibilityID = identifier
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyIdentifier()
        }

        func applyIdentifier() {
            window?.setAccessibilityIdentifier(accessibilityID)
        }
    }
}
