import MCSystemLifecycle
import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var retainDiagnostics = true
    @State private var auditState: AuditState = .idle

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
                    openWindow(id: "activity-center")
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
