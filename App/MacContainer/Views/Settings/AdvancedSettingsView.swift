import MCAppCore
import MCSystemLifecycle
import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(AppState.self) private var state
    @State private var retainDiagnostics = true
    @State private var auditState: AuditState = .idle
    @State private var activityCenterPresented = false

    private enum AuditState: Equatable {
        case idle
        case running
        case complete(present: Int, unverifiable: Int)
    }

    var body: some View {
        SettingsForm {
            Section("Diagnostics") {
                Toggle("Retain redacted compatibility and rollback diagnostics", isOn: $retainDiagnostics)
                Text("Passwords, tokens, credentials, authorization data, and private temporary paths are redacted.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
            }
            Section("Recovery") {
                Button("Open Activity Center") {
                    activityCenterPresented = true
                }
                .accessibilityIdentifier("settings-open-activity-center")
                Button("Re-run residue audit") {
                    runResidueAudit()
                }
                .disabled(auditState == .running)
                .accessibilityIdentifier("settings-run-residue-audit")
                auditStatus
            }
        }
        .sheet(isPresented: $activityCenterPresented) {
            SettingsActivityCenterSheet(
                center: state.activities,
                isPresented: $activityCenterPresented
            )
        }
    }

    @ViewBuilder
    private var auditStatus: some View {
        switch auditState {
        case .idle:
            EmptyView()
        case .running:
            ProgressView("Auditing owned runtime residue…")
        case let .complete(present, unverifiable):
            if unverifiable > 0 {
                Label(
                    "Audit completed with \(unverifiable) unverifiable categories",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            } else if present > 0 {
                Label(
                    "Audit complete — \(present) owned artifact categories are present",
                    systemImage: "checkmark.circle"
                )
            } else {
                Label("Audit complete — no owned residue detected", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private func runResidueAudit() {
        auditState = .running
        Task {
            let report = await ResidueAuditor(checker: SystemResidueAuditChecker()).audit()
            auditState = .complete(
                present: report.items.count { $0.status == .present },
                unverifiable: report.items.count { $0.status == .unverifiable }
            )
        }
    }
}

private struct SettingsActivityCenterSheet: View {
    let center: ActivityCenter
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            ActivityCenterView(center: center)
            Divider()
            HStack {
                Spacer()
                Button("Close") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("settings-close-activity-center")
            }
            .padding(16)
        }
        .frame(minWidth: 680, minHeight: 460)
    }
}
