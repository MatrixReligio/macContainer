import Darwin
import Foundation

public enum FixedPrivilegedCommand: Equatable, Sendable {
    case installPackage
    case forgetContainerReceipt
    case reloadContainerPacketFilter(subnetCIDR: String)
    case clearContainerPacketFilter
    case inspectContainerPacketFilter
    case validateSystemPacketFilter
    case reloadSystemPacketFilter
    case reloadDNS

    public var executable: String {
        switch self {
        case .installPackage:
            "/usr/sbin/installer"
        case .forgetContainerReceipt:
            "/usr/sbin/pkgutil"
        case .reloadContainerPacketFilter, .clearContainerPacketFilter, .inspectContainerPacketFilter,
             .validateSystemPacketFilter, .reloadSystemPacketFilter:
            "/sbin/pfctl"
        case .reloadDNS:
            "/usr/bin/killall"
        }
    }

    public var arguments: [String] {
        switch self {
        case .installPackage:
            [executable, "-pkg", "/dev/fd/198", "-target", "/"]
        case .forgetContainerReceipt:
            [executable, "--forget", "com.apple.container-installer"]
        case .reloadContainerPacketFilter:
            [executable, "-a", "com.apple.container", "-f", "-"]
        case .clearContainerPacketFilter:
            [executable, "-a", "com.apple.container", "-F", "all"]
        case .inspectContainerPacketFilter:
            [executable, "-a", "com.apple.container", "-sr"]
        case .validateSystemPacketFilter:
            [executable, "-n", "-f", "/etc/pf.conf"]
        case .reloadSystemPacketFilter:
            [executable, "-f", "/etc/pf.conf"]
        case .reloadDNS:
            [executable, "-HUP", "mDNSResponder"]
        }
    }

    public var standardInput: Data? {
        switch self {
        case let .reloadContainerPacketFilter(subnetCIDR):
            let rules = "table <container_subnets> persist { \(subnetCIDR) }\n" +
                "pass quick inet from <container_subnets> to any\n"
            return Data(rules.utf8)
        default:
            return nil
        }
    }

    public var requiresPackageDescriptor: Bool {
        self == .installPackage
    }
}

public struct FixedPrivilegedCommandInvocation: Equatable, Sendable {
    public let command: FixedPrivilegedCommand
    public let packageDescriptor: Int32?
    public let executable: String
    public let arguments: [String]
    public let environment: [String: String]
    public let workingDirectory: String

    public init(command: FixedPrivilegedCommand, packageDescriptor: Int32?) {
        self.command = command
        self.packageDescriptor = packageDescriptor
        executable = command.executable
        arguments = command.arguments
        environment = [:]
        workingDirectory = "/"
    }

    public init(
        command: FixedPrivilegedCommand,
        packageDescriptor: Int32?,
        executable: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String
    ) {
        self.command = command
        self.packageDescriptor = packageDescriptor
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }
}

public protocol FixedPrivilegedCommandRunning: Sendable {
    @discardableResult
    func run(_ command: FixedPrivilegedCommand, package: OpenRuntimePackageFile?) throws -> Data
}

public struct PosixSpawnFixedPrivilegedCommandRunner: FixedPrivilegedCommandRunning {
    private let packageStager: PrivatePackageStager
    private let installerExecutable: String

    public init() {
        packageStager = PrivatePackageStager(
            rootDirectory: URL(fileURLWithPath: "/private/var/tmp", isDirectory: true),
            requiredRootOwner: 0
        )
        installerExecutable = "/usr/sbin/installer"
    }

    init(packageStager: PrivatePackageStager, installerExecutable: String) {
        self.packageStager = packageStager
        self.installerExecutable = installerExecutable
    }

    @discardableResult
    public func run(_ command: FixedPrivilegedCommand, package: OpenRuntimePackageFile?) throws -> Data {
        if command == .installPackage {
            guard let package else { throw FixedPrivilegedCommandError.invalidPackageDescriptor }
            return try packageStager.withStagedPackage(package) { stagedPackage in
                try run(
                    FixedPrivilegedCommandInvocation(
                        command: command,
                        packageDescriptor: package.fileDescriptor,
                        executable: installerExecutable,
                        arguments: [installerExecutable, "-pkg", stagedPackage.path, "-target", "/"],
                        environment: [:],
                        workingDirectory: "/"
                    ),
                    standardInput: nil,
                    package: package
                )
            }
        }
        return try run(
            FixedPrivilegedCommandInvocation(
                command: command,
                packageDescriptor: package?.fileDescriptor
            ),
            standardInput: command.standardInput,
            package: package
        )
    }

    @discardableResult
    func run(
        _ invocation: FixedPrivilegedCommandInvocation,
        standardInput input: Data?,
        package: OpenRuntimePackageFile?
    ) throws -> Data {
        let command = invocation.command
        guard command.requiresPackageDescriptor == (package != nil),
              invocation.packageDescriptor == package?.fileDescriptor
        else {
            throw FixedPrivilegedCommandError.invalidPackageDescriptor
        }
        try package?.revalidateIdentity()

        var outputPipe = [Int32](repeating: -1, count: 2)
        guard Darwin.pipe(&outputPipe) == 0 else { throw posixError() }
        defer { outputPipe.forEach(closeIfOpen) }

        var (inputPipe, nullInput) = try makeInputSource(hasData: input != nil)
        defer {
            inputPipe.forEach(closeIfOpen)
            closeIfOpen(nullInput)
        }
        let nullError = Darwin.open("/dev/null", O_WRONLY | O_CLOEXEC)
        guard nullError >= 0 else { throw posixError() }
        defer { closeIfOpen(nullError) }

        var actions: posix_spawn_file_actions_t?
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try invocation.workingDirectory.withCString {
            try check(posix_spawn_file_actions_addchdir(&actions, $0))
        }
        try check(posix_spawn_file_actions_adddup2(&actions, outputPipe[1], STDOUT_FILENO))
        if command == .installPackage {
            try check(posix_spawn_file_actions_adddup2(&actions, outputPipe[1], STDERR_FILENO))
        } else {
            try check(posix_spawn_file_actions_adddup2(&actions, nullError, STDERR_FILENO))
        }
        try check(posix_spawn_file_actions_addclose(&actions, outputPipe[0]))
        if let package {
            try check(posix_spawn_file_actions_adddup2(&actions, package.fileDescriptor, 198))
        }
        if input != nil {
            try check(posix_spawn_file_actions_adddup2(&actions, inputPipe[0], STDIN_FILENO))
            try check(posix_spawn_file_actions_addclose(&actions, inputPipe[1]))
        } else {
            try check(posix_spawn_file_actions_adddup2(&actions, nullInput, STDIN_FILENO))
        }

        var arguments = invocation.arguments.map { strdup($0) }
        arguments.append(nil)
        defer { arguments.compactMap(\.self).forEach { free($0) } }
        var environment = invocation.environment
            .sorted { $0.key < $1.key }
            .map { strdup("\($0.key)=\($0.value)") as UnsafeMutablePointer<CChar>? }
        environment.append(nil)
        defer { environment.compactMap(\.self).forEach { free($0) } }
        var processID = pid_t()
        let launchStatus = invocation.executable.withCString { executable in
            arguments.withUnsafeMutableBufferPointer { arguments in
                environment.withUnsafeMutableBufferPointer { environment in
                    posix_spawn(
                        &processID,
                        executable,
                        &actions,
                        nil,
                        arguments.baseAddress,
                        environment.baseAddress
                    )
                }
            }
        }
        guard launchStatus == 0 else { throw FixedPrivilegedCommandError.launchFailed(launchStatus) }
        var childWasReaped = false
        defer {
            if !childWasReaped {
                _ = try? waitForExit(processID)
            }
        }

        Darwin.close(outputPipe[1])
        outputPipe[1] = -1
        if let input {
            Darwin.close(inputPipe[0])
            inputPipe[0] = -1
            try writeAll(input, to: inputPipe[1])
            Darwin.close(inputPipe[1])
            inputPipe[1] = -1
        }
        let output = try readBoundedOutput(outputPipe[0])
        let status = try waitForExit(processID)
        childWasReaped = true
        guard status & 0x7F == 0, (status >> 8) & 0xFF == 0 else {
            throw FixedPrivilegedCommandError.commandFailed(
                Self.failureCategory(command: command, diagnostic: output)
            )
        }
        return output
    }

    private static func failureCategory(
        command: FixedPrivilegedCommand,
        diagnostic: Data
    ) -> FixedPrivilegedCommandFailure {
        guard command == .installPackage,
              let message = String(data: diagnostic, encoding: .utf8)?.lowercased()
        else {
            return .unspecified
        }
        if message.contains("must be run as root") {
            return .installerRequiresRoot
        }
        if message.contains("package path specified was invalid") {
            return .installerInvalidPackagePath
        }
        let incompatibleHost = message.contains("cannot be installed on this computer") ||
            message.contains("does not meet the requirements")
        if incompatibleHost {
            return .installerIncompatibleHost
        }
        let unavailableVolume = message.contains("could not find the specified volume") ||
            message.contains("error trying to locate volume")
        if unavailableVolume {
            return .installerUnavailableVolume
        }
        if message.contains("installer:") {
            return .installerRejected
        }
        return .unspecified
    }

    private func makeInputSource(hasData: Bool) throws -> ([Int32], Int32) {
        var inputPipe = [Int32](repeating: -1, count: 2)
        if hasData {
            guard Darwin.pipe(&inputPipe) == 0 else { throw posixError() }
            return (inputPipe, -1)
        }
        let nullInput = Darwin.open("/dev/null", O_RDONLY | O_CLOEXEC)
        guard nullInput >= 0 else { throw posixError() }
        return (inputPipe, nullInput)
    }

    private func check(_ status: Int32) throws {
        guard status == 0 else { throw FixedPrivilegedCommandError.launchFailed(status) }
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, baseAddress.advanced(by: offset), bytes.count - offset)
                guard count >= 0 else {
                    if errno == EINTR {
                        continue
                    }
                    throw posixError()
                }
                offset += count
            }
        }
    }

    private func readBoundedOutput(_ descriptor: Int32) throws -> Data {
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else {
                if errno == EINTR {
                    continue
                }
                throw posixError()
            }
            guard count > 0 else { break }
            guard output.count + count <= 1024 * 1024 else {
                throw FixedPrivilegedCommandError.outputTooLarge
            }
            output.append(buffer, count: count)
        }
        return output
    }

    private func waitForExit(_ processID: pid_t) throws -> Int32 {
        var status: Int32 = 0
        while Darwin.waitpid(processID, &status, 0) < 0 {
            guard errno == EINTR else { throw posixError() }
        }
        return status
    }

    private func closeIfOpen(_ descriptor: Int32) {
        if descriptor >= 0 {
            Darwin.close(descriptor)
        }
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}

struct PrivatePackageStager: Sendable {
    private let rootDirectory: URL
    private let requiredRootOwner: uid_t

    init(rootDirectory: URL, requiredRootOwner: uid_t) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.requiredRootOwner = requiredRootOwner
    }

    func withStagedPackage<T>(
        _ package: OpenRuntimePackageFile,
        operation: (URL) throws -> T
    ) throws -> T {
        try validateRoot()
        try package.revalidateIdentity()
        var template = Array(
            rootDirectory
                .appendingPathComponent("container.matrixreligio.com.install.XXXXXX", isDirectory: true)
                .path.utf8CString
        )
        guard let created = template.withUnsafeMutableBufferPointer({ pointer in
            Darwin.mkdtemp(pointer.baseAddress)
        }) else {
            throw FixedPrivilegedCommandError.packageStagingFailed
        }
        let directory = URL(fileURLWithPath: String(cString: created), isDirectory: true)
        let stagedPackage = directory.appendingPathComponent("reviewed.pkg", isDirectory: false)
        var requiresBestEffortCleanup = true
        defer {
            if requiresBestEffortCleanup {
                _ = Darwin.unlink(stagedPackage.path)
                _ = Darwin.rmdir(directory.path)
            }
        }
        guard Darwin.chmod(directory.path, 0o700) == 0 else {
            throw FixedPrivilegedCommandError.packageStagingFailed
        }
        let output = Darwin.open(
            stagedPackage.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            0o600
        )
        guard output >= 0 else { throw FixedPrivilegedCommandError.packageStagingFailed }
        do {
            try copy(package: package, to: output)
            guard Darwin.fsync(output) == 0 else {
                throw FixedPrivilegedCommandError.packageStagingFailed
            }
            guard Darwin.fchmod(output, 0o644) == 0 else {
                throw FixedPrivilegedCommandError.packageStagingFailed
            }
        } catch {
            Darwin.close(output)
            throw error
        }
        Darwin.close(output)
        try package.revalidateIdentity()
        guard Darwin.chmod(directory.path, 0o755) == 0 else {
            throw FixedPrivilegedCommandError.packageStagingFailed
        }
        let result = Result { try operation(stagedPackage) }
        guard Darwin.unlink(stagedPackage.path) == 0,
              Darwin.rmdir(directory.path) == 0
        else {
            throw FixedPrivilegedCommandError.packageStagingCleanupFailed
        }
        requiresBestEffortCleanup = false
        return try result.get()
    }

    private func validateRoot() throws {
        var status = stat()
        guard geteuid() == requiredRootOwner,
              rootDirectory.path.hasPrefix("/"),
              Darwin.lstat(rootDirectory.path, &status) == 0,
              status.st_mode & S_IFMT == S_IFDIR,
              status.st_uid == requiredRootOwner
        else {
            throw FixedPrivilegedCommandError.unsafePackageStagingRoot
        }
        let permissions = status.st_mode & 0o7777
        guard
            permissions & 0o077 == 0 ||
            (requiredRootOwner == 0 && permissions & mode_t(S_ISVTX) != 0)
        else {
            throw FixedPrivilegedCommandError.unsafePackageStagingRoot
        }
    }

    private func copy(package: OpenRuntimePackageFile, to output: Int32) throws {
        var offset: off_t = 0
        var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
        while true {
            let count = Darwin.pread(package.fileDescriptor, &buffer, buffer.count, offset)
            guard count >= 0 else {
                if errno == EINTR {
                    continue
                }
                throw FixedPrivilegedCommandError.packageStagingFailed
            }
            guard count > 0 else { break }
            try writeAll(buffer.prefix(count), to: output)
            offset += off_t(count)
        }
    }

    private func writeAll(_ bytes: ArraySlice<UInt8>, to output: Int32) throws {
        try bytes.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(output, baseAddress.advanced(by: offset), buffer.count - offset)
                guard count >= 0 else {
                    if errno == EINTR {
                        continue
                    }
                    throw FixedPrivilegedCommandError.packageStagingFailed
                }
                offset += count
            }
        }
    }
}

public enum FixedPrivilegedCommandFailure: Equatable, Sendable {
    case installerIncompatibleHost
    case installerInvalidPackagePath
    case installerRejected
    case installerRequiresRoot
    case installerUnavailableVolume
    case unspecified
}

public enum FixedPrivilegedCommandError: Error, Equatable, Sendable {
    case commandFailed(FixedPrivilegedCommandFailure)
    case invalidPackageDescriptor
    case launchFailed(Int32)
    case outputTooLarge
    case packageStagingCleanupFailed
    case packageStagingFailed
    case unsafePackageStagingRoot

    var sanitizedCode: Int {
        switch self {
        case .commandFailed(.installerInvalidPackagePath): 20
        case .commandFailed(.installerRequiresRoot): 21
        case .commandFailed(.installerIncompatibleHost): 22
        case .commandFailed(.installerUnavailableVolume): 23
        case .commandFailed(.installerRejected): 24
        case .commandFailed(.unspecified): 25
        case .invalidPackageDescriptor: 26
        case .launchFailed: 27
        case .outputTooLarge: 28
        case .packageStagingCleanupFailed: 29
        case .packageStagingFailed: 30
        case .unsafePackageStagingRoot: 31
        }
    }
}
