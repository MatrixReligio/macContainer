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
                Picker("Approved update action", selection: $settings.runtimeUpdateMode) {
                    Text("Check only").tag(RuntimeUpdateMode.checkOnly)
                    Text("Download and notify").tag(RuntimeUpdateMode.downloadAndNotify)
                    Text("Automatic when idle").tag(RuntimeUpdateMode.automaticWhenIdle)
                }
                .pickerStyle(.radioGroup)
                .disabled(!settings.automaticallyCheckRuntimeUpdates)
                .accessibilityIdentifier("runtime-update-mode")
                Text(modeDescription(settings.runtimeUpdateMode))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
                if settings.updatePreferencesPersistenceFailed {
                    Label("Update preference could not be saved; the previous safe setting was restored.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("runtime-update-preference-error")
                }
                updateAgentStatus

                Divider()
                updateStatus
                if isAuditMode {
                    Label {
                        Text("Unknown version 1.2.0 is held — no automatic install")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color(nsColor: .labelColor))
                    } icon: {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    Text("Rollback point: 1.0.0 · verified · retained")
                        .font(.subheadline.monospaced().weight(.semibold))
                        .foregroundStyle(Color(nsColor: .labelColor))
                }

                HStack {
                    Button("Check now") {
                        Task { await state.runtimeUpdates.checkNow() }
                    }
                    .disabled(state.runtimeUpdates.isBusy)
                    .accessibilityIdentifier("check-runtime-update")
                    if case .available = state.runtimeUpdates.state {
                        Button("Install compatible update") {
                            Task { await state.runtimeUpdates.installAvailable() }
                        }
                        .disabled(state.runtimeUpdates.isBusy)
                        .accessibilityIdentifier("install-compatible-update")
                    }
                }

                if isAuditMode {
                    switch state.runtimeUpdates.state {
                    case .checking:
                        Button("Complete update check") {
                            state.runtimeUpdates.setAuditState(.available(version: "1.1.0"))
                        }
                        .accessibilityIdentifier("complete-update-check")
                    case .installing:
                        Button("Simulate failed postflight") {
                            state.runtimeUpdates.setAuditState(.rolledBack(
                                previousVersion: "1.0.0",
                                failedProbeID: .images
                            ))
                        }
                        .accessibilityIdentifier("simulate-upgrade-failure")
                        Button("Simulate rollback failure") {
                            state.runtimeUpdates.setAuditState(.recoveryRequired(
                                code: "rollback.previous-probes.run"
                            ))
                        }
                        .accessibilityIdentifier("simulate-update-recovery")
                    case .rolledBack, .recoveryRequired, .held, .pending:
                        Button("Retry after review") {
                            state.runtimeUpdates.setAuditState(.available(version: "1.1.0"))
                        }
                        .accessibilityIdentifier("retry-runtime-update")
                    case .available, .downloading, .checkFailed, .upToDate:
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
            Label {
                Text("Background update checks are enabled")
                    .readableForeground()
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
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
        switch state.runtimeUpdates.state {
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
        case let .checkFailed(failure):
            status(checkFailureText(failure), symbol: "wifi.exclamationmark", color: .orange)
        case .upToDate:
            status("Runtime is up to date and compatibility verified", symbol: "checkmark.circle.fill", color: .green)
        }
    }

    private func checkFailureText(_ failure: RuntimeUpdateCheckFailure) -> LocalizedStringKey {
        switch failure {
        case .cancelled: "Runtime update check was cancelled"
        case .internalFailure: "Runtime update check could not be completed"
        case .noCandidate: "No reviewed runtime update candidate is available"
        case .offline: "Runtime update service is offline — check your connection and retry"
        case .rateLimited: "Runtime update service is temporarily rate limited — retry later"
        }
    }

    private func modeDescription(_ mode: RuntimeUpdateMode) -> LocalizedStringKey {
        switch mode {
        case .checkOnly:
            "Reports reviewed updates and waits for an explicit install request."
        case .downloadAndNotify:
            "Downloads and verifies an approved package, then waits for your review."
        case .automaticWhenIdle:
            "Installs only compatibility-approved updates after explicit consent when all work is idle."
        }
    }

    private func status(
        _ text: LocalizedStringKey,
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

    private func pendingText(_ reason: PendingReason) -> LocalizedStringKey {
        switch reason {
        case .workActive: "Update pending until containers, machines, and builds are idle"
        case .authorizationRequired: "Update pending administrator authorization"
        }
    }

    private func heldText(_ reason: HoldReason) -> LocalizedStringKey {
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
