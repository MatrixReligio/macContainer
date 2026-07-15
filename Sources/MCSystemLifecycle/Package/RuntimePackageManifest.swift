import Foundation

public struct RuntimePackageManifest: Codable, Equatable, Sendable {
    public let runtimeVersion: String
    public let assetName: String
    public let sha256: String
    public let installerTeamID: String
    public let signerCommonName: String
    public let receiptIdentifier: String
    public let installLocation: String
    public let payload: [PayloadEntry]

    public init(
        runtimeVersion: String,
        assetName: String,
        sha256: String,
        installerTeamID: String,
        signerCommonName: String,
        receiptIdentifier: String,
        installLocation: String,
        payload: [PayloadEntry]
    ) {
        self.runtimeVersion = runtimeVersion
        self.assetName = assetName
        self.sha256 = sha256
        self.installerTeamID = installerTeamID
        self.signerCommonName = signerCommonName
        self.receiptIdentifier = receiptIdentifier
        self.installLocation = installLocation
        self.payload = payload
    }

    public static func load(from url: URL) throws -> Self {
        let manifest = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url, options: [.mappedIfSafe]))
        try manifest.validate()
        return manifest
    }

    public func validate() throws {
        try validateIdentity()
        try validatePayload()
    }

    private func validateIdentity() throws {
        guard Self.isSafeVersion(runtimeVersion) else {
            throw RuntimePackageManifestError.invalidRuntimeVersion
        }
        guard Self.isSafeAssetName(assetName) else {
            throw RuntimePackageManifestError.invalidAssetName
        }
        guard Self.isSHA256(sha256) else {
            throw RuntimePackageManifestError.invalidSHA256
        }
        guard Self.isSafeTeamID(installerTeamID) else {
            throw RuntimePackageManifestError.invalidTeamID
        }
        guard !signerCommonName.isEmpty, signerCommonName.count <= 256 else {
            throw RuntimePackageManifestError.invalidSignerCommonName
        }
        guard Self.isSafeIdentifier(receiptIdentifier) else {
            throw RuntimePackageManifestError.invalidReceiptIdentifier
        }
        guard installLocation == "/usr/local" else {
            throw RuntimePackageManifestError.invalidInstallLocation
        }
        guard !payload.isEmpty else {
            throw RuntimePackageManifestError.emptyPayload
        }
    }

    private func validatePayload() throws {
        var paths = Set<String>()
        var previousPath: String?
        for entry in payload {
            try entry.validate()
            guard paths.insert(entry.relativePath).inserted else {
                throw RuntimePackageManifestError.duplicatePayloadPath(entry.relativePath)
            }
            if let previousPath, previousPath >= entry.relativePath {
                throw RuntimePackageManifestError.unsortedPayload
            }
            previousPath = entry.relativePath
        }
    }

    private static func isSafeVersion(_ value: String) -> Bool {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        return components.count == 3 && components.allSatisfy { component in
            !component.isEmpty && component.allSatisfy(\.isNumber)
        }
    }

    private static func isSafeAssetName(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 128 && value == URL(fileURLWithPath: value).lastPathComponent &&
            !value.contains("..") && value.hasSuffix(".pkg")
    }

    fileprivate static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { ("0" ... "9").contains($0) || ("a" ... "f").contains($0) }
    }

    private static func isSafeTeamID(_ value: String) -> Bool {
        value.count == 10 && value.allSatisfy { $0.isASCII && ($0.isNumber || $0.isUppercase) }
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        return components.count >= 3 && components.allSatisfy { component in
            !component.isEmpty && component.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }
}

public struct PayloadEntry: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case file
        case directory
        case symlink
    }

    public let relativePath: String
    public let kind: Kind
    public let sha256: String?
    public let linkTarget: String?

    public init(
        relativePath: String,
        kind: Kind,
        sha256: String? = nil,
        linkTarget: String? = nil
    ) {
        self.relativePath = relativePath
        self.kind = kind
        self.sha256 = sha256
        self.linkTarget = linkTarget
    }

    fileprivate func validate() throws {
        guard Self.isSafeRelativePath(relativePath) else {
            throw RuntimePackageManifestError.unsafePayloadPath(relativePath)
        }
        switch kind {
        case .file:
            guard let sha256, RuntimePackageManifest.isSHA256(sha256), linkTarget == nil else {
                throw RuntimePackageManifestError.invalidPayloadEntry(relativePath)
            }
        case .directory:
            guard sha256 == nil, linkTarget == nil else {
                throw RuntimePackageManifestError.invalidPayloadEntry(relativePath)
            }
        case .symlink:
            guard sha256 == nil, let linkTarget, Self.isSafeLinkTarget(linkTarget) else {
                throw RuntimePackageManifestError.invalidPayloadEntry(relativePath)
            }
        }
    }

    private static func isSafeRelativePath(_ value: String) -> Bool {
        guard
            !value.isEmpty,
            value.count <= 1024,
            !value.hasPrefix("/"),
            !value.hasPrefix("./"),
            !value.contains("//")
        else {
            return false
        }
        return value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { component in
            !component.isEmpty && component != "." && component != ".." && !component.contains("\0")
        }
    }

    private static func isSafeLinkTarget(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 1024, !value.contains("\0") else { return false }
        return !value.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }
}

public enum RuntimePackageManifestError: Error, Equatable, Sendable {
    case duplicatePayloadPath(String)
    case emptyPayload
    case invalidAssetName
    case invalidInstallLocation
    case invalidPayloadEntry(String)
    case invalidReceiptIdentifier
    case invalidRuntimeVersion
    case invalidSHA256
    case invalidSignerCommonName
    case invalidTeamID
    case unsafePayloadPath(String)
    case unsortedPayload
}
