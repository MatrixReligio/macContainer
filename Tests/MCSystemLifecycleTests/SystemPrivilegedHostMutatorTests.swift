import CryptoKit
import Darwin
import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("System privileged host mutator")
struct SystemPrivilegedHostMutatorTests {
    @Test func `reviewed manifest is byte identified and structurally identical to config`() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent(
            "Config/compatibility/apple-container-1.1.0-package.json"
        ))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let decoded = try JSONDecoder().decode(RuntimePackageManifest.self, from: data)

        #expect(digest == ReviewedRuntime110Manifest.sourceSHA256)
        #expect(decoded == ReviewedRuntime110Manifest.package)
        #expect(decoded.payload.count == 27)
    }

    @Test func `removes only manifest payload and preserves shared and unrelated entries`() throws {
        let fixture = try HostMutationFixture()
        defer { fixture.cleanup() }
        let runner = HostRecordingCommandRunner()
        let host = fixture.makeHost(runner: runner)

        try host.removePayload(manifest: fixture.manifest)
        try host.removeKnownEmptyDirectories(manifest: fixture.manifest)

        #expect(!FileManager.default.fileExists(atPath: fixture.runtimeFile.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.pluginFile.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.containerDirectory.path))
        #expect(FileManager.default.fileExists(atPath: fixture.binDirectory.path))
        #expect(FileManager.default.fileExists(atPath: fixture.libexecDirectory.path))
        #expect(FileManager.default.fileExists(atPath: fixture.unrelatedFile.path))
    }

    @Test func `refuses hard linked manifest payload without deleting either link`() throws {
        let fixture = try HostMutationFixture()
        defer { fixture.cleanup() }
        let hardLink = fixture.root.appendingPathComponent("attacker-link")
        try FileManager.default.linkItem(at: fixture.runtimeFile, to: hardLink)
        let host = fixture.makeHost(runner: HostRecordingCommandRunner())

        #expect(throws: PathPolicyError.hardLink) {
            try host.removePayload(manifest: fixture.manifest)
        }
        #expect(FileManager.default.fileExists(atPath: fixture.runtimeFile.path))
        #expect(FileManager.default.fileExists(atPath: hardLink.path))
    }

    @Test func `atomically writes replaces and removes only namespaced resolver`() throws {
        let fixture = try HostMutationFixture()
        defer { fixture.cleanup() }
        let runner = HostRecordingCommandRunner()
        let host = fixture.makeHost(runner: runner)
        let resolver = fixture.resolverDirectory.appendingPathComponent("containerization.default")

        try host.writeResolver(.init(name: "default", nameservers: ["192.168.64.1", "1.1.1.1"]))
        #expect(try String(contentsOf: resolver, encoding: .utf8) == "nameserver 192.168.64.1\nnameserver 1.1.1.1\n")
        var status = stat()
        #expect(Darwin.lstat(resolver.path, &status) == 0)
        #expect(status.st_mode & 0o777 == 0o644)

        try host.writeResolver(.init(name: "default", nameservers: ["127.0.0.1"]))
        #expect(try String(contentsOf: resolver, encoding: .utf8) == "nameserver 127.0.0.1\n")
        try host.removeResolver(name: "default")
        #expect(!FileManager.default.fileExists(atPath: resolver.path))
        #expect(runner.commands == [.reloadDNS, .reloadDNS, .reloadDNS])
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.resolverDirectory.path).isEmpty)
    }

    @Test func `rejects resolver symlink and uses fixed receipt and packet filter commands`() throws {
        let fixture = try HostMutationFixture()
        defer { fixture.cleanup() }
        let runner = HostRecordingCommandRunner()
        let host = fixture.makeHost(runner: runner)
        let resolver = fixture.resolverDirectory.appendingPathComponent("containerization.default")
        try FileManager.default.createSymbolicLink(at: resolver, withDestinationURL: fixture.unrelatedFile)

        #expect(throws: SystemPrivilegedHostError.unsafeResolver) {
            try host.writeResolver(.init(name: "default", nameservers: ["127.0.0.1"]))
        }
        try host.forgetReceipt()
        try host.applyPacketFilter(.init(anchor: "com.apple.container", subnetCIDR: "192.168.64.0/24"))
        runner.output = Data("pass quick inet from <container_subnets> to any\n".utf8)
        #expect(try host.packetFilterRulesPresent())
        try host.removePacketFilter()

        #expect(runner.commands == [
            .forgetContainerReceipt,
            .reloadContainerPacketFilter(subnetCIDR: "192.168.64.0/24"),
            .inspectContainerPacketFilter,
            .clearContainerPacketFilter
        ])
        #expect(
            FixedPrivilegedCommand.reloadContainerPacketFilter(subnetCIDR: "192.168.64.0/24").standardInput ==
                Data(
                    (
                        "table <container_subnets> persist { 192.168.64.0/24 }\n" +
                            "pass quick inet from <container_subnets> to any\n"
                    ).utf8
                )
        )
    }

    @Test func `creates and deletes an Apple compatible DNS domain through fixed privileged actions`() throws {
        let fixture = try HostMutationFixture()
        defer { fixture.cleanup() }
        let runner = HostRecordingCommandRunner()
        let host = fixture.makeHost(runner: runner)
        let resolver = fixture.resolverDirectory.appendingPathComponent("containerization.dev.example")

        try host.createDNSDomain(.init(name: "dev.example", redirectIPv4: "192.0.2.10"))

        #expect(try String(contentsOf: resolver, encoding: .utf8) == """
        domain dev.example
        search dev.example
        nameserver 127.0.0.1
        port 1053
        options localhost:192.0.2.10
        """)
        #expect(try String(contentsOf: fixture.packetFilterAnchor, encoding: .utf8).contains(
            "rdr inet from any to 192.0.2.10 -> 127.0.0.1 # dev.example"
        ))
        let config = try String(contentsOf: fixture.packetFilterConfig, encoding: .utf8)
        #expect(config.contains(#"rdr-anchor "com.apple.container""#))
        #expect(config.contains(
            "load anchor \"com.apple.container\" from \"\(fixture.packetFilterAnchor.path)\""
        ))
        #expect(runner.commands == [.validateSystemPacketFilter, .reloadSystemPacketFilter, .reloadDNS])

        try host.deleteDNSDomain(name: "dev.example")

        #expect(!FileManager.default.fileExists(atPath: resolver.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.packetFilterAnchor.path))
        let restoredConfig = try String(contentsOf: fixture.packetFilterConfig, encoding: .utf8)
        #expect(!restoredConfig.contains("com.apple.container"))
        #expect(runner.commands == [
            .validateSystemPacketFilter, .reloadSystemPacketFilter, .reloadDNS,
            .validateSystemPacketFilter, .reloadSystemPacketFilter, .reloadDNS
        ])
    }

    @Test func `DNS creation restores resolver and packet filter files when validation fails`() throws {
        let fixture = try HostMutationFixture()
        defer { fixture.cleanup() }
        let runner = HostRecordingCommandRunner(failOn: .validateSystemPacketFilter)
        let host = fixture.makeHost(runner: runner)
        let resolver = fixture.resolverDirectory.appendingPathComponent("containerization.dev.example")
        let originalConfig = try Data(contentsOf: fixture.packetFilterConfig)

        #expect(throws: HostCommandFailure.rejected) {
            try host.createDNSDomain(.init(name: "dev.example", redirectIPv4: "192.0.2.10"))
        }

        #expect(!FileManager.default.fileExists(atPath: resolver.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.packetFilterAnchor.path))
        #expect(try Data(contentsOf: fixture.packetFilterConfig) == originalConfig)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.resolverDirectory.path).isEmpty)
    }

    @Test func `DNS creation refuses a packet filter anchor symlink without changing its target`() throws {
        let fixture = try HostMutationFixture()
        defer { fixture.cleanup() }
        try FileManager.default.createSymbolicLink(
            at: fixture.packetFilterAnchor,
            withDestinationURL: fixture.unrelatedFile
        )
        let host = fixture.makeHost(runner: HostRecordingCommandRunner())

        #expect(throws: SystemPrivilegedHostError.invalidManagedFile) {
            try host.createDNSDomain(.init(name: "dev.example", redirectIPv4: "192.0.2.10"))
        }

        #expect(try String(contentsOf: fixture.unrelatedFile, encoding: .utf8) == "unrelated")
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.resolverDirectory.path).isEmpty)
    }
}

private final class HostRecordingCommandRunner: FixedPrivilegedCommandRunning, @unchecked Sendable {
    private(set) var commands: [FixedPrivilegedCommand] = []
    var output = Data()
    private let failOn: FixedPrivilegedCommand?

    init(failOn: FixedPrivilegedCommand? = nil) {
        self.failOn = failOn
    }

    func run(_ command: FixedPrivilegedCommand, package _: OpenRuntimePackageFile?) throws -> Data {
        commands.append(command)
        if command == failOn {
            throw HostCommandFailure.rejected
        }
        return output
    }
}

private enum HostCommandFailure: Error {
    case rejected
}

private final class HostMutationFixture {
    let root: URL
    let binDirectory: URL
    let runtimeFile: URL
    let libexecDirectory: URL
    let containerDirectory: URL
    let pluginFile: URL
    let unrelatedFile: URL
    let resolverDirectory: URL
    let packetFilterConfig: URL
    let packetFilterAnchorsDirectory: URL
    let packetFilterAnchor: URL
    let manifest: RuntimePackageManifest

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainerHostMutationTests-\(UUID().uuidString)", isDirectory: true)
        binDirectory = root.appendingPathComponent("bin", isDirectory: true)
        runtimeFile = binDirectory.appendingPathComponent("runtime")
        libexecDirectory = root.appendingPathComponent("libexec", isDirectory: true)
        containerDirectory = libexecDirectory.appendingPathComponent("container", isDirectory: true)
        pluginFile = containerDirectory.appendingPathComponent("plugin")
        unrelatedFile = binDirectory.appendingPathComponent("unrelated")
        resolverDirectory = root.appendingPathComponent("resolver", isDirectory: true)
        packetFilterConfig = root.appendingPathComponent("pf.conf")
        packetFilterAnchorsDirectory = root.appendingPathComponent("pf.anchors", isDirectory: true)
        packetFilterAnchor = packetFilterAnchorsDirectory.appendingPathComponent("com.apple.container")
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: containerDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resolverDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packetFilterAnchorsDirectory, withIntermediateDirectories: true)
        try Data("set skip on lo0\n".utf8).write(to: packetFilterConfig)
        try Data("runtime".utf8).write(to: runtimeFile)
        try Data("plugin".utf8).write(to: pluginFile)
        try Data("unrelated".utf8).write(to: unrelatedFile)
        manifest = RuntimePackageManifest(
            runtimeVersion: "1.1.0",
            assetName: "runtime.pkg",
            sha256: String(repeating: "a", count: 64),
            installerTeamID: "UPBK2H6LZM",
            signerCommonName: "fixture",
            receiptIdentifier: "com.apple.container-installer",
            installLocation: "/usr/local",
            payload: [
                .init(relativePath: "bin", kind: .directory),
                .init(relativePath: "bin/runtime", kind: .file, sha256: String(repeating: "b", count: 64)),
                .init(relativePath: "libexec", kind: .directory),
                .init(relativePath: "libexec/container", kind: .directory),
                .init(
                    relativePath: "libexec/container/plugin",
                    kind: .file,
                    sha256: String(repeating: "c", count: 64)
                )
            ]
        )
    }

    func makeHost(runner: any FixedPrivilegedCommandRunning) -> SystemPrivilegedHostMutator {
        SystemPrivilegedHostMutator(
            manifest: manifest,
            commandRunner: runner,
            installRoot: root,
            resolverDirectory: resolverDirectory,
            packetFilterConfig: packetFilterConfig,
            packetFilterAnchorsDirectory: packetFilterAnchorsDirectory,
            requiredOwner: geteuid()
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
