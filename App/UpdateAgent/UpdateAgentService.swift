import AppKit
import Foundation
import MCSystemLifecycle
import UserNotifications

final class UpdateAgentPresenter: UpdateAgentPresenting, RuntimeUpdateStateSink, @unchecked Sendable {
    func isAppRunning() async -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "container.matrixreligio.com" }
    }

    func publish(_ state: RuntimeUpdateState) async {
        guard let data = try? JSONEncoder().encode(state) else { return }
        let connection = NSXPCConnection(machServiceName: UpdateAgentXPCIdentity.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: UpdateAgentStatusXPC.self)
        connection.resume()
        await withCheckedContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                connection.invalidate()
                continuation.resume()
            } as? UpdateAgentStatusXPC
            guard let proxy else {
                connection.invalidate()
                continuation.resume()
                return
            }
            proxy.publishStatus(data) { _ in
                connection.invalidate()
                continuation.resume()
            }
        }
    }

    func notify(_ state: RuntimeUpdateState) async {
        let content = UNMutableNotificationContent()
        content.title = "MacContainer runtime update"
        content.body = notificationBody(for: state)
        let request = UNNotificationRequest(identifier: "runtime-update", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func notificationBody(for state: RuntimeUpdateState) -> String {
        switch state {
        case let .available(version): "Apple container \(version) is compatibility-approved and ready to review."
        case let .pending(reason): "The approved update is pending: \(reason.rawValue)."
        case let .held(reason): "The discovered runtime is held: \(reason.rawValue)."
        case .rolledBack: "The runtime update was rolled back. Open MacContainer for recovery details."
        case .recoveryRequired: "Runtime recovery requires attention in MacContainer."
        default: "Open MacContainer to review runtime update status."
        }
    }
}
