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
                            activityTitle(activity.titleKey)
                                .font(.headline)
                            activityPhase(activity.phaseKey)
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

    private func activityTitle(_ key: String) -> Text {
        if key.hasPrefix("activity.operation.") {
            return Text("Operation")
        }
        let components = key.split(separator: ".")
        guard components.count == 3 else { return Text("Operation") }
        let action = switch components[2] {
        case "refresh": Text("Refresh")
        case "delete": Text("Delete")
        case "start": Text("Start")
        case "stop": Text("Stop")
        case "configure": Text("Configure")
        default: Text("Operation")
        }
        return action + Text(verbatim: " — ") + resourceTitle(String(components[1]))
    }

    private func resourceTitle(_ route: String) -> Text {
        switch route {
        case "overview": Text("Overview")
        case "containers": Text("Containers")
        case "images": Text("Images")
        case "builds": Text("Builds")
        case "machines": Text("Machines")
        case "networks": Text("Networks")
        case "volumes": Text("Volumes")
        case "registries": Text("Registries")
        case "system": Text("System")
        default: Text("Operation")
        }
    }

    private func activityPhase(_ key: String) -> Text {
        switch key {
        case "activity.phase.preparing": Text("Preparing")
        case "activity.phase.running": Text("Running")
        case "activity.phase.downloading": Text("Downloading")
        case "activity.phase.completed": Text("Completed")
        case "activity.phase.failed": Text("Failed")
        case "activity.phase.cancelled": Text("Cancelled")
        default: Text("Running")
        }
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
