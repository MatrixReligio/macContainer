# Direct Runtime Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement typed, cancellable, direct Swift/XPC adapters for every supported Apple container 1.1.0 operation without launching the `container` executable or its lifecycle scripts.

**Architecture:** App-owned protocols and summaries isolate upstream types from the rest of the product. Production adapters delegate to exact 1.1.0 clients, while actor-backed fakes drive hosted tests; an operation coordinator serializes lifecycle, system, and per-resource mutations. Interactive sessions expose byte streams and resize/control methods directly to the later SwiftTerm adapter.

**Tech Stack:** Swift concurrency, actors, AsyncSequence, Foundation, Security/Keychain, Apple `ContainerAPIClient`, `ContainerBuild`, `ContainerNetworkClient`, `ContainerPersistence`, `ContainerPlugin`, `ContainerResource`, `ContainerXPC`, `MachineAPIClient` 1.1.0, Swift Testing.

---

## File map

- Create: `Sources/MCModel/RuntimeResources.swift`, `RuntimeRequests.swift`, `ProcessSession.swift`, `UserFacingError.swift`
- Create: `Sources/MCContainerBridge/RuntimeBridge.swift`, `UpstreamValueMapper.swift`, `OperationCoordinator.swift`
- Create: `Sources/MCContainerBridge/System/SystemServiceController.swift`, `SystemAdapter.swift`, `ConfigurationAdapter.swift`, `DNSAdapter.swift`, `KernelAdapter.swift`
- Create: `Sources/MCContainerBridge/Containers/ContainerAdapter.swift`, `ContainerProcessAdapter.swift`
- Create: `Sources/MCContainerBridge/Images/ImageAdapter.swift`
- Create: `Sources/MCContainerBridge/Builds/BuildAdapter.swift`, `BuilderAdapter.swift`
- Create: `Sources/MCContainerBridge/Networks/NetworkAdapter.swift`
- Create: `Sources/MCContainerBridge/Volumes/VolumeAdapter.swift`
- Create: `Sources/MCContainerBridge/Registries/RegistryAdapter.swift`, `RegistryCredentialStore.swift`
- Create: `Sources/MCContainerBridge/Machines/MachineAdapter.swift`, `MachineProcessAdapter.swift`
- Create: `Tests/TestSupport/FakeRuntimeBridge.swift`, `RecordedInvocation.swift`
- Create: focused tests under `Tests/MCContainerBridgeTests/`
- Create: `Config/contracts/apple-container-1.1.0-bridge-map.json`
- Create: `scripts/check-bridge-coverage.swift`
- Create: `docs/reviews/stage-3.md`
- Modify later: `docs/reviews/stage-5.md` backend evidence section

### Task 1: Define app-owned resource, request, process, and bridge protocols

**Files:**
- Create: `Sources/MCModel/RuntimeResources.swift`
- Create: `Sources/MCModel/RuntimeRequests.swift`
- Create: `Sources/MCModel/ProcessSession.swift`
- Create: `Sources/MCContainerBridge/RuntimeBridge.swift`
- Test: `Tests/MCContainerBridgeTests/RuntimeBridgeContractTests.swift`

- [x] **Step 1: Write failing protocol conformance tests**

```swift
import Testing
import MCModel
@testable import MCContainerBridge

@Test func fakeBridgeCanRepresentEveryDomain() async throws {
    let bridge = FakeRuntimeBridge()
    #expect(try await bridge.containers.list().isEmpty)
    #expect(try await bridge.images.list().isEmpty)
    #expect(try await bridge.builders.status().state == .stopped)
    #expect(try await bridge.networks.list().isEmpty)
    #expect(try await bridge.volumes.list().isEmpty)
    #expect(try await bridge.registries.list().isEmpty)
    #expect(try await bridge.machines.list().isEmpty)
    #expect(try await bridge.system.status().state == .stopped)
}
```

- [x] **Step 2: Run and verify RED**

Run: `swift test --filter RuntimeBridgeContractTests`

Expected: FAIL because the protocol family is undefined.

- [x] **Step 3: Define the protocol family**

```swift
public protocol RuntimeBridge: Sendable {
    var containers: any ContainerOperations { get }
    var images: any ImageOperations { get }
    var builds: any BuildOperations { get }
    var builders: any BuilderOperations { get }
    var networks: any NetworkOperations { get }
    var volumes: any VolumeOperations { get }
    var registries: any RegistryOperations { get }
    var machines: any MachineOperations { get }
    var system: any SystemOperations { get }
    var dns: any DNSOperations { get }
    var kernel: any KernelOperations { get }
    var configuration: any ConfigurationOperations { get }
}

public protocol ContainerOperations: Sendable {
    func create(_ request: ContainerCreateRequest) async throws -> ContainerSummary
    func start(ids: [String]) async throws -> [BatchItemResult]
    func stop(ids: [String], timeout: Duration?) async throws -> [BatchItemResult]
    func kill(ids: [String], signal: String) async throws -> [BatchItemResult]
    func delete(ids: [String], force: Bool) async throws -> [BatchItemResult]
    func list() async throws -> [ContainerSummary]
    func exec(_ request: ProcessRequest) async throws -> any ProcessSession
    func export(id: String, destination: URL) async throws
    func logs(id: String, options: LogOptions) async throws -> AsyncThrowingStream<LogRecord, Error>
    func inspect(id: String) async throws -> ContainerDetail
    func stats(id: String) async throws -> AsyncThrowingStream<ContainerStats, Error>
    func copy(_ request: CopyRequest) async throws
    func prune() async throws -> PruneResult
}

public protocol ImageOperations: Sendable {
    func list() async throws -> [ImageSummary]
    func pull(_ request: ImageTransferRequest) async throws -> AsyncThrowingStream<TransferProgress, Error>
    func push(_ request: ImageTransferRequest) async throws -> AsyncThrowingStream<TransferProgress, Error>
    func save(references: [String], destination: URL) async throws
    func load(source: URL) async throws -> [ImageSummary]
    func tag(source: String, target: String) async throws
    func delete(references: [String]) async throws -> [BatchItemResult]
    func prune() async throws -> PruneResult
    func inspect(reference: String) async throws -> ImageDetail
}

public protocol NetworkOperations: Sendable {
    func create(_ request: NetworkCreateRequest) async throws -> NetworkSummary
    func delete(ids: [String]) async throws -> [BatchItemResult]
    func prune() async throws -> PruneResult
    func list() async throws -> [NetworkSummary]
    func inspect(id: String) async throws -> NetworkDetail
}

public protocol VolumeOperations: Sendable {
    func create(_ request: VolumeCreateRequest) async throws -> VolumeSummary
    func delete(names: [String]) async throws -> [BatchItemResult]
    func prune() async throws -> PruneResult
    func list() async throws -> [VolumeSummary]
    func inspect(name: String) async throws -> VolumeDetail
}

public protocol BuildOperations: Sendable {
    func build(_ request: BuildRequest) async throws -> AsyncThrowingStream<BuildProgress, Error>
}

public protocol BuilderOperations: Sendable {
    func start(_ request: BuilderStartRequest) async throws -> BuilderSummary
    func status() async throws -> BuilderSummary
    func stop() async throws
    func delete() async throws
}

public protocol RegistryOperations: Sendable {
    func login(_ request: RegistryLoginRequest) async throws -> RegistrySummary
    func logout(server: String) async throws
    func list() async throws -> [RegistrySummary]
}

public protocol MachineOperations: Sendable {
    func create(_ request: MachineCreateRequest) async throws -> MachineSummary
    func run(_ request: MachineRunRequest) async throws -> any ProcessSession
    func list() async throws -> [MachineSummary]
    func inspect(id: String) async throws -> MachineDetail
    func set(id: String, request: MachineSetRequest) async throws -> MachineSummary
    func setDefault(id: String) async throws
    func logs(id: String, options: LogOptions) async throws -> AsyncThrowingStream<LogRecord, Error>
    func stop(ids: [String], force: Bool) async throws -> [BatchItemResult]
    func delete(ids: [String], force: Bool) async throws -> [BatchItemResult]
}

public protocol SystemOperations: Sendable {
    func start(_ request: SystemStartRequest) async throws -> SystemSummary
    func stop(_ request: SystemStopRequest) async throws -> SystemSummary
    func status() async throws -> SystemSummary
    func version() async throws -> RuntimeVersionSummary
    func logs(_ options: LogOptions) async throws -> AsyncThrowingStream<LogRecord, Error>
    func diskUsage() async throws -> DiskUsageSummary
}

public protocol DNSOperations: Sendable {
    func create(_ request: DNSCreateRequest) async throws -> DNSEntry
    func delete(names: [String]) async throws -> [BatchItemResult]
    func list() async throws -> [DNSEntry]
}

public protocol KernelOperations: Sendable {
    func setRecommended(platform: String, force: Bool) async throws -> KernelSummary
    func setLocalBinary(_ url: URL, platform: String, force: Bool) async throws -> KernelSummary
    func setLocalArchive(_ url: URL, platform: String, force: Bool) async throws -> KernelSummary
    func setVerifiedRemoteArchive(_ request: VerifiedKernelArchiveRequest) async throws -> KernelSummary
}

public protocol ConfigurationOperations: Sendable {
    func load() async throws -> SystemConfiguration
    func validate(_ configuration: SystemConfiguration) async -> [ValidationIssue]
    func preview(_ configuration: SystemConfiguration) async throws -> String
    func save(_ configuration: SystemConfiguration) async throws -> ConfigurationSaveReport
    func apply(_ request: ConfigurationApplyRequest) async throws -> ConfigurationApplyReport
    func export(_ configuration: SystemConfiguration, destination: URL) async throws
}
```

App-owned request/summary types are `Codable`, `Equatable`, `Sendable`, use stable string IDs, retain raw diagnostic JSON only after secret redaction, and never expose upstream protobuf objects across module boundaries.

- [x] **Step 4: Implement actor-backed fakes and run contract tests**

`FakeRuntimeBridge` records `RecordedInvocation(operationID: String, resourceIDs: [String], redactedArguments: [String: String])` in an actor and returns configurable result queues. It rejects secret values in recorded arguments.

Run: `swift test --filter RuntimeBridgeContractTests`

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add Sources/MCModel Sources/MCContainerBridge/RuntimeBridge.swift Tests/TestSupport Tests/MCContainerBridgeTests/RuntimeBridgeContractTests.swift
git commit -m "feat: define direct runtime bridge contracts"
```

### Task 2: Serialize conflicting operations with cancellation-safe locks

**Files:**
- Create: `Sources/MCContainerBridge/OperationCoordinator.swift`
- Test: `Tests/MCContainerBridgeTests/OperationCoordinatorTests.swift`

- [ ] **Step 1: Write failing serialization and cancellation tests**

```swift
@Suite("Operation coordinator")
struct OperationCoordinatorTests {
    @Test func sameResourceSerializesWhileDifferentResourcesOverlap() async throws {
        let coordinator = OperationCoordinator()
        let recorder = ConcurrencyRecorder()
        async let first: Void = coordinator.withLock(.container("one")) { await recorder.hold("one-a") }
        async let second: Void = coordinator.withLock(.container("one")) { await recorder.hold("one-b") }
        async let third: Void = coordinator.withLock(.container("two")) { await recorder.hold("two") }
        _ = try await (first, second, third)
        #expect(await recorder.maximum(for: "one") == 1)
        #expect(await recorder.globalMaximum >= 2)
    }

    @Test func cancelledWaiterNeverOwnsLock() async throws {
        let coordinator = OperationCoordinator()
        let owner = Task { try await coordinator.withLock(.lifecycle) { try await Task.sleep(for: .seconds(1)) } }
        let waiter = Task { try await coordinator.withLock(.lifecycle) { Issue.record("cancelled waiter entered") } }
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        owner.cancel()
    }
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter OperationCoordinatorTests`

Expected: FAIL because the actor is undefined.

- [ ] **Step 3: Implement lock keys and FIFO waiter ownership**

```swift
public enum OperationLockKey: Hashable, Sendable {
    case lifecycle, systemService
    case container(String), image(String), builder, network(String), volume(String), registry(String), machine(String)
}

public actor OperationCoordinator {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var owners: Set<OperationLockKey> = []
    private var waiters: [OperationLockKey: [Waiter]] = [:]

    public func withLock<T: Sendable>(
        _ key: OperationLockKey,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        try Task.checkCancellation()
        let token = UUID()
        try await acquire(key, token: token)
        defer { release(key) }
        return try await operation()
    }
}
```

`acquire` installs a cancellation handler that removes and resumes a cancelled waiter with `CancellationError`; `release` transfers ownership exactly once to the oldest insertion-ordered waiter. Lifecycle acquisition additionally blocks system and all mutation keys; system-service acquisition conflicts with lifecycle.

- [ ] **Step 4: Run the race suite under Thread Sanitizer**

Run: `swift test --filter OperationCoordinatorTests && xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -configuration Debug -enableThreadSanitizer YES CODE_SIGNING_ALLOWED=NO build`

Expected: PASS and no sanitizer diagnostic.

- [ ] **Step 5: Commit**

```bash
git add Sources/MCContainerBridge/OperationCoordinator.swift Tests/MCContainerBridgeTests/OperationCoordinatorTests.swift
git commit -m "feat: coordinate conflicting runtime work"
```

### Task 3: Implement the system service controller directly

**Files:**
- Create: `Sources/MCContainerBridge/System/SystemServiceController.swift`
- Test: `Tests/MCContainerBridgeTests/SystemServiceControllerTests.swift`

- [ ] **Step 1: Write failing path, registration, health, and cleanup tests**

```swift
@Test func startUsesInstalledAPIServerNotAppExecutable() async throws {
    let services = FakeServiceManagement()
    let health = FakeHealthClient(sequence: [.unavailable, .healthy(version: "1.1.0")])
    let controller = SystemServiceController(
        apiServerURL: URL(fileURLWithPath: "/usr/local/bin/container-apiserver"),
        services: services,
        health: health,
        configuration: .fixture
    )
    try await controller.start(timeout: .seconds(5))
    #expect(await services.lastProgram == "/usr/local/bin/container-apiserver")
    #expect(await services.lastProgram != CommandLine.arguments[0])
}

@Test func failedHealthCheckDeregistersService() async {
    let services = FakeServiceManagement()
    let controller = SystemServiceController(apiServerURL: .installedFixture, services: services, health: .alwaysUnavailable, configuration: .fixture)
    await #expect(throws: SystemServiceError.healthTimeout.self) { try await controller.start(timeout: .milliseconds(20)) }
    #expect(await services.isRegistered == false)
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter SystemServiceControllerTests`

Expected: FAIL because the controller is undefined.

- [ ] **Step 3: Implement direct service lifecycle**

The production controller builds `LaunchPlist` for `/usr/local/bin/container-apiserver`, loads configuration through `ConfigurationLoader`, calls `ServiceManager.register`, polls `ClientHealthCheck.ping` with bounded exponential backoff, verifies `MachineClient().list()`, and deregisters on partial start failure. Stop obtains direct container/machine inventories, refuses unsafe stop without explicit policy, asks clients to stop gracefully, and calls `ServiceManager.deregister`; it never calls `Application.SystemStart`, `/usr/local/bin/container`, or shell scripts. The fixed `/bin/launchctl` subprocess used internally by upstream `ServiceManager` is allowlisted only for `bootstrap`, `bootout`, `kickstart`, `kill`, `list`, and `managername` with validated labels/plists.

The injectable boundary is:

```swift
public protocol ServiceManaging: Sendable {
    func register(_ definition: ServiceDefinition) async throws
    func deregister(label: String) async throws
    func isRegistered(label: String) async throws -> Bool
    func labels(prefix: String) async throws -> [String]
}

public protocol HealthChecking: Sendable {
    func ping(timeout: Duration) async throws -> RuntimeHealth
}
```

- [ ] **Step 4: Run focused tests and forbidden-backend scanner**

Run: `swift test --filter SystemServiceControllerTests && scripts/check-no-container-cli.sh .`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MCContainerBridge/System Tests/MCContainerBridgeTests/SystemServiceControllerTests.swift
git commit -m "feat: manage container services through direct APIs"
```

### Task 4: Implement all container operations and process I/O

**Files:**
- Create: `Sources/MCContainerBridge/Containers/ContainerAdapter.swift`
- Create: `Sources/MCContainerBridge/Containers/ContainerProcessAdapter.swift`
- Create: `Sources/MCContainerBridge/UpstreamValueMapper.swift`
- Test: `Tests/MCContainerBridgeTests/ContainerAdapterTests.swift`
- Test: `Tests/MCContainerBridgeTests/ContainerProcessAdapterTests.swift`

- [ ] **Step 1: Write failing request mapping and batch-result tests**

```swift
@Test func createMapsEveryAffectingField() async throws {
    let upstream = FakeContainerClient()
    let adapter = ContainerAdapter(client: upstream, coordinator: .init())
    let request = ContainerCreateRequest.fixture
    _ = try await adapter.create(request)
    let mapped = try #require(await upstream.lastCreate)
    #expect(mapped.imageReference == request.imageReference)
    #expect(mapped.resources.cpuCount == request.cpuCount)
    #expect(mapped.resources.memoryBytes == request.memoryBytes)
    #expect(mapped.environment == request.environment)
    #expect(mapped.mounts.count == request.mounts.count)
    #expect(mapped.networks == request.networks)
    #expect(mapped.readOnlyRoot == request.readOnlyRoot)
}

@Test func batchDeletePreservesPartialFailure() async throws {
    let upstream = FakeContainerClient(deleteResults: ["a": .success, "b": .failure(.busy)])
    let results = try await ContainerAdapter(client: upstream, coordinator: .init()).delete(ids: ["a", "b"], force: false)
    #expect(results.count == 2)
    #expect(results[0].id == "a" && results[0].succeeded)
    #expect(results[1].id == "b" && !results[1].succeeded)
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter ContainerAdapterTests`

Expected: FAIL because production adapters are undefined.

- [ ] **Step 3: Implement all 14 container operations plus core run composition**

Map app requests to `ContainerClient` configuration and direct methods for create/list/get/bootstrap/stop/kill/delete/createProcess/log/stats/copy/export. `core.run` is composed as create → bootstrap → optional process attach, guarded by one per-container lock; remove-on-exit cleanup executes in `defer` and reports cleanup failure separately from process exit.

Every batch mutation uses a stable input order and returns `BatchItemResult` for each item. Prefix resolution rejects zero or multiple matches before mutation. Export/save destinations are already-open security-scoped URLs supplied by the app, not arbitrary strings.

- [ ] **Step 4: Implement and test direct interactive process streams**

```swift
public protocol ProcessSession: Sendable {
    var id: String { get }
    var output: AsyncThrowingStream<ProcessOutputChunk, Error> { get }
    func send(_ data: Data) async throws
    func resize(columns: Int, rows: Int) async throws
    func wait() async throws -> ProcessExit
    func terminate(signal: String) async throws
    func detach() async throws
}

public enum ProcessOutputChunk: Equatable, Sendable {
    case stdout(Data), stderr(Data), terminal(Data)
}
```

`ContainerProcessAdapter` connects upstream stdin/stdout/stderr file handles, propagates EOF exactly once, clamps resize to 1...1,000 columns/rows, validates signals through the contract, and cancels reader tasks on close.

Run: `swift test --filter ContainerAdapterTests && swift test --filter ContainerProcessAdapterTests`

Expected: PASS, including TTY resize, binary bytes, split stdout/stderr, cancellation, detach, and exit-status cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/MCContainerBridge/Containers Sources/MCContainerBridge/UpstreamValueMapper.swift Sources/MCModel Tests/MCContainerBridgeTests/ContainerAdapterTests.swift Tests/MCContainerBridgeTests/ContainerProcessAdapterTests.swift
git commit -m "feat: bridge all container operations directly"
```

### Task 5: Implement image, build, and builder operations

**Files:**
- Create: `Sources/MCContainerBridge/Images/ImageAdapter.swift`
- Create: `Sources/MCContainerBridge/Builds/BuildAdapter.swift`
- Create: `Sources/MCContainerBridge/Builds/BuilderAdapter.swift`
- Test: matching adapter tests

- [ ] **Step 1: Write failing coverage tests**

```swift
@Test func imageAdapterRecordsAllNineActions() async throws {
    let upstream = FakeImageClient()
    let adapter = ImageAdapter(client: upstream, coordinator: .init())
    _ = try await adapter.list()
    _ = try await adapter.pull(.fixture).collect()
    _ = try await adapter.push(.fixture).collect()
    try await adapter.save(references: ["example:latest"], destination: .temporaryFixture)
    _ = try await adapter.load(source: .temporaryFixture)
    try await adapter.tag(source: "example:latest", target: "example:test")
    _ = try await adapter.delete(references: ["example:test"])
    _ = try await adapter.prune()
    _ = try await adapter.inspect(reference: "example:latest")
    #expect(await upstream.operationIDs == ["list", "pull", "push", "save", "load", "tag", "delete", "prune", "inspect"])
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter 'ImageAdapterTests|BuildAdapterTests|BuilderAdapterTests'`

Expected: FAIL because the adapters are absent.

- [ ] **Step 3: Implement direct adapters**

`ImageAdapter` wraps `ClientImage` list/get/pull/push/save/load/tag/delete/unpack calls, canonicalizes references without losing digests, and maps transfer progress to monotonic byte/layer records. `BuildAdapter` uses `ContainerBuild` with a security-scoped local context URL, Dockerfile path confined beneath that context after symlink resolution, typed build arguments/secrets/SSH consent, platform/output/cache options, and an async progress stream. `BuilderAdapter` directly performs start/status/stop/delete and reports its resource state.

- [ ] **Step 4: Test path confinement, progress, cancellation, and operation coverage**

Run: `swift test --filter 'ImageAdapterTests|BuildAdapterTests|BuilderAdapterTests'`

Expected: PASS. Archive traversal, Dockerfile escape, regressing progress, secret logging, and cancelled build cases are rejected.

- [ ] **Step 5: Commit**

```bash
git add Sources/MCContainerBridge/Images Sources/MCContainerBridge/Builds Tests/MCContainerBridgeTests
git commit -m "feat: bridge images builds and builder"
```

### Task 6: Implement network, volume, and registry operations

**Files:**
- Create: `Sources/MCContainerBridge/Networks/NetworkAdapter.swift`
- Create: `Sources/MCContainerBridge/Volumes/VolumeAdapter.swift`
- Create: `Sources/MCContainerBridge/Registries/RegistryAdapter.swift`
- Create: `Sources/MCContainerBridge/Registries/RegistryCredentialStore.swift`
- Test: matching adapter/security tests

- [ ] **Step 1: Write failing domain tests**

Test five network actions, five volume actions, and login/list/logout. Include rejection of deleting the built-in network, duplicate volume name conflict, Keychain item accessibility, secret redaction, and logout idempotence.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter 'NetworkAdapterTests|VolumeAdapterTests|RegistryAdapterTests|RegistryCredentialStoreTests'`

Expected: FAIL because adapters are absent.

- [ ] **Step 3: Implement direct adapters and Keychain storage**

`NetworkAdapter` delegates to `NetworkClient`, preserving subnet/gateway/DNS/plugin/status fields and protecting built-ins. `VolumeAdapter` delegates to `ClientVolume` and validates volume names before lookup/create. `RegistryCredentialStore` uses `kSecClassInternetPassword`, `kSecAttrService = "com.apple.container.registry"`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, returns metadata without password data for list, and zeroizes transient `Data` buffers after login.

- [ ] **Step 4: Run tests with an isolated temporary Keychain**

Run a test-created keychain under `.artifacts/test-keychains/${RUN_UUID}.keychain-db`, select it only for the test process, delete it in `defer`, and verify the user's default keychain list before/after is identical.

Expected: all focused tests PASS and the temporary keychain no longer exists.

- [ ] **Step 5: Commit**

```bash
git add Sources/MCContainerBridge/Networks Sources/MCContainerBridge/Volumes Sources/MCContainerBridge/Registries Tests/MCContainerBridgeTests
git commit -m "feat: bridge networks volumes and registries"
```

### Task 7: Implement all machine operations and process sessions

**Files:**
- Create: `Sources/MCContainerBridge/Machines/MachineAdapter.swift`
- Create: `Sources/MCContainerBridge/Machines/MachineProcessAdapter.swift`
- Test: `Tests/MCContainerBridgeTests/MachineAdapterTests.swift`

- [ ] **Step 1: Write failing nine-operation and capability tests**

The test invokes create, run, list, inspect, set, set-default, logs, stop, and delete; verifies CPU/memory/disk/home sharing/network/kernel mapping; rejects nested virtualization without capability; and verifies machine process output/resize/exit behavior.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter MachineAdapterTests`

Expected: FAIL because adapters are absent.

- [ ] **Step 3: Implement direct `MachineClient` mapping**

Use `MachineClient` list/create/start/stop/update/delete/default APIs and upstream machine configuration types. `run` composes create/start plus a direct process through `ContainerClient().createProcess` for the machine's container identity; it does not invoke a command. Home sharing remains absent unless the request contains an explicit consent token, which is consumed and not persisted. Kernel identifiers are validated against the kernel adapter.

- [ ] **Step 4: Run focused tests**

Run: `swift test --filter MachineAdapterTests`

Expected: PASS with all nine stable operation IDs recorded.

- [ ] **Step 5: Commit**

```bash
git add Sources/MCContainerBridge/Machines Tests/MCContainerBridgeTests/MachineAdapterTests.swift
git commit -m "feat: bridge all machine operations"
```

### Task 8: Implement system, DNS, kernel, and typed configuration operations

**Files:**
- Create: `Sources/MCContainerBridge/System/SystemAdapter.swift`
- Create: `Sources/MCContainerBridge/System/DNSAdapter.swift`
- Create: `Sources/MCContainerBridge/System/KernelAdapter.swift`
- Create: `Sources/MCContainerBridge/System/ConfigurationAdapter.swift`
- Test: four matching test files

- [ ] **Step 1: Write failing operation tests**

Tests cover system start/stop/status/version/logs/disk usage; DNS create/delete/list; kernel set from recommended release, local binary, local archive, and verified remote archive; configuration load/validate/preview/atomic-save/apply/export. A remote archive without an expected digest must fail before network access.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter 'SystemAdapterTests|DNSAdapterTests|KernelAdapterTests|ConfigurationAdapterTests'`

Expected: FAIL because adapters are absent.

- [ ] **Step 3: Implement direct system-domain adapters**

`SystemAdapter` composes `SystemServiceController`, `ClientHealthCheck`, `ClientDiskUsage`, and unified-log streaming APIs. `DNSAdapter` uses typed upstream DNS calls and restricts resolver names to `containerization.${VALIDATED_SUFFIX}` after strict suffix validation. `KernelAdapter` wraps `ClientKernel.getDefaultKernel`, `installKernel`, and `installKernelFromTar`, downloads only through an injected downloader after digest/allowlist input is present, and blocks archive traversal. `ConfigurationAdapter` uses `ConfigurationLoader`/`ContainerPersistence`, writes a `0600` atomic file, preserves one last-known-good copy, produces a TOML preview, and requires an idle confirmation token before controlled restart.

- [ ] **Step 4: Run focused suites and failure injection**

Run: `swift test --filter 'SystemAdapterTests|DNSAdapterTests|KernelAdapterTests|ConfigurationAdapterTests' && scripts/check-no-container-cli.sh .`

Expected: PASS. Atomic-write failure retains the old config, restart failure restores last-known-good, and temporary download/archive files are absent after each test.

- [ ] **Step 5: Commit**

```bash
git add Sources/MCContainerBridge/System Tests/MCContainerBridgeTests
git commit -m "feat: bridge all system operations"
```

### Task 9: Prove exact contract-to-bridge coverage

**Files:**
- Create: `Config/contracts/apple-container-1.1.0-bridge-map.json`
- Create: `scripts/check-bridge-coverage.swift`
- Test: `Tests/MCContainerBridgeTests/BridgeCoverageTests.swift`

- [ ] **Step 1: Write the failing parity test**

```swift
@Test func everyContractOperationHasExactlyOneBridgeAction() throws {
    let contract = try ContractRepository.bundled(version: .init(major: 1, minor: 1, patch: 0))
    let map = try BridgeMap.bundled110()
    #expect(Set(map.entries.map(\.operationID)) == Set(contract.operations.map(\.id)))
    #expect(Dictionary(grouping: map.entries, by: \.operationID).values.allSatisfy { $0.count == 1 })
    #expect(map.entries.allSatisfy { $0.backend != .commandLine })
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter BridgeCoverageTests`

Expected: FAIL because the bridge map is absent.

- [ ] **Step 3: Add one direct mapping per operation**

Each JSON entry contains `operationID`, app protocol method, production adapter type, upstream type/method, focused test name, cancellation behavior, lock key, and backend fixed to `directSwiftAPI`, `directXPC`, `Security.framework`, or `nativeServiceManagement`. The checker rejects any `Process`, `shell`, `commandLine`, missing test, duplicate operation, or operation not present in the contract.

- [ ] **Step 4: Run parity and source/runtime execution audits**

Run:

```bash
swift test --filter BridgeCoverageTests
swift scripts/check-bridge-coverage.swift Sources/MCContracts/Resources/apple-container-1.1.0.json Config/contracts/apple-container-1.1.0-bridge-map.json
scripts/check-no-container-cli.sh .
```

Expected: `Bridge coverage PASS: 61 operations, 61 direct mappings, 0 CLI backends`.

- [ ] **Step 5: Commit**

```bash
git add Config/contracts/apple-container-1.1.0-bridge-map.json scripts/check-bridge-coverage.swift Tests/MCContainerBridgeTests/BridgeCoverageTests.swift
git commit -m "test: prove complete direct API coverage"
```

### Task 10: Complete Stage 3 and backend Stage 5 reviews

**Files:**
- Create: `docs/reviews/stage-3.md`
- Create: `docs/reviews/stage-5.md`

- [ ] **Step 1: Run all bridge evidence**

Run:

```bash
swift test --filter MCContainerBridgeTests
swift test --parallel
scripts/check-no-container-cli.sh .
swift scripts/check-bridge-coverage.swift Sources/MCContracts/Resources/apple-container-1.1.0.json Config/contracts/apple-container-1.1.0-bridge-map.json
git diff --check
```

Expected: PASS.

- [ ] **Step 2: Review API correctness and concurrency**

Inspect every adapter against upstream 1.1.0 signatures; verify no `ContainerCommands`/CLI dependency, exact cancellation cleanup, no detached lifecycle ownership, stable partial results, prefix ambiguity handling, Keychain isolation, archive/path confinement, terminal binary safety, lock conflicts, and service-start cleanup. Fix every finding and rerun focused tests.

- [ ] **Step 3: Commit Stage 3 and the backend section of Stage 5**

```bash
git add docs/reviews/stage-3.md docs/reviews/stage-5.md
git commit -m "docs: close direct runtime bridge review"
git push origin main
```

Expected: Stage 3 says `Gate: PASS`; Stage 5 remains explicitly `Gate: PENDING UI` while its backend section has no unresolved finding.
