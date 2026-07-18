import MCAppCore
import SwiftUI

struct InstallRuntimeView: View {
    private enum InstallPhase {
        case ready
        case postflightPending
        case complete
    }

    @Environment(AppState.self) private var appState
    @State private var phase: InstallPhase = .ready
    let isAuditMode: Bool
    let isSettingsSection: Bool

    init(isAuditMode: Bool = false, isSettingsSection: Bool = false) {
        self.isAuditMode = isAuditMode
        self.isSettingsSection = isSettingsSection
    }

    var body: some View {
        if isSettingsSection {
            content
                .padding(.vertical, 4)
        } else {
            GroupBox("Install Apple container") {
                content
                    .padding(8)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Apple container 1.1.0", systemImage: "shippingbox.fill")
                .font(.headline)
            Text("Source: developer.apple.com")
                .readableForeground()
            Text("Signer: Apple Inc. - Containerization (UPBK2H6LZM)")
                .font(.subheadline.weight(.semibold))
                .readableForeground()
            Label {
                Text("SHA-256 digest verified")
                    .foregroundStyle(Color(nsColor: .labelColor))
            } icon: {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
            .fontWeight(.semibold)
            Text("Disk impact: up to 420 MB")
            Text("Administrator approval is requested only when installation begins.")
                .font(.subheadline.weight(.semibold))
                .readableForeground()

            Button("Review and install") {
                if isAuditMode {
                    phase = .postflightPending
                } else {
                    Task { await appState.runtimeLifecycle.install() }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isAuditMode && appState.runtimeLifecycle.isBusy)
            .accessibilityIdentifier("install-runtime")

            if isAuditMode, phase == .postflightPending {
                Label("Installing — compatibility postflight pending", systemImage: "hourglass")
                Button("Complete simulated postflight") {
                    phase = .complete
                }
                .accessibilityIdentifier("simulate-install-postflight")
            } else if isAuditMode, phase == .complete {
                Label {
                    Text("Runtime ready")
                        .foregroundStyle(Color(nsColor: .labelColor))
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else if !isAuditMode {
                productionState
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            guard !isAuditMode else { return }
            await appState.runtimeLifecycle.refreshHelperStatus()
        }
    }

    @ViewBuilder
    private var productionState: some View {
        switch appState.runtimeLifecycle.state {
        case .ready:
            EmptyView()
        case .authorizingHelper:
            ProgressView("Checking administrator approval…")
        case .helperApprovalRequired:
            Label("Administrator approval required", systemImage: "lock.shield")
            Text("Allow MacContainer in System Settings > General > Login Items, then check again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button("Open Login Items Settings") {
                    Task { await appState.runtimeLifecycle.openHelperApprovalSettings() }
                }
                Button("Check approval") {
                    Task { await appState.runtimeLifecycle.authorizeHelper() }
                }
            }
        case .installing:
            ProgressView("Installing — compatibility postflight pending")
        case let .installed(version):
            Label("Runtime ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Apple container \(version) passed receipt, payload, kernel, and compatibility checks.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case let .failed(code):
            Label("Installation stopped safely", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
            Text(code)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        case .preparingUninstall, .readyToUninstall, .uninstalling, .uninstalled:
            EmptyView()
        }
    }
}
