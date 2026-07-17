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
        self.init(
            coordinator: coordinator,
            dnsBackend: dnsBackend,
            kernelTemporaryRoot: kernelTemporaryRoot,
            clientFactories: .production
        )
    }

    init(clientFactories: AppleRuntimeClientFactories) {
        self.init(
            coordinator: OperationCoordinator(),
            dnsBackend: AppleDNSBackend(),
            kernelTemporaryRoot: FileManager.default.temporaryDirectory
                .appending(path: "container.matrixreligio.com/kernel-downloads", directoryHint: .isDirectory),
            clientFactories: clientFactories
        )
    }

    private init(
        coordinator: OperationCoordinator,
        dnsBackend: any DNSBackend,
        kernelTemporaryRoot: URL,
        clientFactories: AppleRuntimeClientFactories
    ) {
        containers = ContainerAdapter(
            client: AppleContainerBackend(makeClient: clientFactories.container),
            coordinator: coordinator
        )
        images = ImageAdapter(client: AppleImageBackend(), coordinator: coordinator)
        let builderBackend = AppleBuilderBackend(makeClient: clientFactories.container)
        builds = BuildAdapter(
            client: AppleBuildBackend(
                makeClient: clientFactories.container,
                builder: builderBackend
            ),
            coordinator: coordinator
        )
        builders = BuilderAdapter(client: builderBackend, coordinator: coordinator)
        networks = NetworkAdapter(
            client: AppleNetworkBackend(
                makeNetworkClient: clientFactories.network,
                makeContainerClient: clientFactories.container
            ),
            coordinator: coordinator
        )
        volumes = VolumeAdapter(
            client: AppleVolumeBackend(makeContainerClient: clientFactories.container),
            coordinator: coordinator
        )
        registries = RegistryAdapter(
            verifier: AppleRegistryVerifier(),
            store: RegistryCredentialStore(),
            coordinator: coordinator
        )
        machines = MachineAdapter(
            client: AppleMachineBackend(
                makeMachineClient: clientFactories.machine,
                makeContainerClient: clientFactories.container
            ),
            capabilities: AppleMachineCapabilities(),
            kernels: AppleMachineKernelResolver(),
            coordinator: coordinator
        )
        let workloads = AppleWorkloadManager(
            makeContainers: clientFactories.container,
            makeMachines: clientFactories.machine
        )
        system = SystemAdapter(
            backend: AppleSystemRuntimeBackend(
                controller: .production(workloads: workloads),
                workloads: workloads
            ),
            coordinator: coordinator
        )
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
            runtime: AppleConfigurationRuntime(
                controller: .production(workloads: workloads),
                workloads: workloads
            ),
            codec: AppleContainerConfigurationCodec(),
            coordinator: coordinator
        )
    }
}
