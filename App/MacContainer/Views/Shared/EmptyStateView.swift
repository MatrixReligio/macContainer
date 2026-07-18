import AppKit
import MCAppCore
import SwiftUI

struct EmptyStateView: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var diagnostic: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
            if let diagnostic {
                Text(verbatim: diagnostic)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .foregroundStyle(Color(nsColor: .labelColor))
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
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
                            Text(LocalizedStringKey(activity.titleKey))
                                .font(.headline)
                            Text(LocalizedStringKey(activity.phaseKey))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color(nsColor: .labelColor))
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
            setAccessibilityElement(false)
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
