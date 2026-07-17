import AppKit
import Foundation
import MCSystemLifecycle
import UserNotifications

final class UpdateAgentPresenter: UpdateAgentPresenting, RuntimeUpdateStateSink, @unchecked Sendable {
    private let statusStore: RuntimeUpdateStatusStore
    private let localization: UpdateAgentLocalization

    init(
        statusStore: RuntimeUpdateStatusStore = RuntimeUpdateStatusStore(),
        localization: UpdateAgentLocalization = UpdateAgentLocalization()
    ) {
        self.statusStore = statusStore
        self.localization = localization
    }

    func isAppRunning() async -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "container.matrixreligio.com" }
    }

    func publish(_ state: RuntimeUpdateState) async {
        await statusStore.publish(state)
    }

    func notify(_ state: RuntimeUpdateState) async {
        await statusStore.publish(state)
        let content = UNMutableNotificationContent()
        content.title = localization.title()
        content.body = localization.body(for: state)
        let request = UNNotificationRequest(identifier: "runtime-update", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
