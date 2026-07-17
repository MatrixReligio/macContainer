import MCAppCore
import SwiftUI

struct MacContainerCommands: Commands {
    let state: AppState

    var body: some Commands {
        CommandMenu("Navigate") {
            routeButton("Overview", route: .overview, key: "1")
            routeButton("Containers", route: .containers, key: "2")
            routeButton("Images", route: .images, key: "3")
            routeButton("Builds", route: .builds, key: "4")
            routeButton("Machines", route: .machines, key: "5")
            routeButton("Networks", route: .networks, key: "6")
            routeButton("Volumes", route: .volumes, key: "7")
            routeButton("Registries", route: .registries, key: "8")
            routeButton("System", route: .system, key: "9")
        }

        CommandGroup(after: .newItem) {
            Button("New…") {
                state.simpleModePresented = true
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(after: .toolbar) {
            Button("Refresh") {
                NotificationCenter.default.post(name: .macContainerRefresh, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Activity Center") {
                state.activityCenterPresented.toggle()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }

    private func routeButton(_ title: String, route: AppRoute, key: KeyEquivalent) -> some View {
        Button(title) {
            state.selection = route
        }
        .keyboardShortcut(key, modifiers: .command)
    }
}

extension Notification.Name {
    static let macContainerNewResource = Notification.Name("MacContainer.newResource")
    static let macContainerRefresh = Notification.Name("MacContainer.refresh")
}
