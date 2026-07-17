import MCAppCore
import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var settings = state.environment.settings

        VStack(spacing: 26) {
            Spacer()

            Image(systemName: "shippingbox.and.arrow.backward.fill")
                .font(.system(size: 64, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Welcome to MacContainer")
                    .font(.largeTitle.bold())
                Text("Run Apple containers with native controls, safe defaults, and no Terminal setup.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 14) {
                readinessCard(symbol: "checkmark.circle.fill", title: "macOS 26", detail: "Supported")
                readinessCard(symbol: "cpu.fill", title: "Apple silicon", detail: "Ready")
                readinessCard(symbol: "shippingbox.fill", title: "Runtime", detail: "Ready")
            }
            .accessibilityElement(children: .contain)

            Text("macOS 26 · Apple silicon · Runtime ready")
                .font(.headline)

            GroupBox("Runtime updates") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(
                        "Automatically install updates that pass compatibility checks",
                        isOn: $settings.autoInstallCompatibleRuntimeUpdates
                    )
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("onboarding.auto-install")
                    .accessibilityValue(Text(settings.autoInstallCompatibleRuntimeUpdates ? "On" : "Off"))
                    Text(
                        "Current automatic install setting: " +
                            (settings.autoInstallCompatibleRuntimeUpdates ? "On" : "Off")
                    )
                    .font(.caption.bold())
                    .accessibilityIdentifier("onboarding.auto-install-status")
                    Text("Automatic installation is off until you opt in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Administrator approval is requested only when an install or upgrade actually begins.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(maxWidth: 620)

            Button("Start with Simple Mode") {
                state.simpleModePresented = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("onboarding.continue")

            Spacer()
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding")
    }

    private func readinessCard(symbol: String, title: String, detail: String) -> some View {
        GroupBox {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, alignment: .leading)
        }
    }
}
