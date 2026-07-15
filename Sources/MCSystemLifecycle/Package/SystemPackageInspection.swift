import CryptoKit
import Darwin
import Foundation

public struct SystemPackageSignatureVerifier: PackageSignatureVerifying {
    public init() {}

    public func verifySignature(of file: OpenRuntimePackageFile) async throws -> PackageSignatureReport {
        let result: FixedPackageToolResult
        do {
            result = try FixedPackageToolRunner.run(.checkSignature, package: file)
        } catch {
            throw PackageTrustError.unsignedPackage
        }
        guard result.exitStatus == 0 else { throw PackageTrustError.unsignedPackage }
        guard let output = String(bytes: result.output, encoding: .utf8) else {
            throw PackageTrustError.unsignedPackage
        }
        guard
            output.contains("Status: signed by a developer certificate issued by Apple for distribution"),
            let certificateLine = output.split(separator: "\n").first(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("1. Developer ID Installer:")
            })
        else {
            throw PackageTrustError.unsignedPackage
        }

        let trimmed = certificateLine.trimmingCharacters(in: .whitespaces)
        let commonName = String(trimmed.dropFirst(3))
        guard
            let opening = commonName.lastIndex(of: "("),
            commonName.hasSuffix(")")
        else {
            throw PackageTrustError.unsignedPackage
        }
        let teamID = String(
            commonName[commonName.index(after: opening) ..< commonName.index(before: commonName.endIndex)]
        )
        return PackageSignatureReport(
            teamID: teamID,
            commonName: commonName,
            notarized: output.contains("Notarization: trusted by the Apple notary service")
        )
    }
}

public struct SystemRuntimePackageInspector: RuntimePackageInspecting {
    public init() {}

    public func inspect(_ file: OpenRuntimePackageFile) async throws -> RuntimePackageInspection {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainerPackageInspection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let stagedPackage = root.appendingPathComponent("reviewed.pkg", isDirectory: false)
        try Self.copyOpenPackage(file, to: stagedPackage)
        let expanded = root.appendingPathComponent("expanded", isDirectory: true)
        let result = try FixedPackageToolRunner.run(
            .expandFull(packagePath: stagedPackage.path, destination: expanded),
            package: file
        )
        guard result.exitStatus == 0 else { throw PackageInspectionError.expansionFailed }

        let metadata = try PackageInfoParser.parse(expanded.appendingPathComponent("PackageInfo"))
        let payloadRoot = expanded.appendingPathComponent("Payload", isDirectory: true)
        let payload = try Self.inspectPayload(root: payloadRoot)
        // PackageInfo counts the shared install root (`.`); the manifest intentionally
        // excludes `/usr/local` because MacContainer must never remove that shared directory.
        guard metadata.numberOfFiles == payload.count + 1 else {
            throw PackageInspectionError.payloadCountMismatch
        }
        return RuntimePackageInspection(
            runtimeVersion: metadata.version,
            receiptIdentifier: metadata.identifier,
            installLocation: metadata.installLocation,
            payload: payload
        )
    }

    private static func inspectPayload(root: URL) throws -> [PayloadEntry] {
        let root = root.resolvingSymlinksInPath()
        var rootStatus = stat()
        guard Darwin.lstat(root.path, &rootStatus) == 0, rootStatus.st_mode & S_IFMT == S_IFDIR else {
            throw PackageInspectionError.invalidPayload
        }

        var pending = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).map { ($0, $0.lastPathComponent) }
        var entries: [PayloadEntry] = []
        while let (url, relativePath) = pending.popLast() {
            var status = stat()
            guard Darwin.lstat(url.path, &status) == 0, status.st_uid == geteuid() else {
                throw PackageInspectionError.invalidPayload
            }
            switch status.st_mode & S_IFMT {
            case S_IFDIR:
                entries.append(PayloadEntry(relativePath: relativePath, kind: .directory))
                let children = try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil
                ).map { ($0, "\(relativePath)/\($0.lastPathComponent)") }
                pending.append(contentsOf: children)
            case S_IFREG:
                guard status.st_nlink == 1 else { throw PackageInspectionError.hardLink }
                try entries.append(PayloadEntry(
                    relativePath: relativePath,
                    kind: .file,
                    sha256: SHA256FileReader.digest(url)
                ))
            case S_IFLNK:
                try entries.append(PayloadEntry(
                    relativePath: relativePath,
                    kind: .symlink,
                    linkTarget: readLink(url)
                ))
            default:
                throw PackageInspectionError.invalidPayload
            }
        }
        return entries.sorted { $0.relativePath < $1.relativePath }
    }

    private static func copyOpenPackage(_ file: OpenRuntimePackageFile, to destination: URL) throws {
        let descriptor = Darwin.open(
            destination.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            0o600
        )
        guard descriptor >= 0 else { throw PackageInspectionError.invalidPayload }
        defer { Darwin.close(descriptor) }
        var offset: off_t = 0
        var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
        while true {
            let count = Darwin.pread(file.fileDescriptor, &buffer, buffer.count, offset)
            guard count >= 0 else {
                if errno == EINTR {
                    continue
                }
                throw PackageInspectionError.invalidPayload
            }
            guard count > 0 else { break }
            try writeAll(buffer.prefix(count), to: descriptor)
            offset += off_t(count)
        }
        guard Darwin.fsync(descriptor) == 0 else { throw PackageInspectionError.invalidPayload }
    }

    private static func writeAll(_ bytes: ArraySlice<UInt8>, to descriptor: Int32) throws {
        try bytes.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, baseAddress.advanced(by: offset), buffer.count - offset)
                guard count >= 0 else {
                    if errno == EINTR {
                        continue
                    }
                    throw PackageInspectionError.invalidPayload
                }
                offset += count
            }
        }
    }

    private static func readLink(_ url: URL) throws -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        let count = Darwin.readlink(url.path, &buffer, buffer.count)
        guard count > 0, count < buffer.count else {
            throw PackageInspectionError.invalidPayload
        }
        guard let target = String(bytes: buffer.prefix(count).map { UInt8(bitPattern: $0) }, encoding: .utf8) else {
            throw PackageInspectionError.invalidPayload
        }
        return target
    }
}

public extension RuntimePackageVerifier {
    static var system: Self {
        Self(
            digester: SHA256RuntimePackageDigester(),
            signature: SystemPackageSignatureVerifier(),
            inspector: SystemRuntimePackageInspector()
        )
    }
}

public enum PackageInspectionError: Error, Equatable, Sendable {
    case expansionFailed
    case hardLink
    case invalidMetadata
    case invalidPayload
    case outputTooLarge
    case payloadCountMismatch
    case toolLaunchFailed(Int32)
}

private struct PackageInfoMetadata {
    let identifier: String
    let version: String
    let installLocation: String
    let numberOfFiles: Int
}

private final class PackageInfoParser: NSObject, XMLParserDelegate {
    private var metadata: PackageInfoMetadata?

    static func parse(_ url: URL) throws -> PackageInfoMetadata {
        var status = stat()
        guard Darwin.lstat(url.path, &status) == 0, status.st_mode & S_IFMT == S_IFREG, status.st_nlink == 1 else {
            throw PackageInspectionError.invalidMetadata
        }
        let delegate = PackageInfoParser()
        let parser = try XMLParser(data: Data(contentsOf: url, options: [.mappedIfSafe]))
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), let metadata = delegate.metadata else {
            throw PackageInspectionError.invalidMetadata
        }
        return metadata
    }

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "pkg-info":
            parsePackageInfo(attributeDict)
        case "payload":
            parsePayload(attributeDict)
        default:
            break
        }
    }

    private func parsePackageInfo(_ attributes: [String: String]) {
        guard
            let identifier = attributes["identifier"],
            let version = attributes["version"],
            let installLocation = attributes["install-location"]
        else {
            return
        }
        metadata = PackageInfoMetadata(
            identifier: identifier,
            version: version,
            installLocation: installLocation,
            numberOfFiles: -1
        )
    }

    private func parsePayload(_ attributes: [String: String]) {
        guard let count = attributes["numberOfFiles"].flatMap(Int.init), let current = metadata else {
            return
        }
        metadata = PackageInfoMetadata(
            identifier: current.identifier,
            version: current.version,
            installLocation: current.installLocation,
            numberOfFiles: count
        )
    }

    func parser(
        _ parser: XMLParser,
        resolveExternalEntityName _: String,
        systemID _: String?
    ) -> Data? {
        parser.abortParsing()
        return nil
    }
}

private enum FixedPackageToolCommand {
    case checkSignature
    case expandFull(packagePath: String, destination: URL)

    var arguments: [String] {
        switch self {
        case .checkSignature:
            ["--check-signature", "/dev/fd/198"]
        case let .expandFull(packagePath, destination):
            ["--expand-full", packagePath, destination.path]
        }
    }
}

private struct FixedPackageToolResult {
    let exitStatus: Int32
    let output: Data
}

private enum FixedPackageToolRunner {
    static func run(
        _ command: FixedPackageToolCommand,
        package: OpenRuntimePackageFile
    ) throws -> FixedPackageToolResult {
        var outputPipe = [Int32](repeating: -1, count: 2)
        guard Darwin.pipe(&outputPipe) == 0 else { throw posixError() }
        defer {
            closeIfOpen(outputPipe[0])
            closeIfOpen(outputPipe[1])
        }

        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw posixError() }
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, package.fileDescriptor, 198)
        posix_spawn_file_actions_adddup2(&actions, outputPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, outputPipe[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, outputPipe[0])
        posix_spawn_file_actions_addclose(&actions, outputPipe[1])

        let executable = "/usr/sbin/pkgutil"
        let arguments = [executable] + command.arguments
        var duplicated = arguments.map { strdup($0) }
        duplicated.append(nil)
        defer { duplicated.compactMap(\.self).forEach { free($0) } }
        var environment: [UnsafeMutablePointer<CChar>?] = [nil]
        var processID = pid_t()
        let launchStatus = executable.withCString { executablePointer in
            duplicated.withUnsafeMutableBufferPointer { argumentsPointer in
                environment.withUnsafeMutableBufferPointer { environmentPointer in
                    posix_spawn(
                        &processID,
                        executablePointer,
                        &actions,
                        nil,
                        argumentsPointer.baseAddress,
                        environmentPointer.baseAddress
                    )
                }
            }
        }
        guard launchStatus == 0 else { throw PackageInspectionError.toolLaunchFailed(launchStatus) }
        Darwin.close(outputPipe[1])
        outputPipe[1] = -1

        let output = try readOutput(outputPipe[0])
        let status = try waitForExit(processID)
        let exitedNormally = status & 0x7F == 0
        let exitStatus = exitedNormally ? (status >> 8) & 0xFF : -1
        return FixedPackageToolResult(exitStatus: exitStatus, output: output)
    }

    private static func closeIfOpen(_ descriptor: Int32) {
        if descriptor >= 0 {
            Darwin.close(descriptor)
        }
    }

    private static func readOutput(_ descriptor: Int32) throws -> Data {
        var output = Data()
        var exceededLimit = false
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
            if output.count + count <= 1024 * 1024 {
                output.append(buffer, count: count)
            } else {
                exceededLimit = true
            }
        }
        guard !exceededLimit else { throw PackageInspectionError.outputTooLarge }
        return output
    }

    private static func waitForExit(_ processID: pid_t) throws -> Int32 {
        var status: Int32 = 0
        while Darwin.waitpid(processID, &status, 0) < 0 {
            guard errno == EINTR else { throw posixError() }
        }
        return status
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}

private enum SHA256FileReader {
    static func digest(_ url: URL) throws -> String {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw PackageInspectionError.invalidPayload }
        defer { Darwin.close(descriptor) }
        var status = stat()
        guard
            Darwin.fstat(descriptor, &status) == 0,
            status.st_mode & S_IFMT == S_IFREG,
            status.st_nlink == 1
        else {
            throw PackageInspectionError.invalidPayload
        }

        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else {
                if errno == EINTR {
                    continue
                }
                throw PackageInspectionError.invalidPayload
            }
            guard count > 0 else { break }
            hasher.update(data: Data(buffer.prefix(count)))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
