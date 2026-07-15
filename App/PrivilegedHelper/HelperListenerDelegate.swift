import Foundation
import MCSystemLifecycle

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let serviceFactory: @Sendable (uid_t) -> PrivilegedHelperService
    private let callerValidator: CallerValidator

    init(
        service: PrivilegedHelperService,
        callerValidator: CallerValidator = CallerValidator()
    ) {
        serviceFactory = { _ in service }
        self.callerValidator = callerValidator
    }

    init(
        callerValidator: CallerValidator = CallerValidator(),
        serviceFactory: @escaping @Sendable (uid_t) -> PrivilegedHelperService
    ) {
        self.serviceFactory = serviceFactory
        self.callerValidator = callerValidator
    }

    func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        do {
            _ = try callerValidator.validate(connection)
        } catch {
            connection.invalidate()
            return false
        }
        connection.exportedInterface = PrivilegedHelperXPC.interface()
        connection.exportedObject = serviceFactory(connection.effectiveUserIdentifier)
        connection.activate()
        return true
    }
}
