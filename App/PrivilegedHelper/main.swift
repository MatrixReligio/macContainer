import Darwin
import Dispatch
import Foundation
import MCSystemLifecycle

if CommandLine.arguments.contains("--build-smoke-test") {
    exit(EXIT_SUCCESS)
}

let listener = NSXPCListener(machServiceName: HelperClient.machServiceName)
listener.setConnectionCodeSigningRequirement(CodeSigningRequirements.app)
let operationGate = PrivilegedOperationGate()
let connectionRetirement = PrivilegedHelperConnectionRetirement(
    schedule: { operation in
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + .milliseconds(500),
            execute: operation
        )
    },
    terminate: { exit(EXIT_SUCCESS) }
)
let delegate = HelperListenerDelegate(connectionRetirement: connectionRetirement) { packageOwner in
    PrivilegedHelperService(
        system: SystemPrivilegedAdapter(packageOwner: packageOwner),
        operationGate: operationGate
    )
}

listener.delegate = delegate
listener.resume()
dispatchMain()
