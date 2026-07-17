import MCAppCore
import SwiftUI

struct AboutSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            VStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
                Text("MacContainer")
                    .font(.largeTitle.bold())
                    .readableForeground()
                Text("Version \(appVersion)")
                    .fontWeight(.semibold)
                    .readableForeground()
                Link("contact@matrixreligio.com", destination: URL(string: "mailto:contact@matrixreligio.com")!)
                    .accessibilityLabel("Email Matrix Religio support")
                    .accessibilityHint("Opens a message to contact at matrixreligio dot com")
                Text("Apache License 2.0")
                    .font(.subheadline.weight(.semibold))
                    .readableForeground()
            }
            .frame(maxWidth: .infinity)

            Section("Application updates") {
                Toggle(
                    "Automatically check for signed application updates",
                    isOn: automaticChecksBinding
                )
                LabeledContent("Status") {
                    Text(updateStatus)
                        .readableForeground()
                }
                if case let .failed(message) = state.appUpdates.state {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                Button("Check for Application Updates") {
                    state.appUpdates.checkNow()
                }
                .disabled(state.appUpdates.state == .checking)
                .accessibilityIdentifier("check-for-app-updates")

                if state.appUpdates.hasPendingRelaunch {
                    Text(relaunchGuidance)
                        .foregroundStyle(.secondary)
                    Button("Continue Update and Relaunch") {
                        state.appUpdates.resumeRelaunch(
                            hasUnsavedWork: state.hasUnsavedWork,
                            hasActiveOperations: state.activities.hasActiveOperations
                        )
                    }
                    .accessibilityIdentifier("continue-app-update-relaunch")
                }

                // swiftlint:disable:next line_length
                Text("Application updates are signed and handled separately from Apple container runtime updates, which always require compatibility approval.")
                    .font(.footnote)
                    .readableForeground()
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var automaticChecksBinding: Binding<Bool> {
        Binding(
            get: { state.appUpdates.automaticallyChecksForUpdates },
            set: { state.appUpdates.setAutomaticallyChecksForUpdates($0) }
        )
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var updateStatus: LocalizedStringKey {
        switch state.appUpdates.state {
        case .idle: "Ready"
        case .checking: "Checking for application updates…"
        case let .available(version): "Application update \(version) is available"
        case .upToDate: "MacContainer is up to date"
        case .unavailable: "Application update service is not ready"
        case .failed: "Application update check failed"
        }
    }

    private var relaunchGuidance: LocalizedStringKey {
        switch state.appUpdates.relaunchSafety {
        case .ready: "Ready to install and relaunch"
        case .saveOrDiscardDraft: "Save or discard the current draft before relaunching"
        case .waitForActivities: "Wait for active operations and terminals to finish before relaunching"
        }
    }
}
