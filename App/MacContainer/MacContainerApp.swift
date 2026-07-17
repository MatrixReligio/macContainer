import AppKit
import MCAppCore
import SwiftUI

@main
struct MacContainerApp: App {
    @State private var state: AppState
    private let sparkleUpdater: SparkleAppUpdater?
    private let physicalHelperBootstrap: PhysicalHelperBootstrapCommand?
    private let physicalPacketFilterAudit: PhysicalPacketFilterAuditCommand?
    private let physicalPrivilegedOperation: PhysicalPrivilegedOperationCommand?
    private let isPhysicalRuntimeUITest: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let environment = ProcessInfo.processInfo.environment
        let mode: AppEnvironmentMode = arguments.contains("--fake-runtime")
            ? .fakeRuntime
            : .production
        let physicalRuntimeUITest = mode == .production &&
            arguments.contains("--physical-runtime-ui-test") &&
            Self.isAuthorizedPhysicalTest(environment)
        isPhysicalRuntimeUITest = physicalRuntimeUITest
        let fakeRuntimeLanguage = arguments.compactMap(Self.fakeRuntimeLanguage).first
        let physicalRuntimeLanguage = physicalRuntimeUITest
            ? arguments.compactMap(Self.physicalRuntimeLanguage).first
            : nil
        let languageController = if mode == .fakeRuntime {
            LanguageController(storage: FixedLanguageSelectionStore(selection: fakeRuntimeLanguage ?? .english))
        } else if let physicalRuntimeLanguage {
            LanguageController(storage: FixedLanguageSelectionStore(selection: physicalRuntimeLanguage))
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
                environment: environment
            )
            : nil
        physicalPacketFilterAudit = mode == .production
            ? PhysicalPacketFilterAuditCommand(
                arguments: arguments,
                environment: environment
            )
            : nil
        physicalPrivilegedOperation = mode == .production
            ? PhysicalPrivilegedOperationCommand(
                arguments: arguments,
                environment: environment
            )
            : nil
        if (mode == .production && !physicalRuntimeUITest) || SparkleAppUpdater.hasValidatedTestFeed {
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
                    } else if let physicalPrivilegedOperation {
                        try? await physicalPrivilegedOperation.execute()
                    } else if isPhysicalRuntimeUITest {
                        await state.runtimeUpdates.restoreLatestStatus()
                        return
                    } else {
                        await state.runtimeUpdates.restoreLatestStatus()
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

    private static func physicalRuntimeLanguage(_ argument: String) -> AppLanguage? {
        let prefix = "--physical-runtime-language="
        guard argument.hasPrefix(prefix) else { return nil }
        return AppLanguage(rawValue: String(argument.dropFirst(prefix.count)))
    }

    private static func isAuthorizedPhysicalTest(_ environment: [String: String]) -> Bool {
        guard let runID = environment["PHYSICAL_RUN_ID"],
              UUID(uuidString: runID) != nil,
              environment["PHYSICAL_TEST_AUTHORIZATION"] == runID,
              let root = environment["PHYSICAL_RUN_ROOT"]
        else {
            return false
        }
        return URL(fileURLWithPath: root, isDirectory: true)
            .standardizedFileURL.lastPathComponent == runID
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
