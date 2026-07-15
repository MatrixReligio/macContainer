import Darwin
import Foundation
import MCSystemLifecycle

if CommandLine.arguments.contains("--build-smoke-test") {
    exit(EXIT_SUCCESS)
}

let listener = NSXPCListener(machServiceName: HelperClient.machServiceName)
listener.setConnectionCodeSigningRequirement(CodeSigningRequirements.app)
let operationGate = PrivilegedOperationGate()
let delegate = HelperListenerDelegate { packageOwner in
    PrivilegedHelperService(
        system: SystemPrivilegedAdapter(packageOwner: packageOwner),
        operationGate: operationGate
    )
}

listener.delegate = delegate
listener.resume()
