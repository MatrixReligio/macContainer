import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("Physical machine baseline")
struct MachineBaselineTests {
    @Test func `canonical comparison ignores only capture time and process identifiers`() {
        let first = MachineBaseline.fixture(
            capturedAt: Date(timeIntervalSince1970: 1),
            serviceProcessID: 101,
            runtimeProcessID: 201
        )
        let second = MachineBaseline.fixture(
            capturedAt: Date(timeIntervalSince1970: 2),
            serviceProcessID: 102,
            runtimeProcessID: 202
        )

        #expect(first.canonicalForComparison == second.canonicalForComparison)

        let changed = MachineBaseline.fixture(
            capturedAt: Date(timeIntervalSince1970: 2),
            serviceProcessID: 102,
            runtimeProcessID: 202,
            processSHA256: String(repeating: "b", count: 64)
        )
        #expect(first.canonicalForComparison != changed.canonicalForComparison)
    }

    @Test(arguments: ExistingRuntimeStateFixture.all)
    func `destructive preflight refuses every existing user state without mutation`(
        fixture: ExistingRuntimeStateFixture
    ) async throws {
        let environment = RecordingPhysicalPreflightEnvironment(baseline: fixture.baseline)
        let result = try await PhysicalPreflight(environment: environment).run()

        #expect(result.permission == .refusedExistingState)
        #expect(!result.refusalReasons.isEmpty)
        #expect(await environment.mutationCount == 0)
    }

    @Test func `destructive preflight permits an empty verified baseline`() async throws {
        let environment = RecordingPhysicalPreflightEnvironment(baseline: .emptyFixture)
        let result = try await PhysicalPreflight(environment: environment).run()

        #expect(result.permission == .safeToTest)
        #expect(result.refusalReasons.isEmpty)
        #expect(await environment.mutationCount == 0)
    }

    @Test func `empty defaults export is not existing runtime state`() throws {
        let empty = Data("<?xml version=\"1.0\"?><plist version=\"1.0\"><dict/></plist>".utf8)
        let populated = Data(
            "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>enabled</key><true/></dict></plist>".utf8
        )

        #expect(try DefaultsSnapshot.exported(domain: "fixture", data: empty) == nil)
        #expect(try DefaultsSnapshot.exported(domain: "fixture", data: populated) != nil)
    }
}

private actor RecordingPhysicalPreflightEnvironment: PhysicalPreflightEnvironment {
    let baseline: MachineBaseline
    private(set) var mutationCount = 0

    init(baseline: MachineBaseline) {
        self.baseline = baseline
    }

    func captureBaseline() async throws -> MachineBaseline {
        baseline
    }
}

struct ExistingRuntimeStateFixture: CustomTestStringConvertible, Sendable {
    let name: String
    let baseline: MachineBaseline

    var testDescription: String {
        name
    }

    static let all: [Self] = [
        .init(name: "receipt", baseline: .emptyFixture.withReceipt),
        .init(name: "payload", baseline: .emptyFixture.withPayload),
        .init(name: "launch service", baseline: .emptyFixture.withLaunchService),
        .init(name: "runtime process", baseline: .emptyFixture.withRuntimeProcess),
        .init(name: "runtime path", baseline: .emptyFixture.withRuntimePath),
        .init(name: "defaults", baseline: .emptyFixture.withDefaults),
        .init(name: "keychain", baseline: .emptyFixture.withKeychainItem),
        .init(name: "resolver", baseline: .emptyFixture.withResolver),
        .init(name: "packet filter", baseline: .emptyFixture.withPacketFilterRule),
        .init(name: "test cache", baseline: .emptyFixture.withTestCache)
    ]
}

private extension MachineBaseline {
    static var emptyFixture: Self {
        Self(
            hostHardware: .init(
                model: "MacFixture",
                architecture: "arm64",
                hardwareUUIDSHA256: String(repeating: "a", count: 64)
            ),
            macOSVersion: "26.0",
            packageReceipt: nil,
            usrLocalPayload: [],
            launchServices: [],
            runtimeProcesses: [],
            runtimePaths: [],
            defaults: nil,
            keychainItems: [],
            resolvers: [],
            packetFilter: .init(anchor: "com.apple.container", normalizedRules: [], verified: true),
            testCaches: [],
            capturedAt: Date(timeIntervalSince1970: 0)
        )
    }

    static func fixture(
        capturedAt: Date,
        serviceProcessID: Int32,
        runtimeProcessID: Int32,
        processSHA256: String = String(repeating: "a", count: 64)
    ) -> Self {
        Self(
            hostHardware: emptyFixture.hostHardware,
            macOSVersion: emptyFixture.macOSVersion,
            packageReceipt: nil,
            usrLocalPayload: [],
            launchServices: [
                .init(
                    label: "com.apple.container.apiserver",
                    state: "loaded",
                    executablePath: "/usr/local/bin/container-apiserver",
                    executableSHA256: processSHA256,
                    teamID: "UPBK2H6LZM",
                    processID: serviceProcessID
                )
            ],
            runtimeProcesses: [
                .init(
                    executablePath: "/usr/local/bin/container-apiserver",
                    executableSHA256: processSHA256,
                    teamID: "UPBK2H6LZM",
                    processID: runtimeProcessID
                )
            ],
            runtimePaths: [],
            defaults: nil,
            keychainItems: [],
            resolvers: [],
            packetFilter: emptyFixture.packetFilter,
            testCaches: [],
            capturedAt: capturedAt
        )
    }

    var withReceipt: Self {
        replacing(packageReceipt: .init(
            identifier: "com.apple.container-installer",
            version: "1.1.0",
            installLocation: "/usr/local"
        ))
    }

    var withPayload: Self {
        replacing(usrLocalPayload: [Self.sampleFile])
    }

    var withLaunchService: Self {
        replacing(launchServices: [.init(label: "com.apple.container.apiserver", state: "loaded")])
    }

    var withRuntimeProcess: Self {
        replacing(runtimeProcesses: [
            .init(
                executablePath: "/usr/local/bin/container",
                executableSHA256: String(repeating: "a", count: 64),
                teamID: "UPBK2H6LZM",
                processID: 42
            )
        ])
    }

    var withRuntimePath: Self {
        replacing(runtimePaths: [.init(root: "/fixture/runtime", entries: [Self.sampleFile])])
    }

    var withDefaults: Self {
        replacing(defaults: .init(domain: "com.apple.container.defaults", byteCount: 1, sha256: "a"))
    }

    var withKeychainItem: Self {
        replacing(keychainItems: [.init(service: "com.apple.container.registry", metadataSHA256: "a")])
    }

    var withResolver: Self {
        replacing(resolvers: [Self.sampleFile])
    }

    var withPacketFilterRule: Self {
        replacing(packetFilter: .init(
            anchor: "com.apple.container",
            normalizedRules: ["pass on bridge100"],
            verified: true
        ))
    }

    var withTestCache: Self {
        replacing(testCaches: [.init(root: "/fixture/test-cache", entries: [Self.sampleFile])])
    }

    private static var sampleFile: FileSnapshot {
        .init(
            path: "/fixture/file",
            kind: .file,
            mode: 0o600,
            ownerID: 501,
            groupID: 20,
            size: 1,
            sha256: String(repeating: "a", count: 64)
        )
    }

    private func replacing(
        packageReceipt: ReceiptSnapshot? = nil,
        usrLocalPayload: [FileSnapshot] = [],
        launchServices: [LaunchServiceSnapshot] = [],
        runtimeProcesses: [ProcessSnapshot] = [],
        runtimePaths: [PathSnapshot] = [],
        defaults: DefaultsSnapshot? = nil,
        keychainItems: [KeychainMetadataSnapshot] = [],
        resolvers: [FileSnapshot] = [],
        packetFilter: PacketFilterSnapshot? = nil,
        testCaches: [PathSnapshot] = []
    ) -> Self {
        Self(
            schemaVersion: schemaVersion,
            hostHardware: hostHardware,
            macOSVersion: macOSVersion,
            packageReceipt: packageReceipt,
            usrLocalPayload: usrLocalPayload,
            launchServices: launchServices,
            runtimeProcesses: runtimeProcesses,
            runtimePaths: runtimePaths,
            defaults: defaults,
            keychainItems: keychainItems,
            resolvers: resolvers,
            packetFilter: packetFilter ?? self.packetFilter,
            testCaches: testCaches,
            verificationErrors: verificationErrors,
            capturedAt: capturedAt
        )
    }
}
