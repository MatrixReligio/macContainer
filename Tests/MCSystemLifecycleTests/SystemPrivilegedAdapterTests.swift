import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("System privileged adapter")
struct SystemPrivilegedAdapterTests {
    @Test func `reverifies inherited descriptor and invokes only fixed installer`() throws {
        let package = try AdapterPackageFixture()
        defer { package.cleanup() }
        let verifier = RecordingPrivilegedPackageVerifier(openFile: package.openFile)
        let commands = RecordingFixedCommandRunner()
        let host = RecordingPrivilegedHostMutator()
        let adapter = SystemPrivilegedAdapter(
            manifest: .adapterFixture,
            manifestID: "apple-container-1.1.0",
            manifestSHA256: String(repeating: "f", count: 64),
            packageVerifier: verifier,
            commandRunner: commands,
            host: host
        )

        try adapter.installVerifiedPackage(
            package.handle,
            token: .init(runtimeVersion: "1.1.0", sha256: RuntimePackageManifest.adapterFixture.sha256)
        )

        #expect(verifier.verificationCount == 1)
        #expect(commands.invocations == [
            .init(
                command: .installPackage,
                packageDescriptor: package.openFile.fileDescriptor,
                executable: "/usr/sbin/installer",
                arguments: ["/usr/sbin/installer", "-pkg", "/dev/fd/198", "-target", "/"],
                environment: [:],
                workingDirectory: "/"
            )
        ])
    }

    @Test(arguments: [
        PackageInstallToken(runtimeVersion: "9.9.9", sha256: RuntimePackageManifest.adapterFixture.sha256),
        PackageInstallToken(runtimeVersion: "1.1.0", sha256: String(repeating: "0", count: 64))
    ])
    func `rejects token drift before verification or install`(_ token: PackageInstallToken) throws {
        let package = try AdapterPackageFixture()
        defer { package.cleanup() }
        let verifier = RecordingPrivilegedPackageVerifier(openFile: package.openFile)
        let commands = RecordingFixedCommandRunner()
        let adapter = SystemPrivilegedAdapter.fixture(verifier: verifier, commands: commands)

        #expect(throws: SystemPrivilegedAdapterError.packageTokenMismatch) {
            try adapter.installVerifiedPackage(package.handle, token: token)
        }
        #expect(verifier.verificationCount == 0)
        #expect(commands.invocations.isEmpty)
    }

    @Test func `delegates only validated noninstaller operations`() throws {
        let package = try AdapterPackageFixture()
        defer { package.cleanup() }
        let host = RecordingPrivilegedHostMutator()
        let adapter = SystemPrivilegedAdapter.fixture(
            verifier: RecordingPrivilegedPackageVerifier(openFile: package.openFile),
            commands: RecordingFixedCommandRunner(),
            host: host
        )
        let digest = String(repeating: "f", count: 64)

        try adapter.removePayload(.init(manifestID: "apple-container-1.1.0", manifestSHA256: digest))
        try adapter.forgetReceipt(identifier: "com.apple.container-installer")
        try adapter.writeResolver(.init(name: "default", nameservers: ["192.168.64.1"]))
        try adapter.removeResolver(name: "default")
        try adapter.applyPacketFilter(.init(anchor: "com.apple.container", subnetCIDR: "192.168.64.0/24"))
        try adapter.removePacketFilter(anchor: "com.apple.container")
        try adapter.removeKnownEmptyDirectories(manifestID: "apple-container-1.1.0")

        #expect(host.actions == [
            "removePayload", "forgetReceipt", "writeResolver", "removeResolver",
            "applyPacketFilter", "removePacketFilter", "removeKnownEmptyDirectories"
        ])
    }
}

private final class RecordingPrivilegedPackageVerifier: PrivilegedPackageVerifying, @unchecked Sendable {
    private let openFile: OpenRuntimePackageFile
    private(set) var verificationCount = 0

    init(openFile: OpenRuntimePackageFile) {
        self.openFile = openFile
    }

    func verify(_: FileHandle, against manifest: RuntimePackageManifest) throws -> PrivilegedVerifiedPackage {
        verificationCount += 1
        return PrivilegedVerifiedPackage(
            runtimeVersion: manifest.runtimeVersion,
            sha256: manifest.sha256,
            openFile: openFile
        )
    }
}

private final class RecordingFixedCommandRunner: FixedPrivilegedCommandRunning, @unchecked Sendable {
    private(set) var invocations: [FixedPrivilegedCommandInvocation] = []

    func run(_ command: FixedPrivilegedCommand, package: OpenRuntimePackageFile?) throws {
        invocations.append(.init(command: command, packageDescriptor: package?.fileDescriptor))
    }
}

private final class RecordingPrivilegedHostMutator: PrivilegedHostMutating, @unchecked Sendable {
    private(set) var actions: [String] = []

    func removePayload(manifest _: RuntimePackageManifest) throws {
        actions.append("removePayload")
    }

    func forgetReceipt() throws {
        actions.append("forgetReceipt")
    }

    func writeResolver(_: ResolverRequest) throws {
        actions.append("writeResolver")
    }

    func removeResolver(name _: String) throws {
        actions.append("removeResolver")
    }

    func applyPacketFilter(_: PacketFilterRequest) throws {
        actions.append("applyPacketFilter")
    }

    func removePacketFilter() throws {
        actions.append("removePacketFilter")
    }

    func removeKnownEmptyDirectories(manifest _: RuntimePackageManifest) throws {
        actions.append("removeKnownEmptyDirectories")
    }
}

private final class AdapterPackageFixture {
    let root: URL
    let url: URL
    let handle: FileHandle
    let openFile: OpenRuntimePackageFile

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainerAdapterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        url = root.appendingPathComponent("runtime.pkg")
        try Data("fixture".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        handle = try FileHandle(forReadingFrom: url)
        openFile = try OpenRuntimePackageFile(duplicating: handle.fileDescriptor)
    }

    func cleanup() {
        try? handle.close()
        try? FileManager.default.removeItem(at: root)
    }
}

private extension RuntimePackageManifest {
    static let adapterFixture = Self(
        runtimeVersion: "1.1.0",
        assetName: "container-1.1.0-installer-signed.pkg",
        sha256: "0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714",
        installerTeamID: "UPBK2H6LZM",
        signerCommonName: "Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)",
        receiptIdentifier: "com.apple.container-installer",
        installLocation: "/usr/local",
        payload: [.init(relativePath: "bin", kind: .directory)]
    )
}

private extension SystemPrivilegedAdapter {
    static func fixture(
        verifier: any PrivilegedPackageVerifying,
        commands: any FixedPrivilegedCommandRunning,
        host: any PrivilegedHostMutating = RecordingPrivilegedHostMutator()
    ) -> Self {
        Self(
            manifest: .adapterFixture,
            manifestID: "apple-container-1.1.0",
            manifestSHA256: String(repeating: "f", count: 64),
            packageVerifier: verifier,
            commandRunner: commands,
            host: host
        )
    }
}
