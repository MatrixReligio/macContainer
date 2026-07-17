import Darwin
import Foundation
import MCSystemLifecycle

public protocol PacketFilterAuditing: Sendable {
    func hasRules(anchor: String) async throws -> Bool
}

extension HelperClient: PacketFilterAuditing {}

public struct PhysicalPacketFilterAuditResult: Codable, Equatable, Sendable {
    public let verified: Bool
    public let residuePresent: Bool

    public init(verified: Bool, residuePresent: Bool) {
        self.verified = verified
        self.residuePresent = residuePresent
    }
}

public struct PhysicalHelperBootstrapResult: Codable, Equatable, Sendable {
    public let status: String
    public let errorDomain: String?
    public let errorCode: Int?

    public init(status: String, errorDomain: String? = nil, errorCode: Int? = nil) {
        self.status = status
        self.errorDomain = errorDomain
        self.errorCode = errorCode
    }
}

public struct PhysicalHelperBootstrapCommand: Sendable {
    private enum Operation: Sendable {
        case register
        case unregister
    }

    private struct Specification {
        let operation: Operation
        let argumentPrefix: String
        let filenamePrefix: String
    }

    private let outputURL: URL
    private let operation: Operation
    private let registrar: any PrivilegedHelperRegistering

    public init?(
        arguments: [String],
        environment: [String: String],
        registrar: any PrivilegedHelperRegistering = PrivilegedHelperRegistrar()
    ) {
        let specifications = [
            Specification(
                operation: .register,
                argumentPrefix: "--physical-helper-bootstrap-output=",
                filenamePrefix: "helper-bootstrap-"
            ),
            Specification(
                operation: .unregister,
                argumentPrefix: "--physical-helper-cleanup-output=",
                filenamePrefix: "helper-cleanup-"
            )
        ]
        let matches = specifications.compactMap { specification in
            authorizedOutputURL(
                arguments: arguments,
                environment: environment,
                argumentPrefix: specification.argumentPrefix,
                filenamePrefix: specification.filenamePrefix
            ).map { (specification.operation, $0) }
        }
        guard matches.count == 1, let match = matches.first else {
            return nil
        }
        operation = match.0
        outputURL = match.1
        self.registrar = registrar
    }

    public func execute() async throws {
        let result: PhysicalHelperBootstrapResult
        do {
            switch operation {
            case .register:
                let status = try await registrar.ensureAvailable()
                result = PhysicalHelperBootstrapResult(status: Self.label(for: status))
            case .unregister:
                try await registrar.unregister()
                result = PhysicalHelperBootstrapResult(status: "unregistered")
            }
        } catch {
            let status = await registrar.status()
            if status == .enabled || status == .requiresApproval {
                result = PhysicalHelperBootstrapResult(status: Self.label(for: status))
            } else {
                let error = error as NSError
                result = PhysicalHelperBootstrapResult(
                    status: "failed",
                    errorDomain: error.domain,
                    errorCode: error.code
                )
            }
        }
        try writeExclusiveJSON(result, to: outputURL)
    }

    private static func label(for status: PrivilegedHelperRegistrationStatus) -> String {
        switch status {
        case .enabled:
            "enabled"
        case .requiresApproval:
            "requires-approval"
        case .notRegistered:
            "not-registered"
        case .notFound:
            "not-found"
        case .unknown:
            "unknown"
        }
    }
}

public struct PhysicalPacketFilterAuditCommand: Sendable {
    private let outputURL: URL
    private let helper: any PacketFilterAuditing

    public init?(
        arguments: [String],
        environment: [String: String],
        helper: any PacketFilterAuditing = HelperClient()
    ) {
        guard let outputURL = authorizedOutputURL(
            arguments: arguments,
            environment: environment,
            argumentPrefix: "--physical-pf-audit-output=",
            filenamePrefix: "packet-filter-"
        ) else {
            return nil
        }
        self.outputURL = outputURL
        self.helper = helper
    }

    public func execute() async throws {
        let result: PhysicalPacketFilterAuditResult
        do {
            let residuePresent = try await helper.hasRules(anchor: "com.apple.container")
            result = .init(verified: true, residuePresent: residuePresent)
        } catch {
            result = .init(verified: false, residuePresent: false)
        }
        try writeExclusiveJSON(result, to: outputURL)
    }
}

private func authorizedOutputURL(
    arguments: [String],
    environment: [String: String],
    argumentPrefix: String,
    filenamePrefix: String
) -> URL? {
    guard let argument = arguments.first(where: { $0.hasPrefix(argumentPrefix) }),
          let authorization = environment["PHYSICAL_AUDIT_AUTHORIZATION"],
          let runID = UUID(uuidString: authorization),
          authorization == runID.uuidString.lowercased(),
          let rootPath = environment["PHYSICAL_AUDIT_ROOT"]
    else {
        return nil
    }
    let root = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
    let output = URL(
        fileURLWithPath: String(argument.dropFirst(argumentPrefix.count)),
        isDirectory: false
    ).standardizedFileURL
    var status = stat()
    guard root.path.hasPrefix("/"),
          Darwin.lstat(root.path, &status) == 0,
          status.st_mode & S_IFMT == S_IFDIR,
          status.st_uid == geteuid(),
          status.st_mode & 0o077 == 0,
          output.deletingLastPathComponent() == root,
          output.lastPathComponent == "\(filenamePrefix)\(authorization).json",
          Darwin.lstat(output.path, &status) != 0,
          errno == ENOENT
    else {
        return nil
    }
    return output
}

private func writeExclusiveJSON(_ value: some Encodable, to outputURL: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    let descriptor = Darwin.open(
        outputURL.path,
        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
        0o600
    )
    guard descriptor >= 0 else { throw posixError() }
    defer { Darwin.close(descriptor) }
    try data.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
            let count = Darwin.write(
                descriptor,
                buffer.baseAddress?.advanced(by: offset),
                buffer.count - offset
            )
            guard count >= 0 else {
                if errno == EINTR {
                    continue
                }
                throw posixError()
            }
            offset += count
        }
    }
    guard Darwin.fsync(descriptor) == 0 else { throw posixError() }
}

private func posixError() -> NSError {
    NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
}
