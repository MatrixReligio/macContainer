import AppKit
import MCAppCore
import MCModel
import SwiftUI

enum MarketingFixture: String, CaseIterable {
    case overview
    case templates
    case upgrade
    case uninstall
    case terminal
    case error

    static func from(arguments: [String]) -> Self? {
        let prefix = "--marketing-fixture="
        guard let value = arguments.first(where: { $0.hasPrefix(prefix) })?
            .dropFirst(prefix.count)
        else {
            return nil
        }
        return Self(rawValue: String(value))
    }
}

struct MarketingFixturesView: View {
    @Environment(AppState.self) private var state
    let fixture: MarketingFixture

    var body: some View {
        VStack(spacing: 0) {
            marketingHeader
            Divider()
            fixtureContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(MarketingWindowConfigurator())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("marketing.\(fixture.rawValue).ready")
        .onAppear {
            if fixture == .upgrade {
                state.environment.settings.automaticallyCheckRuntimeUpdates = true
                state.environment.settings.autoInstallCompatibleRuntimeUpdates = true
            }
        }
    }

    private var marketingHeader: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("MacContainer")
                    .font(.headline)
                Text(fixture.subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label("Apple container · compatible", systemImage: "checkmark.shield.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.green.opacity(0.09), in: Capsule())
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var fixtureContent: some View {
        switch fixture {
        case .overview:
            overviewFixture
        case .templates:
            SimpleModeView()
        case .upgrade:
            upgradeFixture
        case .uninstall:
            uninstallFixture
        case .terminal:
            TerminalScene(session: TerminalAuditSession())
        case .error:
            errorFixture
        }
    }

    private var overviewFixture: some View {
        HStack(spacing: 0) {
            OverviewView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                Text("Safe by default")
                    .font(.title2.bold())
                marketingPoint(
                    "Scenario-first setup",
                    detail: "Start with a goal, then review every generated value.",
                    symbol: "square.grid.2x2.fill",
                    color: .blue
                )
                marketingPoint(
                    "Compatibility guarded",
                    detail: "Only approved runtime updates can install automatically.",
                    symbol: "checkmark.shield.fill",
                    color: .green
                )
                marketingPoint(
                    "Clean ownership",
                    detail: "A fresh inventory tracks every runtime-owned artifact.",
                    symbol: "sparkles",
                    color: .purple
                )
                Spacer()
                Text("No daemon guessing. No hidden destructive action.")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(width: 360, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        }
    }

    private var upgradeFixture: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 18) {
                Label("Compatibility gate passed", systemImage: "checkmark.seal.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.green)
                Text("Apple container 1.1.0")
                    .font(.largeTitle.bold())
                Text("Signed by Apple · SHA-256 verified")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    versionStep("1.0.0", detail: "Verified rollback point", symbol: "archivebox.fill")
                    versionStep(
                        "1.1.0",
                        detail: "Approved for this MacContainer build",
                        symbol: "arrow.up.circle.fill"
                    )
                    versionStep(
                        "Postflight",
                        detail: "Operations and templates rechecked after install",
                        symbol: "checkmark.shield.fill"
                    )
                }
                .padding(16)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                Spacer()
            }
            .frame(width: 410, alignment: .topLeading)

            RuntimeUpdateSettingsView(isAuditMode: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(30)
    }

    private var uninstallFixture: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 18) {
                Label("Complete means complete", systemImage: "trash.slash.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.red)
                Text("Every owned artifact is inventoried again immediately before removal.")
                    .font(.title3.weight(.medium))
                VStack(alignment: .leading, spacing: 11) {
                    marketingPoint(
                        "15 artifact categories",
                        detail: "Services, receipts, credentials, caches, rollback data, and more.",
                        symbol: "checklist",
                        color: .blue
                    )
                    marketingPoint(
                        "Typed confirmation",
                        detail: "The destructive path remains separate from preserve-data removal.",
                        symbol: "keyboard.fill",
                        color: .orange
                    )
                    marketingPoint(
                        "Verified postflight",
                        detail: "Incomplete cleanup is reported with a concrete recovery action.",
                        symbol: "magnifyingglass.circle.fill",
                        color: .green
                    )
                }
                Spacer()
            }
            .frame(width: 390, alignment: .topLeading)

            ScrollView {
                UninstallRuntimeView(
                    isAuditMode: true,
                    initialConfirmation: "REMOVE APPLE CONTAINER"
                )
                .padding(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(26)
    }

    private var errorFixture: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Errors that help you recover")
                    .font(.largeTitle.bold())
                Text("A clear cause, a redacted diagnostic, and safe next actions — without exposing credentials.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    recoveryBadge("Redacted", symbol: "eye.slash.fill")
                    recoveryBadge("Retry-safe", symbol: "arrow.clockwise.circle.fill")
                    recoveryBadge("Actionable", symbol: "wrench.and.screwdriver.fill")
                }
                Spacer()
            }
            .padding(34)
            .frame(width: 460, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(Color.accentColor.opacity(0.07))

            VStack(alignment: .leading, spacing: 16) {
                Text("Activity details")
                    .font(.title2.bold())
                ErrorPresentation(error: Self.sampleError, style: .activity) { _ in }
                Spacer()
            }
            .padding(34)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func marketingPoint(_ title: String, detail: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func versionStep(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.monospaced())
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func recoveryBadge(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary, in: Capsule())
    }

    private static let sampleError = UserFacingError(
        code: "registry.authentication.rejected",
        domain: .registry,
        operationID: "registries.login",
        titleKey: "Registry authentication failed",
        explanationKey: "Review the saved account and try again. Your existing containers are unaffected.",
        diagnosticDetail: "Authorization rejected for registry.example.invalid · secret values redacted",
        retryIsSafe: true,
        recoveryActions: [
            ErrorRecoveryAction(id: "edit-credentials", titleKey: "Edit credentials"),
            ErrorRecoveryAction(id: "retry", titleKey: "Retry")
        ],
        timestamp: Date(timeIntervalSince1970: 0)
    )
}

private extension MarketingFixture {
    var subtitle: String {
        switch self {
        case .overview: "A safer home for Apple container"
        case .templates: "Start from a scenario, not a wall of flags"
        case .upgrade: "Automatic updates with a compatibility gate"
        case .uninstall: "Verified removal without leftovers"
        case .terminal: "Interactive sessions with guarded capabilities"
        case .error: "Actionable recovery without leaking secrets"
        }
    }
}

private struct MarketingWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ConfiguratorView {
        ConfiguratorView(frame: .zero)
    }

    func updateNSView(_ nsView: ConfiguratorView, context: Context) {
        nsView.scheduleSizeEnforcement()
    }

    @MainActor
    final class ConfiguratorView: NSView {
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
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

        func scheduleSizeEnforcement() {
            for delay in [0.0, 0.1, 0.3, 0.6] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let window = self?.window else { return }
                    window.contentMinSize = NSSize(width: 1180, height: 760)
                    window.setContentSize(NSSize(width: 1180, height: 760))
                    window.title = "MacContainer"
                }
            }
        }
    }
}
