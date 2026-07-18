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
                        value: runtimeStatus,
                        symbol: state.health == .healthy ? "checkmark.circle.fill" : "clock",
                        identifier: "runtime-health-value"
                    )
                    MetricSummary(
                        title: "Containers",
                        value: resourceCount(for: .containers),
                        symbol: "shippingbox"
                    )
                    MetricSummary(
                        title: "Virtual machines",
                        value: resourceCount(for: .machines),
                        symbol: "desktopcomputer"
                    )
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
                    Text(recommendationDetail)
                        .readableForeground()
                    Button {
                        performRecommendedAction()
                    } label: {
                        Label(recommendationActionTitle, systemImage: recommendationActionSymbol)
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
        .task {
            await state.refreshOverview()
        }
    }

    private var runtimeStatus: LocalizedStringKey {
        switch state.health {
        case .healthy: "Ready"
        case .attention: "Changing"
        case .unavailable: "Unavailable"
        case .checking: "Checking"
        }
    }

    private var recommendationDetail: LocalizedStringKey {
        let machineTotal = state.resourceBrowser.totalCount(for: .machines)
        let machineRunning = state.resourceBrowser.runningCount(for: .machines)
        let containerTotal = state.resourceBrowser.totalCount(for: .containers)
        if machineRunning > 0 {
            return "Your virtual machine is running. Open Virtual Machines for terminal and lifecycle controls."
        }
        if machineTotal > 0 {
            return "Your virtual machine is stopped. Open Virtual Machines to start it or access its terminal."
        }
        if containerTotal > 0 {
            return "Containers and virtual machines are separate resources. Open Containers to manage this workload."
        }
        return "Create a guided container or virtual machine. The verified Alpine image is prepared automatically."
    }

    private var recommendationActionTitle: LocalizedStringKey {
        if state.resourceBrowser.totalCount(for: .machines) > 0 {
            return "Open Virtual Machines"
        }
        if state.resourceBrowser.totalCount(for: .containers) > 0 {
            return "Open Containers"
        }
        return "Create a workload…"
    }

    private var recommendationActionSymbol: String {
        if state.resourceBrowser.totalCount(for: .machines) > 0 {
            return "desktopcomputer"
        }
        if state.resourceBrowser.totalCount(for: .containers) > 0 {
            return "shippingbox"
        }
        return "plus.circle.fill"
    }

    private func resourceCount(for route: AppRoute) -> String {
        let total = state.resourceBrowser.totalCount(for: route)
        let running = state.resourceBrowser.runningCount(for: route)
        return "\(total) total · \(running) running"
    }

    private func performRecommendedAction() {
        if state.resourceBrowser.totalCount(for: .machines) > 0 {
            state.selection = .machines
        } else if state.resourceBrowser.totalCount(for: .containers) > 0 {
            state.selection = .containers
        } else {
            state.creationIntent = .workload
            state.simpleModeInitialTemplateID = "quick-run"
            state.simpleModePresented = true
        }
    }
}

private struct HealthSummary: View {
    let title: LocalizedStringKey
    let value: LocalizedStringKey
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
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(nsColor: .labelColor))
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
    let title: LocalizedStringKey
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
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(nsColor: .labelColor))
                    Text(verbatim: value)
                        .font(.headline.monospacedDigit())
                        .readableForeground()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }
}
