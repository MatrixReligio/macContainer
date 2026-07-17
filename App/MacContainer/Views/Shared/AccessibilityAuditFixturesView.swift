import AppKit
import MCAppCore
import MCContracts
import MCModel
import MCTemplates
import SwiftUI

private enum AccessibilityAuditFixture: String, CaseIterable, Identifiable {
    case overview
    case containers
    case images
    case builds
    case machines
    case networks
    case volumes
    case registries
    case system
    case operation
    case operationForm = "operation-form"
    case templates
    case templateReview = "template-review"
    case activity
    case settings
    case settingsGeneral = "settings-general"
    case settingsRuntime = "settings-runtime"
    case settingsUpdates = "settings-updates"
    case settingsCompatibility = "settings-compatibility"
    case settingsDefaults = "settings-defaults"
    case settingsAdvanced = "settings-advanced"
    case settingsAbout = "settings-about"
    case lifecycle
    case terminal
    case error

    var id: String {
        rawValue
    }

    var title: String {
        rawValue
            .split(separator: "-")
            .map(\.capitalized)
            .joined(separator: " ")
    }
}

struct AccessibilityAuditFixturesView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @State private var selection: AccessibilityAuditFixture = .overview

    var body: some View {
        NavigationSplitView {
            fixtureNavigation
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            fixtureContent
                .id(selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(selection.title) fixture")
                .accessibilityIdentifier("audit.content.\(selection.rawValue)")
        }
        .background(AuditWindowConfigurator())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Accessibility audit fixture browser")
        .accessibilityIdentifier("accessibility-audit-ready")
        .onChange(of: state.selection) {
            selection = AccessibilityAuditFixture(rawValue: state.selection.rawValue) ?? .overview
        }
        .onChange(of: state.activityCenterPresented) {
            openWindow(id: "activity-center")
        }
    }

    private var fixtureNavigation: some View {
        List(selection: $selection) {
            ForEach(AccessibilityAuditFixture.allCases) { fixture in
                Button {
                    selection = fixture
                } label: {
                    Text(fixture.title)
                        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(selection == fixture ? Color.accentColor.opacity(0.16) : Color.clear)
                .accessibilityValue(selection == fixture ? "Selected" : "")
                .accessibilityIdentifier("audit.fixture.\(fixture.rawValue)")
                .tag(fixture)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Audit")
        .accessibilityLabel("Accessibility fixture navigation")
        .accessibilityIdentifier("audit.fixture-navigation")
    }

    @ViewBuilder
    private var fixtureContent: some View {
        switch selection {
        case .overview:
            OverviewView()
        case .containers:
            ResourceDomainView(route: .containers)
        case .images:
            ResourceDomainView(route: .images)
        case .builds:
            ResourceDomainView(route: .builds)
        case .machines:
            ResourceDomainView(route: .machines)
        case .networks:
            ResourceDomainView(route: .networks)
        case .volumes:
            ResourceDomainView(route: .volumes)
        case .registries:
            ResourceDomainView(route: .registries)
        case .system:
            ResourceDomainView(route: .system)
        case .operation:
            if let contract = Self.contract {
                ContractAuditView(contract: contract)
            }
        case .operationForm:
            if let contract = Self.contract {
                if let operation = contract.operation(id: "core.run") {
                    OperationForm(operation: operation, runtimeVersion: contract.runtimeVersion)
                }
            }
        case .templates:
            SimpleModeView()
        case .templateReview:
            TemplateReviewAuditFixture()
        case .activity:
            ActivityAuditFixture()
        case .settings:
            SettingsScene()
        case .settingsGeneral:
            GeneralSettingsView()
        case .settingsRuntime:
            RuntimeSettingsView()
        case .settingsUpdates:
            RuntimeUpdateSettingsView(isAuditMode: true)
        case .settingsCompatibility:
            CompatibilitySettingsView()
        case .settingsDefaults:
            DefaultsSettingsView()
        case .settingsAdvanced:
            AdvancedSettingsView()
        case .settingsAbout:
            AboutSettingsView()
        case .lifecycle:
            RuntimeLifecycleAuditView()
        case .terminal:
            TerminalScene(session: TerminalAuditSession())
        case .error:
            ErrorPresentation(error: Self.sampleError, style: .activity) { _ in }
                .padding(24)
                .frame(maxWidth: 720, alignment: .topLeading)
        }
    }

    private static let contract = try? ContractRepository.bundled(
        version: RuntimeVersion(major: 1, minor: 1, patch: 0)
    )

    private static let sampleError = UserFacingError(
        code: "error.authentication",
        domain: .registry,
        operationID: "registries.login",
        titleKey: "Registry authentication failed",
        explanationKey: "Review the saved account and try again.",
        diagnosticDetail: "Authorization rejected for registry.example.invalid",
        retryIsSafe: true,
        recoveryActions: [
            ErrorRecoveryAction(id: "edit-credentials", titleKey: "Edit credentials"),
            ErrorRecoveryAction(id: "retry", titleKey: "Retry")
        ],
        timestamp: Date(timeIntervalSince1970: 0)
    )
}

private struct ActivityAuditFixture: View {
    @Environment(AppState.self) private var state
    @State private var seeded = false

    var body: some View {
        ActivityCenterView(center: state.activities)
            .task {
                guard seeded == false else { return }
                seeded = true
                let id = state.activities.start(titleKey: "Refresh container inventory", cancellable: true)
                state.activities.update(id, phaseKey: "Checking runtime", completed: 2, total: 3)
            }
    }
}

private struct TemplateReviewAuditFixture: View {
    @State private var isPresented = true

    var body: some View {
        if let contract = Self.contract {
            if let template = BuiltInTemplates.all.first {
                if let review = try? TemplateRenderer(contract: contract).render(
                    template: template,
                    context: Self.context
                ) {
                    TemplateReviewView(
                        template: template,
                        review: review,
                        contract: contract,
                        isPresented: $isPresented
                    ) { "Simulated template run completed" }
                }
            }
        } else {
            ContentUnavailableView("Template review unavailable", systemImage: "exclamationmark.triangle")
        }
    }

    private static let contract = try? ContractRepository.bundled(
        version: RuntimeVersion(major: 1, minor: 1, patch: 0)
    )

    private static let context = TemplateContext(
        host: HostProfile(
            logicalCPUs: 8,
            physicalMemoryBytes: 16 * 1_073_741_824,
            chip: .appleSilicon,
            macOSMajor: 26,
            capabilities: ["rosetta", "nestedVirtualization"]
        ),
        image: ImageProfile(
            reference: "alpine:latest",
            defaultCommand: [],
            shells: ["/bin/sh"],
            platform: "linux/arm64",
            exposedPorts: [8080]
        ),
        selectedDirectory: "/tmp/maccontainer-audit-workspace",
        selectedVolume: "maccontainer-audit-data",
        hostPort: 8080,
        containerPort: 8080
    )
}

private struct AuditWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ConfiguratorView {
        ConfiguratorView(arguments: ProcessInfo.processInfo.arguments)
    }

    func updateNSView(_ nsView: ConfiguratorView, context: Context) {
        nsView.scheduleSizeEnforcement()
    }

    @MainActor
    final class ConfiguratorView: NSView {
        private let contentSize: NSSize?

        init(arguments: [String]) {
            if arguments.contains("--audit-compact-window") {
                contentSize = NSSize(
                    width: AppWindowLayout.defaultContentWidth,
                    height: AppWindowLayout.defaultContentHeight
                )
            } else if arguments.contains("--audit-wide-window") {
                contentSize = NSSize(width: 1440, height: 900)
            } else {
                contentSize = nil
            }
            super.init(frame: .zero)
            setAccessibilityElement(false)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleSizeEnforcement()
        }

        func applySize() {
            guard let contentSize, let window else { return }
            window.contentMinSize = NSSize(
                width: AppWindowLayout.minimumContentWidth,
                height: AppWindowLayout.minimumContentHeight
            )
            window.setContentSize(contentSize)
        }

        func scheduleSizeEnforcement() {
            for delay in [0.0, 0.1, 0.3, 0.6] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.applySize()
                }
            }
        }
    }
}
