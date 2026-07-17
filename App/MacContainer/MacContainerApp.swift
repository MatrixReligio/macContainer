import AppKit
import MCAppCore
import SwiftUI

@main
struct MacContainerApp: App {
    @State private var state: AppState
    private let sparkleUpdater: SparkleAppUpdater?
    private let physicalHelperBootstrap: PhysicalHelperBootstrapCommand?
    private let physicalPacketFilterAudit: PhysicalPacketFilterAuditCommand?

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let mode: AppEnvironmentMode = arguments.contains("--fake-runtime")
            ? .fakeRuntime
            : .production
        let forcedLanguage = arguments.compactMap(Self.fakeRuntimeLanguage).first
        let languageController = if mode == .fakeRuntime, let forcedLanguage {
            LanguageController(storage: FixedLanguageSelectionStore(selection: forcedLanguage))
        } else {
            LanguageController()
        }
        let state = AppState(environment: AppEnvironment(
            mode: mode,
            languageController: languageController
        ))
        _state = State(initialValue: state)
        physicalHelperBootstrap = mode == .production
            ? PhysicalHelperBootstrapCommand(
                arguments: arguments,
                environment: ProcessInfo.processInfo.environment
            )
            : nil
        physicalPacketFilterAudit = mode == .production
            ? PhysicalPacketFilterAuditCommand(
                arguments: arguments,
                environment: ProcessInfo.processInfo.environment
            )
            : nil
        if mode == .production || SparkleAppUpdater.hasValidatedTestFeed {
            let updater = SparkleAppUpdater(state: state)
            state.appUpdates.attach(driver: updater)
            sparkleUpdater = updater
        } else {
            sparkleUpdater = nil
        }
    }

    var body: some Scene {
        WindowGroup("MacContainer", id: "main-window") {
            RootScene()
                .environment(state)
                .environment(
                    \.locale,
                    Locale(identifier: state.environment.languageController.resolvedIdentifier)
                )
                .task {
                    if let physicalHelperBootstrap {
                        try? await physicalHelperBootstrap.execute()
                    } else if let physicalPacketFilterAudit {
                        try? await physicalPacketFilterAudit.execute()
                    } else {
                        await state.runtimeUpdateAgentRegistration.reconcile(
                            enabled: state.environment.settings.automaticallyCheckRuntimeUpdates
                        )
                        return
                    }
                    NSApplication.shared.terminate(nil)
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            MacContainerCommands(state: state)
        }

        Window("Activity Center", id: "activity-center") {
            ActivityCenterView(center: state.activities)
                .background(WindowAccessibilityIdentifier("activity-center"))
        }
        .defaultSize(width: 680, height: 460)

        Settings {
            SettingsScene()
                .environment(state)
                .environment(
                    \.locale,
                    Locale(identifier: state.environment.languageController.resolvedIdentifier)
                )
        }
    }

    private static func fakeRuntimeLanguage(_ argument: String) -> AppLanguage? {
        let prefix = "--fake-runtime-language="
        guard argument.hasPrefix(prefix) else { return nil }
        return AppLanguage(rawValue: String(argument.dropFirst(prefix.count)))
    }
}

@MainActor
private final class FixedLanguageSelectionStore: LanguageSelectionStoring {
    private var selection: AppLanguage

    init(selection: AppLanguage) {
        self.selection = selection
    }

    func load() -> String? {
        selection.rawValue
    }

    func save(_ rawValue: String) throws {
        guard let selection = AppLanguage(rawValue: rawValue) else { return }
        self.selection = selection
    }
}
