import Foundation

public struct AppleRuntimeBridge: RuntimeBridge, Sendable {
    public let containers: any ContainerOperations
    public let images: any ImageOperations
    public let builds: any BuildOperations
    public let builders: any BuilderOperations
    public let networks: any NetworkOperations
    public let volumes: any VolumeOperations
    public let registries: any RegistryOperations
    public let machines: any MachineOperations
    public let system: any SystemOperations
    public let dns: any DNSOperations
    public let kernel: any KernelOperations
    public let configuration: any ConfigurationOperations

    public init(
        coordinator: OperationCoordinator = OperationCoordinator(),
        dnsBackend: any DNSBackend = AppleDNSBackend(),
        kernelTemporaryRoot: URL = FileManager.default.temporaryDirectory
            .appending(path: "container.matrixreligio.com/kernel-downloads", directoryHint: .isDirectory)
    ) {
        containers = ContainerAdapter(client: AppleContainerBackend(), coordinator: coordinator)
        images = ImageAdapter(client: AppleImageBackend(), coordinator: coordinator)
        builds = BuildAdapter(client: AppleBuildBackend(), coordinator: coordinator)
        builders = BuilderAdapter(client: AppleBuilderBackend(), coordinator: coordinator)
        networks = NetworkAdapter(client: AppleNetworkBackend(), coordinator: coordinator)
        volumes = VolumeAdapter(client: AppleVolumeBackend(), coordinator: coordinator)
        registries = RegistryAdapter(
            verifier: AppleRegistryVerifier(),
            store: RegistryCredentialStore(),
            coordinator: coordinator
        )
        machines = MachineAdapter(
            client: AppleMachineBackend(),
            capabilities: AppleMachineCapabilities(),
            kernels: AppleMachineKernelResolver(),
            coordinator: coordinator
        )
        system = SystemAdapter(backend: AppleSystemRuntimeBackend(), coordinator: coordinator)
        dns = DNSAdapter(backend: dnsBackend, coordinator: coordinator)
        kernel = KernelAdapter(
            backend: AppleKernelBackend(),
            downloader: URLSessionKernelDownloader(),
            archiveValidator: AppleKernelArchiveValidator(),
            coordinator: coordinator,
            temporaryRoot: kernelTemporaryRoot
        )
        configuration = ConfigurationAdapter(
            storage: AtomicConfigurationStorage.production(),
            runtime: AppleConfigurationRuntime(),
            codec: AppleContainerConfigurationCodec(),
            coordinator: coordinator
        )
    }
}
