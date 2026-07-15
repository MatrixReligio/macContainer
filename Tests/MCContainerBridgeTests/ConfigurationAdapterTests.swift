import Foundation
@testable import MCContainerBridge
import MCModel
import Testing

@Suite("Configuration adapter")
struct ConfigurationAdapterTests {
    @Test func `preview is deterministic and save preserves a 0600 last known good file`() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appending(path: "config.toml")
        try "[container]\ncpus = 2\n".write(to: destination, atomically: true, encoding: .utf8)
        let adapter = ConfigurationAdapter(
            storage: AtomicConfigurationStorage(destination: destination),
            runtime: FakeConfigurationRuntime()
        )
        let configuration = SystemConfiguration(values: ["container.memory": "2gb", "container.cpus": "4"])

        let preview = try await adapter.preview(configuration)
        let report = try await adapter.save(configuration)

        #expect(preview.contains("[container]"))
        #expect(preview.range(of: "cpus = 4") != nil)
        #expect(report.destination == destination)
        #expect(report.lastKnownGoodPreserved)
        #expect(try String(contentsOf: destination, encoding: .utf8) == preview)
        let lastKnownGood = destination.appendingPathExtension("last-known-good")
        #expect(try String(contentsOf: lastKnownGood, encoding: .utf8).contains("cpus = 2"))
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        let permissions = try #require(attributes[.posixPermissions] as? Int)
        #expect(permissions == 0o600)
    }

    @Test func `validation reports unknown and malformed typed values without writing`() async {
        let storage = RecordingConfigurationStorage()
        let adapter = ConfigurationAdapter(storage: storage, runtime: FakeConfigurationRuntime())
        let issues = await adapter.validate(.init(values: [
            "container.cpus": "zero",
            "untrusted.command": "rm -rf /"
        ]))

        #expect(issues.map(\.parameterID) == ["container.cpus", "untrusted.command"])
        #expect(issues.allSatisfy { $0.severity == .error })
        #expect(await storage.writeCount == 0)
    }

    @Test func `load rejects unknown TOML instead of silently deleting it on a later save`() async {
        let storage = RecordingConfigurationStorage(contents: "[plugin.unreviewed]\nenabled = true\n")
        let adapter = ConfigurationAdapter(storage: storage, runtime: FakeConfigurationRuntime())

        await #expect(throws: ConfigurationAdapterError.invalidConfiguration([
            .init(
                parameterID: "plugin.unreviewed.enabled",
                severity: .error,
                messageKey: "validation.configuration.unknown",
                recoveryKey: "validation.configuration.unknown.recovery"
            ),
            .init(
                parameterID: "plugin",
                severity: .error,
                messageKey: "validation.configuration.unknown",
                recoveryKey: "validation.configuration.unknown.recovery"
            ),
            .init(
                parameterID: "plugin.unreviewed",
                severity: .error,
                messageKey: "validation.configuration.unknown",
                recoveryKey: "validation.configuration.unknown.recovery"
            )
        ].sorted())) {
            try await adapter.load()
        }
        #expect(await storage.writeCount == 0)
    }

    @Test func `known TOML loads as typed values and export is private and atomic`() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appending(path: "config.toml")
        try "[container]\ncpus = 4\nmemory = \"2gb\"\n".write(
            to: destination,
            atomically: true,
            encoding: .utf8
        )
        let adapter = ConfigurationAdapter(
            storage: AtomicConfigurationStorage(destination: destination),
            runtime: FakeConfigurationRuntime()
        )

        let loaded = try await adapter.load()
        #expect(loaded.values["container.cpus"] == "4")
        #expect(loaded.values["container.memory"] == "2gb")

        let exported = root.appending(path: "exported.toml")
        try await adapter.export(.init(values: ["container.cpus": "6"]), destination: exported)
        #expect(try String(contentsOf: exported, encoding: .utf8) == "[container]\ncpus = 6\n")
        let attributes = try FileManager.default.attributesOfItem(atPath: exported.path)
        #expect(try #require(attributes[.posixPermissions] as? Int) == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).count == 2)
    }

    @Test func `apply requires an idle one-time token then restarts`() async throws {
        let storage = RecordingConfigurationStorage(contents: "[container]\ncpus = 2\n")
        let runtime = FakeConfigurationRuntime()
        let adapter = ConfigurationAdapter(storage: storage, runtime: runtime)
        let token = UUID()
        let request = ConfigurationApplyRequest(
            configuration: .init(values: ["container.cpus": "4"]),
            idleConfirmationToken: token
        )

        #expect(try await adapter.apply(request) == .init(restarted: true))
        #expect(await runtime.events == ["inventory", "stop", "start"])
        await #expect(throws: ConfigurationAdapterError.confirmationTokenAlreadyUsed) {
            try await adapter.apply(request)
        }
    }

    @Test func `active workloads reject apply before save or restart`() async {
        let storage = RecordingConfigurationStorage(contents: "old")
        let runtime = FakeConfigurationRuntime(inventory: .init(activeContainerIDs: ["web"], activeMachineIDs: []))
        let adapter = ConfigurationAdapter(storage: storage, runtime: runtime)

        await #expect(throws: ConfigurationAdapterError.activeWorkloads(containers: 1, machines: 0)) {
            try await adapter.apply(.init(configuration: .empty, idleConfirmationToken: UUID()))
        }
        #expect(await storage.writeCount == 0)
        #expect(await runtime.events == ["inventory"])
    }

    @Test func `restart failure restores the exact prior bytes and restarts last known good`() async throws {
        let old = "[container]\ncpus = 2\n"
        let storage = RecordingConfigurationStorage(contents: old)
        let runtime = FakeConfigurationRuntime(startFailures: 1)
        let adapter = ConfigurationAdapter(storage: storage, runtime: runtime)

        let report = try await adapter.apply(.init(
            configuration: .init(values: ["container.cpus": "4"]),
            idleConfirmationToken: UUID()
        ))

        #expect(report == .init(restarted: true, restoredLastKnownGood: true))
        #expect(await storage.contents == old)
        #expect(await runtime.events == ["inventory", "stop", "start", "start"])
    }

    @Test func `atomic save failure leaves original bytes untouched`() async {
        let storage = RecordingConfigurationStorage(contents: "original", writeError: ConfigurationTestFailure.write)
        let adapter = ConfigurationAdapter(storage: storage, runtime: FakeConfigurationRuntime())

        await #expect(throws: ConfigurationTestFailure.write) {
            try await adapter.save(.init(values: ["container.cpus": "4"]))
        }
        #expect(await storage.contents == "original")
    }

    @Test func `production storage rejects oversized replacement without residue`() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appending(path: "config.toml")
        try "original".write(to: destination, atomically: true, encoding: .utf8)
        let storage = AtomicConfigurationStorage(destination: destination, maximumBytes: 16)

        await #expect(throws: ConfigurationAdapterError.configurationTooLarge) {
            try await storage.write(String(repeating: "x", count: 17), preserveLastKnownGood: true)
        }

        #expect(try String(contentsOf: destination, encoding: .utf8) == "original")
        #expect(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) == [destination])
    }

    @Test func `cancellation still restores old configuration in an uncancelled recovery task`() async throws {
        let old = "[container]\ncpus = 2\n"
        let storage = RecordingConfigurationStorage(contents: old)
        let runtime = CancellationConfigurationRuntime()
        let adapter = ConfigurationAdapter(storage: storage, runtime: runtime)
        let task = Task {
            try await adapter.apply(.init(
                configuration: .init(values: ["container.cpus": "4"]),
                idleConfirmationToken: UUID()
            ))
        }
        for _ in 0 ..< 2000 {
            if await runtime.startCount == 1 {
                break
            }
            await Task.yield()
        }
        #expect(await runtime.startCount == 1)

        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        #expect(await storage.contents == old)
        #expect(await runtime.startCount == 2)
    }

    private func makeRoot() throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: ".mc-configuration-adapter-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private actor RecordingConfigurationStorage: ConfigurationStoring {
    nonisolated let destination = URL(fileURLWithPath: "/virtual/config.toml")
    var contents: String?
    var writeCount = 0
    let writeError: (any Error)?

    init(contents: String? = nil, writeError: (any Error)? = nil) {
        self.contents = contents
        self.writeError = writeError
    }

    func read() async throws -> String? {
        contents
    }

    func write(_ value: String, preserveLastKnownGood _: Bool) async throws -> Bool {
        writeCount += 1
        if let writeError {
            throw writeError
        }
        let preserved = contents != nil
        contents = value
        return preserved
    }

    func restore(_ value: String?) async throws {
        contents = value
    }

    func export(_ value: String, to _: URL) async throws {
        contents = value
    }
}

private actor FakeConfigurationRuntime: ConfigurationRuntimeManaging {
    let configuredInventory: WorkloadInventory
    var remainingStartFailures: Int
    var events: [String] = []

    init(inventory: WorkloadInventory = .empty, startFailures: Int = 0) {
        configuredInventory = inventory
        remainingStartFailures = startFailures
    }

    func inventory() async throws -> WorkloadInventory {
        events.append("inventory")
        return configuredInventory
    }

    func stop() async throws {
        events.append("stop")
    }

    func start() async throws {
        events.append("start")
        if remainingStartFailures > 0 {
            remainingStartFailures -= 1
            throw ConfigurationTestFailure.restart
        }
    }
}

private actor CancellationConfigurationRuntime: ConfigurationRuntimeManaging {
    var startCount = 0

    func inventory() async throws -> WorkloadInventory {
        .empty
    }

    func stop() async throws {}

    func start() async throws {
        startCount += 1
        guard startCount == 1 else { return }
        while true {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private enum ConfigurationTestFailure: Error {
    case write
    case restart
}
