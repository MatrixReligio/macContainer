import Darwin
import Foundation

public protocol PrivilegedSystemAdapting: Sendable {
    func installVerifiedPackage(_ package: FileHandle, token: PackageInstallToken) throws
    func removePayload(_ request: RemovePayloadRequest) throws
    func forgetReceipt(identifier: String) throws
    func writeResolver(_ request: ResolverRequest) throws
    func removeResolver(name: String) throws
    func removeEmptyResolverDirectory() throws
    func createDNSDomain(_ request: DNSDomainRequest) throws
    func deleteDNSDomain(name: String) throws
    func applyPacketFilter(_ request: PacketFilterRequest) throws
    func removePacketFilter(anchor: String) throws
    func packetFilterRulesPresent(anchor: String) throws -> Bool
    func removeKnownEmptyDirectories(manifestID: String) throws
}

public final class PrivilegedOperationGate: @unchecked Sendable {
    private let lock = NSLock()

    public init() {}

    fileprivate func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        try lock.withLock(operation)
    }
}

public final class PrivilegedHelperService: NSObject, MCPrivilegedHelperXPCProtocol, @unchecked Sendable {
    private let system: any PrivilegedSystemAdapting
    private let operationGate: PrivilegedOperationGate

    public init(
        system: any PrivilegedSystemAdapting,
        operationGate: PrivilegedOperationGate = PrivilegedOperationGate()
    ) {
        self.system = system
        self.operationGate = operationGate
    }

    public func perform(
        _ requestData: Data,
        packageFile: FileHandle?,
        withReply reply: @escaping (Data?, NSError?) -> Void
    ) {
        do {
            let response = try operationGate.withLock {
                let request = try PrivilegedRequestCodec.decode(requestData)
                return try PrivilegedResponseCodec.encode(dispatch(request, packageFile: packageFile))
            }
            reply(response, nil)
        } catch {
            reply(nil, Self.sanitizedError(for: error))
        }
    }

    // The enum switch is the complete privileged-operation allowlist.
    // swiftlint:disable:next cyclomatic_complexity
    private func dispatch(_ request: PrivilegedRequest, packageFile: FileHandle?) throws -> PrivilegedResponse {
        switch request {
        case let .installVerifiedPackage(token):
            guard let packageFile else { throw PrivilegedHelperServiceError.packageFileRequired }
            try system.installVerifiedPackage(packageFile, token: token)
        case let .removePayload(request):
            try rejectSmuggledPackage(packageFile)
            try system.removePayload(request)
        case let .forgetReceipt(identifier):
            try rejectSmuggledPackage(packageFile)
            try system.forgetReceipt(identifier: identifier)
        case let .writeResolver(request):
            try rejectSmuggledPackage(packageFile)
            try system.writeResolver(request)
        case let .removeResolver(name):
            try rejectSmuggledPackage(packageFile)
            try system.removeResolver(name: name)
        case .removeEmptyResolverDirectory:
            try rejectSmuggledPackage(packageFile)
            try system.removeEmptyResolverDirectory()
        case let .createDNSDomain(request):
            try rejectSmuggledPackage(packageFile)
            try system.createDNSDomain(request)
        case let .deleteDNSDomain(name):
            try rejectSmuggledPackage(packageFile)
            try system.deleteDNSDomain(name: name)
        case let .applyPacketFilter(request):
            try rejectSmuggledPackage(packageFile)
            try system.applyPacketFilter(request)
        case let .removePacketFilter(anchor):
            try rejectSmuggledPackage(packageFile)
            try system.removePacketFilter(anchor: anchor)
        case let .auditPacketFilter(anchor):
            try rejectSmuggledPackage(packageFile)
            return try PrivilegedResponse(residuePresent: system.packetFilterRulesPresent(anchor: anchor))
        case let .removeKnownEmptyDirectories(manifestID):
            try rejectSmuggledPackage(packageFile)
            try system.removeKnownEmptyDirectories(manifestID: manifestID)
        }
        return PrivilegedResponse()
    }

    private func rejectSmuggledPackage(_ packageFile: FileHandle?) throws {
        guard packageFile == nil else { throw PrivilegedHelperServiceError.unexpectedPackageFile }
    }

    private static func sanitizedError(for error: Error) -> NSError {
        NSError(
            domain: "container.matrixreligio.com.helper",
            code: sanitizedErrorCode(for: error),
            userInfo: [NSLocalizedDescriptionKey: "The privileged operation was rejected."]
        )
    }

    static func sanitizedErrorCode(for error: Error) -> Int {
        switch error {
        case PrivilegedRequestError.messageTooLarge:
            2
        case is PrivilegedRequestError:
            3
        case PrivilegedHelperServiceError.packageFileRequired,
             PrivilegedHelperServiceError.unexpectedPackageFile:
            4
        case let error as FixedPrivilegedCommandError:
            error.sanitizedCode
        case let error as PackageTrustError:
            error.sanitizedCode
        case let error as PackageInspectionError:
            error.sanitizedCode
        case let error as SystemPrivilegedAdapterError:
            error.sanitizedCode
        case let error as SystemPrivilegedHostError:
            error.sanitizedCode
        case let error as NSError where error.domain == NSPOSIXErrorDomain:
            sanitizedPOSIXErrorCode(error.code)
        default:
            5
        }
    }

    private static func sanitizedPOSIXErrorCode(_ code: Int) -> Int {
        switch Int32(code) {
        case EACCES, EPERM, EROFS: 80
        case ENOENT: 81
        case EEXIST: 82
        case ENOSPC, EMFILE, ENFILE: 83
        case EIO: 84
        default: (1 ... 255).contains(code) ? 1000 + code : 1099
        }
    }
}

public enum PrivilegedHelperServiceError: Error, Equatable, Sendable {
    case packageFileRequired
    case unexpectedPackageFile
}
