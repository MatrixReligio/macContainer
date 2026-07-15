import Foundation
@testable import MCContainerBridge
import MCModel
import Testing

@Suite("System service controller")
struct SystemServiceControllerTests {
    @Test func `start uses the installed API server and verifies both APIs`() async throws {
        let services = FakeServiceManager()
        let health = FakeHealthChecker(results: [
            .failure(TestFailure.unavailable),
            .success(RuntimeHealth(healthy: true, version: "1.1.0"))
        ])
        let machines = FakeMachineAPIProbe()
        let configurationLoader = FakeSystemConfigurationLoader()
        let controller = makeController(
            services: services,
            health: health,
            machines: machines,
            configurationLoader: configurationLoader
        )

        let result = try await controller.start(timeout: .seconds(5))

        #expect(result == RuntimeHealth(healthy: true, version: "1.1.0"))
        let definition = try #require(await services.registeredDefinitions.first)
        #expect(definition.program.path == "/usr/local/bin/container-apiserver")
        #expect(definition.arguments == ["/usr/local/bin/container-apiserver", "start"])
        #expect(definition.program.path != CommandLine.arguments[0])
        #expect(definition.label == "com.apple.container.apiserver")
        #expect(definition.machServices == ["com.apple.container.apiserver"])
        #expect(await machines.verificationCount == 1)
        #expect(await configurationLoader.loadCount == 1)
    }

    @Test func `configuration failure occurs before registration`() async {
        let services = FakeServiceManager()
        let loader = FakeSystemConfigurationLoader(error: TestFailure.configuration)
        let controller = makeController(services: services, configurationLoader: loader)

        await #expect(throws: TestFailure.configuration) {
            try await controller.start(timeout: .seconds(1))
        }

        #expect(await services.registeredDefinitions.isEmpty)
    }

    @Test func `health timeout deregisters only a service registered by this start`() async {
        let services = FakeServiceManager()
        let health = FakeHealthChecker(results: [.failure(TestFailure.unavailable)])
        let controller = makeController(services: services, health: health)

        await #expect(throws: SystemServiceError.healthTimeout) {
            try await controller.start(timeout: .milliseconds(4))
        }

        #expect(await services.registeredLabels.isEmpty)
        #expect(await services.deregisteredLabels == ["com.apple.container.apiserver"])
        #expect(await health.pingCount > 1)
    }

    @Test func `each health probe is bounded by the caller deadline`() async {
        let health = FakeHealthChecker(results: [.failure(TestFailure.unavailable)])
        let controller = makeController(
            health: health,
            retryPolicy: .init(
                initialDelay: .milliseconds(1),
                maximumDelay: .milliseconds(1),
                pingTimeout: .seconds(30)
            )
        )

        await #expect(throws: SystemServiceError.healthTimeout) {
            try await controller.start(timeout: .milliseconds(3))
        }

        #expect(await health.requestedTimeouts.allSatisfy { $0 <= .milliseconds(3) })
    }

    @Test func `unhealthy preexisting service is never claimed or deregistered`() async {
        let services = FakeServiceManager(registeredLabels: ["com.apple.container.apiserver"])
        let controller = makeController(
            services: services,
            health: FakeHealthChecker(results: [.failure(TestFailure.unavailable)])
        )

        await #expect(throws: SystemServiceError.healthTimeout) {
            try await controller.start(timeout: .milliseconds(3))
        }

        #expect(await services.registeredDefinitions.isEmpty)
        #expect(await services.deregisteredLabels.isEmpty)
        #expect(await services.registeredLabels == ["com.apple.container.apiserver"])
    }

    @Test func `machine API failure cleans up a partial start`() async {
        let services = FakeServiceManager()
        let machines = FakeMachineAPIProbe(error: TestFailure.machineAPI)
        let controller = makeController(services: services, machines: machines)

        await #expect(throws: SystemServiceError.machineAPIUnavailable) {
            try await controller.start(timeout: .seconds(1))
        }

        #expect(await services.registeredLabels.isEmpty)
        #expect(await services.deregisteredLabels == ["com.apple.container.apiserver"])
    }

    @Test func `failed partial start cleanup is never hidden`() async {
        let services = FakeServiceManager(deregisterError: TestFailure.cleanup)
        let controller = makeController(services: services, machines: FakeMachineAPIProbe(error: .machineAPI))

        await #expect(throws: SystemServiceError.partialStartCleanupFailed) {
            try await controller.start(timeout: .seconds(1))
        }

        #expect(await services.registeredLabels == ["com.apple.container.apiserver"])
    }

    @Test func `cancelling start cleans up its registration`() async throws {
        let services = FakeServiceManager()
        let health = BlockingHealthChecker()
        let controller = makeController(services: services, health: health)
        let task = Task {
            try await controller.start(timeout: .seconds(30))
        }
        await waitUntil { await services.registeredLabels.contains("com.apple.container.apiserver") }

        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        #expect(await services.registeredLabels.isEmpty)
        #expect(await services.deregisteredLabels == ["com.apple.container.apiserver"])
    }

    @Test func `stop refuses active workloads without explicit policy`() async {
        let services = FakeServiceManager(registeredLabels: ["com.apple.container.apiserver"])
        let workloads = FakeWorkloadManager(inventories: [
            WorkloadInventory(activeContainerIDs: ["web"], activeMachineIDs: ["builder"])
        ])
        let controller = makeController(services: services, workloads: workloads)

        await #expect(throws: SystemServiceError.activeWorkloads(containers: 1, machines: 1)) {
            try await controller.stop(stopActiveWorkloads: false, timeout: .seconds(2))
        }

        #expect(await workloads.stopRequests.isEmpty)
        #expect(await services.deregisteredLabels.isEmpty)
    }

    @Test func `explicit stop drains workloads and deregisters API last`() async throws {
        let services = FakeServiceManager(
            registeredLabels: [
                "com.apple.container.apiserver",
                "com.apple.container.core.machine-apiserver",
                "unrelated.service"
            ]
        )
        let workloads = FakeWorkloadManager(inventories: [
            WorkloadInventory(activeContainerIDs: ["web"], activeMachineIDs: ["builder"]),
            .empty
        ])
        let controller = makeController(services: services, workloads: workloads)

        try await controller.stop(stopActiveWorkloads: true, timeout: .seconds(2))

        #expect(await workloads.stopRequests.count == 1)
        #expect(await services.deregisteredLabels == [
            "com.apple.container.core.machine-apiserver",
            "com.apple.container.apiserver"
        ])
        #expect(await services.registeredLabels == ["unrelated.service"])
    }

    @Test func `workload shutdown timeout preserves every service`() async {
        let services = FakeServiceManager(registeredLabels: ["com.apple.container.apiserver"])
        let workloads = FakeWorkloadManager(inventories: [
            WorkloadInventory(activeContainerIDs: ["web"], activeMachineIDs: [])
        ])
        let controller = makeController(services: services, workloads: workloads)

        await #expect(throws: SystemServiceError.workloadShutdownTimeout) {
            try await controller.stop(stopActiveWorkloads: true, timeout: .milliseconds(3))
        }

        #expect(await services.registeredLabels == ["com.apple.container.apiserver"])
        #expect(await services.deregisteredLabels.isEmpty)
    }

    @Test func `start rejects every executable path except the fixed installation path`() async {
        let controller = SystemServiceController(
            apiServerURL: URL(fileURLWithPath: "/Applications/MacContainer.app/Contents/MacOS/MacContainer"),
            services: FakeServiceManager(),
            health: FakeHealthChecker(),
            machineAPI: FakeMachineAPIProbe(),
            workloads: FakeWorkloadManager(),
            configurationLoader: FakeSystemConfigurationLoader(),
            configuration: .testFixture
        )

        await #expect(throws: SystemServiceError.invalidAPIServerPath) {
            try await controller.start(timeout: .seconds(1))
        }
    }

    private func makeController(
        services: FakeServiceManager = FakeServiceManager(),
        health: any HealthChecking = FakeHealthChecker(),
        machines: FakeMachineAPIProbe = FakeMachineAPIProbe(),
        workloads: FakeWorkloadManager = FakeWorkloadManager(),
        configurationLoader: FakeSystemConfigurationLoader = FakeSystemConfigurationLoader(),
        retryPolicy: SystemServiceRetryPolicy = .init(
            initialDelay: .milliseconds(1),
            maximumDelay: .milliseconds(2),
            pingTimeout: .milliseconds(1)
        )
    ) -> SystemServiceController {
        SystemServiceController(
            apiServerURL: URL(fileURLWithPath: "/usr/local/bin/container-apiserver"),
            services: services,
            health: health,
            machineAPI: machines,
            workloads: workloads,
            configurationLoader: configurationLoader,
            configuration: .testFixture,
            retryPolicy: retryPolicy
        )
    }

    private func waitUntil(
        attempts: Int = 2000,
        condition: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0 ..< attempts {
            if await condition() {
                return
            }
            await Task.yield()
        }
        Issue.record("condition did not become true")
    }
}

private extension SystemServiceConfiguration {
    static let testFixture = SystemServiceConfiguration(
        applicationRoot: URL(fileURLWithPath: "/private/tmp/MacContainer-SystemServiceControllerTests"),
        installRoot: URL(fileURLWithPath: "/usr/local"),
        logRoot: nil,
        inheritedEnvironment: ["HTTPS_PROXY": "https://proxy.invalid"]
    )
}

private enum TestFailure: Error, Equatable {
    case unavailable
    case configuration
    case machineAPI
    case cleanup
}

private actor FakeServiceManager: ServiceManaging {
    private let deregisterError: TestFailure?
    private(set) var registeredLabels: Set<String>
    private(set) var registeredDefinitions: [ServiceDefinition] = []
    private(set) var deregisteredLabels: [String] = []

    init(registeredLabels: Set<String> = [], deregisterError: TestFailure? = nil) {
        self.registeredLabels = registeredLabels
        self.deregisterError = deregisterError
    }

    func register(_ definition: ServiceDefinition) async throws {
        registeredDefinitions.append(definition)
        registeredLabels.insert(definition.label)
    }

    func deregister(label: String) async throws {
        if let deregisterError {
            throw deregisterError
        }
        registeredLabels.remove(label)
        deregisteredLabels.append(label)
    }

    func isRegistered(label: String) async throws -> Bool {
        registeredLabels.contains(label)
    }

    func labels(prefix: String) async throws -> [String] {
        registeredLabels.filter { $0.hasPrefix(prefix) }.sorted()
    }
}

private actor FakeHealthChecker: HealthChecking {
    private var results: [Result<RuntimeHealth, TestFailure>]
    private(set) var pingCount = 0
    private(set) var requestedTimeouts: [Duration] = []

    init(results: [Result<RuntimeHealth, TestFailure>] = [
        .success(RuntimeHealth(healthy: true, version: "1.1.0"))
    ]) {
        self.results = results
    }

    func ping(timeout: Duration) async throws -> RuntimeHealth {
        pingCount += 1
        requestedTimeouts.append(timeout)
        guard !results.isEmpty else {
            throw TestFailure.unavailable
        }
        if results.count == 1 {
            return try results[0].get()
        }
        return try results.removeFirst().get()
    }
}

private struct BlockingHealthChecker: HealthChecking {
    func ping(timeout _: Duration) async throws -> RuntimeHealth {
        try await Task.sleep(for: .seconds(60))
        return RuntimeHealth(healthy: true, version: "unexpected")
    }
}

private actor FakeMachineAPIProbe: MachineAPIProbing {
    private let error: TestFailure?
    private(set) var verificationCount = 0

    init(error: TestFailure? = nil) {
        self.error = error
    }

    func verifyList() async throws {
        verificationCount += 1
        if let error {
            throw error
        }
    }
}

private actor FakeSystemConfigurationLoader: SystemConfigurationLoading {
    private let error: TestFailure?
    private(set) var loadCount = 0

    init(error: TestFailure? = nil) {
        self.error = error
    }

    func prepareAndLoad() async throws {
        loadCount += 1
        if let error {
            throw error
        }
    }
}

private actor FakeWorkloadManager: WorkloadManaging {
    private var inventories: [WorkloadInventory]
    private(set) var stopRequests: [Duration] = []

    init(inventories: [WorkloadInventory] = [.empty]) {
        self.inventories = inventories
    }

    func inventory() async throws -> WorkloadInventory {
        if inventories.count == 1 {
            return inventories[0]
        }
        return inventories.removeFirst()
    }

    func stopAll(_ inventory: WorkloadInventory, timeout: Duration) async throws {
        #expect(!inventory.isEmpty)
        stopRequests.append(timeout)
    }
}
