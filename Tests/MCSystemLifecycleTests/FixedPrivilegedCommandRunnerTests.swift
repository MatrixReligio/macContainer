import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("Fixed privileged command runner")
struct FixedPrivilegedCommandRunnerTests {
    @Test func `installer failures expose only a stable sanitized category`() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("mc-installer-diagnostic-\(UUID().uuidString).pkg")
        try Data("diagnostic-package".utf8).write(to: source, options: .withoutOverwriting)
        defer { try? FileManager.default.removeItem(at: source) }
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        let package = try OpenRuntimePackageFile(duplicating: handle.fileDescriptor)
        let invocation = FixedPrivilegedCommandInvocation(
            command: .installPackage,
            packageDescriptor: package.fileDescriptor,
            executable: "/bin/sh",
            arguments: ["/bin/sh", "-c", "echo 'installer: Must be run as root to install this package.' >&2; exit 1"],
            environment: [:],
            workingDirectory: "/"
        )

        #expect(throws: FixedPrivilegedCommandError.commandFailed(.installerRequiresRoot)) {
            try PosixSpawnFixedPrivilegedCommandRunner().run(
                invocation,
                standardInput: nil,
                package: package
            )
        }
    }

    @Test(arguments: [
        (FixedPrivilegedCommand.validateSystemPacketFilter, FixedPrivilegedCommandFailure.packetFilterValidation),
        (FixedPrivilegedCommand.reloadSystemPacketFilter, FixedPrivilegedCommandFailure.packetFilterReload),
        (FixedPrivilegedCommand.reloadDNS, FixedPrivilegedCommandFailure.dnsReload)
    ])
    func `system reload failures retain only their fixed command category`(
        command: FixedPrivilegedCommand,
        expected: FixedPrivilegedCommandFailure
    ) {
        let invocation = FixedPrivilegedCommandInvocation(
            command: command,
            packageDescriptor: nil,
            executable: "/bin/sh",
            arguments: ["/bin/sh", "-c", "exit 1"],
            environment: [:],
            workingDirectory: "/"
        )

        #expect(throws: FixedPrivilegedCommandError.commandFailed(expected)) {
            try PosixSpawnFixedPrivilegedCommandRunner().run(
                invocation,
                standardInput: nil,
                package: nil
            )
        }
    }

    @Test func `staged package is immutable to users and readable by the installer service`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mc-installer-permissions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.pkg")
        let expected = Data("reviewed-package-permissions".utf8)
        try expected.write(to: source, options: .withoutOverwriting)
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        let package = try OpenRuntimePackageFile(duplicating: handle.fileDescriptor)
        let stager = PrivatePackageStager(rootDirectory: root, requiredRootOwner: geteuid())

        try stager.withStagedPackage(package) { stagedPackage in
            let directoryAttributes = try FileManager.default.attributesOfItem(
                atPath: stagedPackage.deletingLastPathComponent().path
            )
            let packageAttributes = try FileManager.default.attributesOfItem(atPath: stagedPackage.path)

            #expect(directoryAttributes[.ownerAccountID] as? Int == Int(geteuid()))
            #expect(directoryAttributes[.posixPermissions] as? Int == 0o755)
            #expect(packageAttributes[.ownerAccountID] as? Int == Int(geteuid()))
            #expect(packageAttributes[.posixPermissions] as? Int == 0o644)
            #expect(try Data(contentsOf: stagedPackage) == expected)
        }

        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["source.pkg"])
    }

    @Test func `installer receives an immutable private path instead of a process descriptor`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mc-installer-stage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.pkg")
        try Data("immutable-reviewed-package".utf8).write(to: source, options: .withoutOverwriting)
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        let package = try OpenRuntimePackageFile(duplicating: handle.fileDescriptor)
        let runner = PosixSpawnFixedPrivilegedCommandRunner(
            packageStager: PrivatePackageStager(rootDirectory: root, requiredRootOwner: geteuid()),
            installerExecutable: "/bin/echo"
        )

        let output = try runner.run(.installPackage, package: package)
        let arguments = try #require(String(data: output, encoding: .utf8))
            .split(separator: " ")
            .map(String.init)
        let stagedPath = try #require(arguments.dropFirst().first)

        #expect(arguments.first == "-pkg")
        #expect(stagedPath.hasPrefix(root.path + "/container.matrixreligio.com.install."))
        #expect(!stagedPath.hasPrefix("/dev/fd/"))
        #expect(!FileManager.default.fileExists(atPath: stagedPath))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["source.pkg"])
    }

    @Test func `returns stdout without merging stderr diagnostics`() throws {
        let invocation = FixedPrivilegedCommandInvocation(
            command: .inspectContainerPacketFilter,
            packageDescriptor: nil,
            executable: "/bin/sh",
            arguments: ["/bin/sh", "-c", "printf 'rule-output'; printf 'diagnostic' >&2"],
            environment: [:],
            workingDirectory: "/"
        )

        let output = try PosixSpawnFixedPrivilegedCommandRunner().run(
            invocation,
            standardInput: nil,
            package: nil
        )

        #expect(try #require(String(data: output, encoding: .utf8)) == "rule-output")
    }
}
