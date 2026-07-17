import MCAppCore
import SwiftUI

@main
struct MacContainerApp: App {
    @State private var state: AppState
    private let sparkleUpdater: SparkleAppUpdater?

    init() {
        let mode: AppEnvironmentMode = ProcessInfo.processInfo.arguments.contains("--fake-runtime")
            ? .fakeRuntime
            : .production
        let state = AppState(environment: AppEnvironment(mode: mode))
        _state = State(initialValue: state)
        if mode == .production {
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
}
