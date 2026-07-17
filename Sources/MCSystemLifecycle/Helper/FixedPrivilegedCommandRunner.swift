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
    public init() {}

    @discardableResult
    public func run(_ command: FixedPrivilegedCommand, package: OpenRuntimePackageFile?) throws -> Data {
        try run(
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
        try check(posix_spawn_file_actions_adddup2(&actions, nullError, STDERR_FILENO))
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
            throw FixedPrivilegedCommandError.commandFailed
        }
        return output
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

public enum FixedPrivilegedCommandError: Error, Equatable, Sendable {
    case commandFailed
    case invalidPackageDescriptor
    case launchFailed(Int32)
    case outputTooLarge
}
