import SwiftUI

struct RuntimeSettingsView: View {
    var body: some View {
        SettingsForm {
            Section("Install Apple container") {
                InstallRuntimeView(isSettingsSection: true)
            }
            Section("Remove Apple container") {
                UninstallRuntimeView(isSettingsSection: true)
            }
        }
    }
}

struct RuntimeLifecycleAuditView: View {
    var body: some View {
        ScrollView {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    auditSections
                }
                .frame(minWidth: 1060, alignment: .top)

                VStack(alignment: .leading, spacing: 34) {
                    auditSections
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(16)
        }
        .accessibilityIdentifier("runtime-lifecycle-scroll")
        .frame(minWidth: 680, minHeight: 680, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime-lifecycle")
    }

    @ViewBuilder
    private var auditSections: some View {
        InstallRuntimeView(isAuditMode: true)
            .frame(maxWidth: .infinity, alignment: .top)
        RuntimeUpdateSettingsView(isAuditMode: true)
            .frame(maxWidth: .infinity, alignment: .top)
        UninstallRuntimeView(isAuditMode: true)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}
