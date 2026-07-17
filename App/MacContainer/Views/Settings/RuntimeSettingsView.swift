import SwiftUI

struct RuntimeSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                InstallRuntimeView()
                Divider()
                UninstallRuntimeView()
            }
            .padding()
        }
    }
}

struct RuntimeLifecycleAuditView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            InstallRuntimeView(isAuditMode: true)
                .frame(maxWidth: .infinity, alignment: .top)
            RuntimeUpdateSettingsView(isAuditMode: true)
                .frame(maxWidth: .infinity, alignment: .top)
            UninstallRuntimeView(isAuditMode: true)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .padding(16)
        .frame(minWidth: 1100, minHeight: 680, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime-lifecycle")
    }
}
