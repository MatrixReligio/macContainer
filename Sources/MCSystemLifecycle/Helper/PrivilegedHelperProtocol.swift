import Darwin
import Foundation

@objc public protocol MCPrivilegedHelperXPCProtocol {
    func perform(
        _ requestData: Data,
        packageFile: FileHandle?,
        withReply reply: @escaping (Data?, NSError?) -> Void
    )
}

public enum PrivilegedHelperXPC {
    public static func interface() -> NSXPCInterface {
        NSXPCInterface(with: MCPrivilegedHelperXPCProtocol.self)
    }
}

public enum PrivilegedRequest: Codable, Equatable, Sendable {
    case installVerifiedPackage(PackageInstallToken)
    case removePayload(RemovePayloadRequest)
    case forgetReceipt(identifier: String)
    case writeResolver(ResolverRequest)
    case removeResolver(name: String)
    case applyPacketFilter(PacketFilterRequest)
    case removePacketFilter(anchor: String)
    case removeKnownEmptyDirectories(manifestID: String)

    public func validate(policy: PathPolicy) throws {
        switch self {
        case let .installVerifiedPackage(token):
            try Self.validate(token)
        case let .removePayload(request):
            try Self.validate(request)
        case let .forgetReceipt(identifier):
            try Self.validateReceipt(identifier)
        case let .writeResolver(request):
            try Self.validate(request, policy: policy)
        case let .removeResolver(name):
            try Self.validateResolverName(name, policy: policy)
        case let .applyPacketFilter(request):
            try Self.validate(request, policy: policy)
        case let .removePacketFilter(anchor):
            try Self.validatePacketFilterAnchor(anchor, policy: policy)
        case let .removeKnownEmptyDirectories(manifestID):
            try Self.validateManifestID(manifestID)
        }
    }

    private static func validate(_ token: PackageInstallToken) throws {
        guard isVersion(token.runtimeVersion), isSHA256(token.sha256) else {
            throw PrivilegedRequestError.invalidPackageToken
        }
    }

    private static func validate(_ request: RemovePayloadRequest) throws {
        guard isManifestID(request.manifestID), isSHA256(request.manifestSHA256) else {
            throw PrivilegedRequestError.invalidManifest
        }
    }

    private static func validateReceipt(_ identifier: String) throws {
        guard identifier == "com.apple.container-installer" else {
            throw PrivilegedRequestError.invalidReceipt
        }
    }

    private static func validate(_ request: ResolverRequest, policy: PathPolicy) throws {
        guard
            policy.allowsResolverName(request.name),
            (1 ... 8).contains(request.nameservers.count),
            request.nameservers.allSatisfy(isIPAddress)
        else {
            throw PrivilegedRequestError.invalidResolver
        }
    }

    private static func validateResolverName(_ name: String, policy: PathPolicy) throws {
        guard policy.allowsResolverName(name) else { throw PrivilegedRequestError.invalidResolver }
    }

    private static func validate(_ request: PacketFilterRequest, policy: PathPolicy) throws {
        guard policy.allowsPacketFilterAnchor(request.anchor), isIPv4CIDR(request.subnetCIDR) else {
            throw PrivilegedRequestError.invalidPacketFilter
        }
    }

    private static func validatePacketFilterAnchor(_ anchor: String, policy: PathPolicy) throws {
        guard policy.allowsPacketFilterAnchor(anchor) else {
            throw PrivilegedRequestError.invalidPacketFilter
        }
    }

    private static func validateManifestID(_ manifestID: String) throws {
        guard isManifestID(manifestID) else { throw PrivilegedRequestError.invalidManifest }
    }

    private static func isVersion(_ value: String) -> Bool {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        return components.count == 3 && components.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { ("0" ... "9").contains($0) || ("a" ... "f").contains($0) }
    }

    private static func isManifestID(_ value: String) -> Bool {
        guard (1 ... 64).contains(value.count), let first = value.first, first.isLowercase || first.isNumber else {
            return false
        }
        return value.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "." || $0 == "-" }
    }

    private static func isIPAddress(_ value: String) -> Bool {
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        return value.withCString { pointer in
            inet_pton(AF_INET, pointer, &ipv4) == 1 || inet_pton(AF_INET6, pointer, &ipv6) == 1
        }
    }

    private static func isIPv4CIDR(_ value: String) -> Bool {
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2, let prefix = Int(components[1]), (0 ... 32).contains(prefix) else {
            return false
        }
        var address = in_addr()
        return String(components[0]).withCString { inet_pton(AF_INET, $0, &address) == 1 }
    }
}

public struct PackageInstallToken: Codable, Equatable, Sendable {
    public let runtimeVersion: String
    public let sha256: String
    public let verificationNonce: UUID

    public init(runtimeVersion: String, sha256: String, verificationNonce: UUID = UUID()) {
        self.runtimeVersion = runtimeVersion
        self.sha256 = sha256
        self.verificationNonce = verificationNonce
    }
}

public struct RemovePayloadRequest: Codable, Equatable, Sendable {
    public let manifestID: String
    public let manifestSHA256: String

    public init(manifestID: String, manifestSHA256: String) {
        self.manifestID = manifestID
        self.manifestSHA256 = manifestSHA256
    }
}

public struct ResolverRequest: Codable, Equatable, Sendable {
    public let name: String
    public let nameservers: [String]

    public init(name: String, nameservers: [String]) {
        self.name = name
        self.nameservers = nameservers
    }
}

public struct PacketFilterRequest: Codable, Equatable, Sendable {
    public let anchor: String
    public let subnetCIDR: String

    public init(anchor: String, subnetCIDR: String) {
        self.anchor = anchor
        self.subnetCIDR = subnetCIDR
    }
}

public enum PrivilegedRequestCodec {
    public static let maximumMessageBytes = 1024 * 1024
    private static let schemaVersion = 1

    public static func encode(_ request: PrivilegedRequest) throws -> Data {
        try request.validate(policy: .runtime110)
        let envelope = PrivilegedRequestEnvelope(version: schemaVersion, request: request)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        guard data.count <= maximumMessageBytes else { throw PrivilegedRequestError.messageTooLarge }
        return data
    }

    public static func decode(_ data: Data) throws -> PrivilegedRequest {
        guard data.count <= maximumMessageBytes else { throw PrivilegedRequestError.messageTooLarge }
        let envelope: PrivilegedRequestEnvelope
        do {
            envelope = try JSONDecoder().decode(PrivilegedRequestEnvelope.self, from: data)
        } catch {
            throw PrivilegedRequestError.invalidEncoding
        }
        guard envelope.version == schemaVersion else { throw PrivilegedRequestError.unsupportedVersion }
        try envelope.request.validate(policy: .runtime110)
        return envelope.request
    }
}

public struct PrivilegedResponse: Codable, Equatable, Sendable {
    public let version: Int
    public let success: Bool

    public init(version: Int = 1, success: Bool = true) {
        self.version = version
        self.success = success
    }
}

public enum PrivilegedResponseCodec {
    public static func encodeSuccess() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(PrivilegedResponse())
    }

    public static func decode(_ data: Data) throws -> PrivilegedResponse {
        guard data.count <= PrivilegedRequestCodec.maximumMessageBytes else {
            throw PrivilegedRequestError.messageTooLarge
        }
        do {
            let response = try JSONDecoder().decode(PrivilegedResponse.self, from: data)
            guard response.version == 1, response.success else {
                throw PrivilegedRequestError.unsupportedVersion
            }
            return response
        } catch let error as PrivilegedRequestError {
            throw error
        } catch {
            throw PrivilegedRequestError.invalidEncoding
        }
    }
}

public enum PrivilegedRequestError: Error, Equatable, Sendable {
    case invalidEncoding
    case invalidManifest
    case invalidPackageToken
    case invalidPacketFilter
    case invalidReceipt
    case invalidResolver
    case messageTooLarge
    case unsupportedVersion
}

private struct PrivilegedRequestEnvelope: Codable {
    let version: Int
    let request: PrivilegedRequest
}
