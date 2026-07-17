import ContainerAPIClient
import MachineAPIClient

struct AppleRuntimeClientFactories: Sendable {
    static let production = Self(
        container: { ContainerClient() },
        machine: { MachineClient() },
        network: { NetworkClient() }
    )

    let container: @Sendable () -> ContainerClient
    let machine: @Sendable () -> MachineClient
    let network: @Sendable () -> NetworkClient
}
