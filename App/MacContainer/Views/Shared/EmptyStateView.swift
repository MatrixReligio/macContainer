import AppKit
import MCAppCore
import SwiftUI

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
    }
}

struct ActivityCenterView: View {
    let center: MCAppCore.ActivityCenter

    var body: some View {
        NavigationStack {
            Group {
                if center.activities.isEmpty {
                    ContentUnavailableView(
                        "No Activities",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Installs, pulls, builds, and updates will appear here.")
                    )
                } else {
                    List(center.activities.values.sorted { $0.startedAt > $1.startedAt }) { activity in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(activity.titleKey)
                                .font(.headline)
                            Text(activity.phaseKey)
                                .foregroundStyle(.secondary)
                            if let progress = activity.progress {
                                ProgressView(value: progress)
                            } else if activity.outcome == nil {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Activity Center")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity-center-content")
    }
}

struct WindowAccessibilityIdentifier: NSViewRepresentable {
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
