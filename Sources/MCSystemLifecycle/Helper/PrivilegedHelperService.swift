import Foundation

public protocol PrivilegedSystemAdapting: Sendable {
    func installVerifiedPackage(_ package: FileHandle, token: PackageInstallToken) throws
    func removePayload(_ request: RemovePayloadRequest) throws
    func forgetReceipt(identifier: String) throws
    func writeResolver(_ request: ResolverRequest) throws
    func removeResolver(name: String) throws
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
        let code = switch error {
        case PrivilegedRequestError.messageTooLarge:
            2
        case is PrivilegedRequestError:
            3
        case PrivilegedHelperServiceError.packageFileRequired,
             PrivilegedHelperServiceError.unexpectedPackageFile:
            4
        default:
            5
        }
        return NSError(
            domain: "container.matrixreligio.com.helper",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: "The privileged operation was rejected."]
        )
    }
}

public enum PrivilegedHelperServiceError: Error, Equatable, Sendable {
    case packageFileRequired
    case unexpectedPackageFile
}
