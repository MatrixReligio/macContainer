import MCAppCore
import SwiftUI

struct OverviewView: View {
    @Environment(AppState.self) private var state

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Overview")
                        .font(.largeTitle.bold())
                    Text("Runtime health and the safest next action, at a glance.")
                        .font(.title3)
                        .readableForeground()
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    HealthSummary(
                        title: "Apple container",
                        value: state.health == .healthy ? "Ready" : "Checking",
                        symbol: state.health == .healthy ? "checkmark.circle.fill" : "clock",
                        identifier: "runtime-health-value"
                    )
                    HealthSummary(
                        title: "Compatibility",
                        value: state.health == .healthy ? "Compatible" : "Pending",
                        symbol: state.health == .healthy ? "checkmark.shield.fill" : "shield.lefthalf.filled",
                        identifier: "compatibility-health-value"
                    )
                    MetricSummary(title: "Running", value: "0", symbol: "play.circle")
                    MetricSummary(
                        title: "Activities",
                        value: "\(state.activities.activities.values.filter { $0.outcome == nil }.count)",
                        symbol: "list.bullet.rectangle"
                    )
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Runtime summary")

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Recommended")
                        .font(.headline)
                    Button {
                        state.simpleModePresented = true
                    } label: {
                        Label("Create your first container", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("overview-primary-action")
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Overview")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Overview")
        .accessibilityIdentifier("overview-content")
    }
}

private struct HealthSummary: View {
    let title: String
    let value: String
    let symbol: String
    let identifier: String

    var body: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text(value)
                        .font(.headline)
                        .readableForeground()
                        .accessibilityIdentifier(identifier)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct MetricSummary: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text(value)
                        .font(.headline.monospacedDigit())
                        .readableForeground()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }
}
