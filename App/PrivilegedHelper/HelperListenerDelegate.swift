import Foundation
import MCSystemLifecycle

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let serviceFactory: @Sendable (uid_t) -> PrivilegedHelperService
    private let callerValidator: CallerValidator
    private let connectionRetirement: PrivilegedHelperConnectionRetirement?

    init(
        service: PrivilegedHelperService,
        callerValidator: CallerValidator = CallerValidator(),
        connectionRetirement: PrivilegedHelperConnectionRetirement? = nil
    ) {
        serviceFactory = { _ in service }
        self.callerValidator = callerValidator
        self.connectionRetirement = connectionRetirement
    }

    init(
        callerValidator: CallerValidator = CallerValidator(),
        connectionRetirement: PrivilegedHelperConnectionRetirement? = nil,
        serviceFactory: @escaping @Sendable (uid_t) -> PrivilegedHelperService
    ) {
        self.serviceFactory = serviceFactory
        self.callerValidator = callerValidator
        self.connectionRetirement = connectionRetirement
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
        if let connectionRetirement {
            let identifier = connectionRetirement.acceptConnection()
            connection.invalidationHandler = {
                connectionRetirement.disconnect(identifier)
            }
        }
        connection.activate()
        return true
    }
}
