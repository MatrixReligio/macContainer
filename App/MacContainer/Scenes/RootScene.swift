import MCAppCore
import MCContracts
import SwiftUI

struct RootScene: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var state = state
        let arguments = ProcessInfo.processInfo.arguments
        let showsSparkleTestAbout = arguments.contains("--sparkle-test-about") &&
            arguments.contains("--fake-runtime") && SparkleAppUpdater.hasValidatedTestFeed

        Group {
            if showsSparkleTestAbout {
                AboutSettingsView()
                    .accessibilityIdentifier("sparkle-test-about")
            } else if let fixture = MarketingFixture.from(arguments: arguments), arguments.contains("--fake-runtime") {
                MarketingFixturesView(fixture: fixture)
            } else if arguments.contains("--accessibility-fixtures") {
                AccessibilityAuditFixturesView()
            } else if let contract = Self.contract, arguments.contains("--contract-audit-mode") {
                ContractAuditView(contract: contract)
            } else if arguments.contains("--onboarding-mode") {
                OnboardingView()
            } else if arguments.contains("--simple-mode-audit") {
                SimpleModeView()
            } else if arguments.contains("--lifecycle-audit") {
                RuntimeLifecycleAuditView()
            } else if arguments.contains("--terminal-audit") {
                TerminalScene(session: TerminalAuditSession())
            } else {
                NavigationSplitView(columnVisibility: $state.columnVisibility) {
                    Sidebar(selection: $state.selection)
                        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
                } content: {
                    RouteContentView(route: state.selection)
                        .navigationSplitViewColumnWidth(min: 420, ideal: 620)
                } detail: {
                    ResourceInspectorPlaceholder(route: state.selection)
                        .navigationSplitViewColumnWidth(min: 260, ideal: 340)
                }
                .onChange(of: state.activityCenterPresented) {
                    openWindow(id: "activity-center")
                }
                .sheet(isPresented: $state.simpleModePresented) {
                    SimpleModeView(initialTemplateID: state.simpleModeInitialTemplateID)
                        .onDisappear {
                            state.simpleModeInitialTemplateID = "quick-run"
                        }
                }
            }
        }
        .frame(
            minWidth: AppWindowLayout.minimumContentWidth,
            minHeight: AppWindowLayout.minimumContentHeight
        )
        .background(WindowAccessibilityIdentifier("main-window"))
    }

    private static let contract = try? ContractRepository.bundled(
        version: RuntimeVersion(major: 1, minor: 1, patch: 0)
    )
}

private struct RouteContentView: View {
    let route: AppRoute

    var body: some View {
        if route == .overview {
            OverviewView()
        } else {
            ResourceDomainView(route: route)
        }
    }
}

private struct ResourceInspectorPlaceholder: View {
    @Environment(AppState.self) private var state
    let route: AppRoute

    var body: some View {
        if let resource = state.selectedResource {
            Form {
                Section("Identity") {
                    LabeledContent("Name", value: resource.name)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ID")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(resource.id)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .accessibilityIdentifier("resource-detail-id")
                    }
                    LabeledContent("Kind", value: resource.kind)
                }
                Section("State") {
                    Label(
                        LocalizedStringKey(resource.status),
                        systemImage: resource.status == "Running" ? "play.fill" : "circle"
                    )
                }
                Section("Activity") {
                    Text("No recent activity")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(resource.name)
            .accessibilityIdentifier("resource-inspector")
        } else {
            EmptyStateView(
                symbol: "sidebar.right",
                title: "Nothing Selected",
                message: "Select a resource to inspect its details."
            )
            .accessibilityIdentifier("resource-inspector")
        }
    }
}
