import MCAppCore
import MCCompatibility
import MCSystemLifecycle
import SwiftUI

struct RuntimeUpdateSettingsView: View {
    @Environment(AppState.self) private var state

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
                if settings.runtimeUpdatePreferencesPersistenceFailed {
                    Label("Update preference could not be saved; the previous safe setting was restored.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("runtime-update-preference-error")
                }
                updateAgentStatus

                Divider()
                updateStatus
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
                    Button("Check now") {
                        state.runtimeUpdateState = .checking
                    }
                    .accessibilityIdentifier("check-runtime-update")
                    if case .available = state.runtimeUpdateState {
                        Button("Install compatible update") {
                            state.runtimeUpdateState = .installing(.targetProbes)
                        }
                        .accessibilityIdentifier("install-compatible-update")
                    }
                }

                if isAuditMode {
                    switch state.runtimeUpdateState {
                    case .checking:
                        Button("Complete update check") {
                            state.runtimeUpdateState = .available(version: "1.1.0")
                        }
                        .accessibilityIdentifier("complete-update-check")
                    case .installing:
                        Button("Simulate failed postflight") {
                            state.runtimeUpdateState = .rolledBack(
                                previousVersion: "1.0.0",
                                failedProbeID: .images
                            )
                        }
                        .accessibilityIdentifier("simulate-upgrade-failure")
                        Button("Simulate rollback failure") {
                            state.runtimeUpdateState = .recoveryRequired(
                                code: "rollback.previous-probes.run"
                            )
                        }
                        .accessibilityIdentifier("simulate-update-recovery")
                    case .rolledBack, .recoveryRequired, .held, .pending:
                        Button("Retry after review") {
                            state.runtimeUpdateState = .available(version: "1.1.0")
                        }
                        .accessibilityIdentifier("retry-runtime-update")
                    case .available, .downloading, .upToDate:
                        EmptyView()
                    }
                }

                Text("Administrator approval appears only after download, signature verification, and review.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .onChange(of: settings.automaticallyCheckRuntimeUpdates) { _, enabled in
            Task {
                await state.runtimeUpdateAgentRegistration.reconcile(enabled: enabled)
            }
        }
    }

    @ViewBuilder
    private var updateAgentStatus: some View {
        switch state.runtimeUpdateAgentRegistration.status {
        case .enabled:
            Label("Background update checks are enabled", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .requiresApproval:
            HStack {
                Label("Background checks require approval in System Settings",
                      systemImage: "person.badge.key.fill")
                    .foregroundStyle(.orange)
                Button("Open System Settings") {
                    state.runtimeUpdateAgentRegistration.openApprovalSettings()
                }
                .accessibilityIdentifier("open-update-agent-approval")
            }
        case .notRegistered, .notFound:
            if state.environment.settings.automaticallyCheckRuntimeUpdates {
                Label("Background update checks are not registered",
                      systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
            }
        case .unknown:
            Label("Background update registration could not be verified",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch state.runtimeUpdateState {
        case .checking:
            status("Checking for reviewed runtime updates", symbol: "arrow.triangle.2.circlepath")
        case let .available(version):
            status("Compatible update: \(version)", symbol: "checkmark.seal.fill", color: .green)
        case let .downloading(version):
            status("Downloading verified runtime \(version)", symbol: "arrow.down.circle")
        case let .pending(reason):
            status(pendingText(reason), symbol: "clock.badge.exclamationmark", color: .orange)
        case let .installing(stage):
            if stage == .targetProbes {
                status("Upgrade installed; full compatibility postflight pending", symbol: "hourglass")
            } else {
                status("Installing approved runtime — \(stage.rawValue)", symbol: "gearshape.2")
            }
        case let .held(reason):
            status(heldText(reason), symbol: "pause.circle.fill", color: .orange)
        case let .rolledBack(previousVersion, failedProbeID):
            VStack(alignment: .leading, spacing: 4) {
                status(
                    "Compatibility failed — rolled back to \(previousVersion)",
                    symbol: "arrow.uturn.backward.circle.fill"
                )
                if let failedProbeID {
                    Text("Failed compatibility probe: \(failedProbeID.rawValue)")
                        .font(.caption.monospaced())
                }
            }
        case let .recoveryRequired(code):
            status(
                "Rollback could not restore a verified runtime — recovery required (\(code))",
                symbol: "exclamationmark.triangle.fill",
                color: .red
            )
        case .upToDate:
            status("Runtime is up to date and compatibility verified", symbol: "checkmark.circle.fill", color: .green)
        }
    }

    private func status(
        _ text: String,
        symbol: String,
        color: Color = Color(nsColor: .labelColor)
    ) -> some View {
        Label {
            Text(text).foregroundStyle(Color(nsColor: .labelColor))
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
        .accessibilityIdentifier("runtime-update-status")
    }

    private func pendingText(_ reason: PendingReason) -> String {
        switch reason {
        case .workActive: "Update pending until containers, machines, and builds are idle"
        case .authorizationRequired: "Update pending administrator authorization"
        }
    }

    private func heldText(_ reason: HoldReason) -> String {
        switch reason {
        case .unknownRuntime: "Update held — runtime version has not been reviewed"
        case .appVersionOutsideRange: "Update held — this app version is outside the reviewed range"
        case .unsupportedHost: "Update held — this Mac does not meet the reviewed host requirements"
        case .packageIdentityMismatch: "Update held — package identity verification failed"
        case .previousRollback: "Update held — this runtime previously failed compatibility checks"
        case .explicitConsentRequired: "Update held — storage migration requires explicit consent"
        case .missingPhysicalAttestation: "Update held — physical compatibility proof is missing"
        case .catalogInvalid: "Update held — embedded compatibility catalog is invalid"
        case .rollbackUnavailable: "Update held — a verified rollback point cannot be created"
        case .preflightFailed: "Update held — compatibility preflight failed"
        }
    }
}
