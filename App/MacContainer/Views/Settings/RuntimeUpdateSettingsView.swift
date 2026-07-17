import MCAppCore
import SwiftUI

struct RuntimeUpdateSettingsView: View {
    private enum UpdatePhase {
        case ready
        case postflightPending
        case rolledBack
    }

    @Environment(AppState.self) private var state
    @State private var phase: UpdatePhase = .ready

    let isAuditMode: Bool

    init(isAuditMode: Bool = false) {
        self.isAuditMode = isAuditMode
    }

    var body: some View {
        @Bindable var settings = state.environment.settings

        GroupBox("Runtime updates") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    "Automatically check for signed runtime updates",
                    isOn: $settings.automaticallyCheckRuntimeUpdates
                )
                Toggle(
                    "Automatically install only compatibility-approved updates",
                    isOn: $settings.autoInstallCompatibleRuntimeUpdates
                )
                Text(
                    settings.autoInstallCompatibleRuntimeUpdates
                        ? "Automatic installation is limited to compatibility-approved updates."
                        : "Automatic installation is off until you explicitly opt in."
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(nsColor: .labelColor))

                Divider()
                Label {
                    Text("Compatible update: 1.1.0")
                        .foregroundStyle(Color(nsColor: .labelColor))
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                Label {
                    Text("Unknown version 1.2.0 is held — no automatic install")
                        .foregroundStyle(Color(nsColor: .labelColor))
                } icon: {
                    Image(systemName: "pause.circle.fill")
                        .foregroundStyle(.orange)
                }
                Text("Rollback point: 1.0.0 · verified · retained")
                    .font(.caption.monospaced())

                HStack {
                    Button("Check now") {}
                        .accessibilityIdentifier("check-runtime-update")
                    Button("Install compatible update") {
                        phase = .postflightPending
                    }
                    .accessibilityIdentifier("install-compatible-update")
                }

                if phase == .postflightPending {
                    Label("Upgrade installed; full compatibility postflight pending", systemImage: "hourglass")
                    if isAuditMode {
                        Button("Simulate failed postflight") {
                            phase = .rolledBack
                        }
                        .accessibilityIdentifier("simulate-upgrade-failure")
                    }
                } else if phase == .rolledBack {
                    Label(
                        "Compatibility failed — rolled back to 1.0.0",
                        systemImage: "arrow.uturn.backward.circle.fill"
                    )
                    .foregroundStyle(Color(nsColor: .labelColor))
                    Button("Retry after review") {
                        phase = .ready
                    }
                    .accessibilityIdentifier("retry-runtime-update")
                }

                Text("Administrator approval appears only after download, signature verification, and review.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}
