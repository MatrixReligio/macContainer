import CryptoKit
import Darwin
import Foundation

public protocol RuntimePackageDigesting: Sendable {
    func sha256(of file: OpenRuntimePackageFile) async throws -> String
}

public protocol PackageSignatureVerifying: Sendable {
    func verifySignature(of file: OpenRuntimePackageFile) async throws -> PackageSignatureReport
}

public protocol RuntimePackageInspecting: Sendable {
    func inspect(_ file: OpenRuntimePackageFile) async throws -> RuntimePackageInspection
}

public struct PackageSignatureReport: Equatable, Sendable {
    public let teamID: String
    public let commonName: String
    public let notarized: Bool

    public init(teamID: String, commonName: String, notarized: Bool) {
        self.teamID = teamID
        self.commonName = commonName
        self.notarized = notarized
    }
}

public struct RuntimePackageInspection: Equatable, Sendable {
    public let runtimeVersion: String
    public let receiptIdentifier: String
    public let installLocation: String
    public let payload: [PayloadEntry]

    public init(
        runtimeVersion: String,
        receiptIdentifier: String,
        installLocation: String,
        payload: [PayloadEntry]
    ) {
        self.runtimeVersion = runtimeVersion
        self.receiptIdentifier = receiptIdentifier
        self.installLocation = installLocation
        self.payload = payload
    }
}

public struct VerifiedRuntimePackage: Sendable {
    public let runtimeVersion: String
    public let sha256: String
    public let installerTeamID: String
    public let signerCommonName: String
    public let receiptIdentifier: String
    public let installLocation: String
    public let payload: [PayloadEntry]
    public let openFile: OpenRuntimePackageFile
}

public enum PackageTrustError: Error, Equatable, Sendable {
    case digestMismatch
    case installLocationMismatch
    case invalidManifest
    case notarizationRejected
    case packageChangedDuringVerification
    case payloadMismatch(expectedCount: Int, actualCount: Int, firstDifference: String?)
    case receiptMismatch
    case signerCommonNameMismatch
    case teamIDMismatch
    case unsafePackageFile
    case unsignedPackage
    case versionMismatch

    var sanitizedCode: Int {
        switch self {
        case .unsafePackageFile: 40
        case .packageChangedDuringVerification: 41
        case .invalidManifest: 42
        case .digestMismatch: 43
        case .unsignedPackage: 44
        case .notarizationRejected: 45
        case .teamIDMismatch: 46
        case .signerCommonNameMismatch: 47
        case .versionMismatch: 48
        case .receiptMismatch: 49
        case .installLocationMismatch: 50
        case .payloadMismatch: 51
        }
    }
}

public final class OpenRuntimePackageFile: @unchecked Sendable {
    public let fileDescriptor: Int32
    public let sourceURL: URL
    private let initialIdentity: RuntimePackageFileIdentity

    fileprivate init(packageAt url: URL) throws {
        sourceURL = url.standardizedFileURL
        fileDescriptor = Darwin.open(sourceURL.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fileDescriptor >= 0 else {
            throw PackageTrustError.unsafePackageFile
        }
        do {
            initialIdentity = try Self.readAndValidateIdentity(fileDescriptor, allowedOwner: geteuid())
        } catch {
            Darwin.close(fileDescriptor)
            throw error
        }
    }

    public init(duplicating descriptor: Int32, allowedOwner: uid_t = getuid()) throws {
        fileDescriptor = Darwin.fcntl(descriptor, F_DUPFD_CLOEXEC, 0)
        guard fileDescriptor >= 0 else { throw PackageTrustError.unsafePackageFile }
        sourceURL = URL(fileURLWithPath: "/dev/fd/\(fileDescriptor)")
        do {
            initialIdentity = try Self.readAndValidateIdentity(fileDescriptor, allowedOwner: allowedOwner)
        } catch {
            Darwin.close(fileDescriptor)
            throw error
        }
    }

    deinit {
        Darwin.close(fileDescriptor)
    }

    public func duplicateFileDescriptor() throws -> Int32 {
        let duplicate = Darwin.fcntl(fileDescriptor, F_DUPFD_CLOEXEC, 0)
        guard duplicate >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return duplicate
    }

    public func revalidateIdentity() throws {
        let current = try Self.readAndValidateIdentity(fileDescriptor, allowedOwner: initialIdentity.owner)
        guard current == initialIdentity else {
            throw PackageTrustError.packageChangedDuringVerification
        }
    }

    private static func readAndValidateIdentity(
        _ descriptor: Int32,
        allowedOwner: uid_t
    ) throws -> RuntimePackageFileIdentity {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else {
            throw PackageTrustError.unsafePackageFile
        }
        guard
            status.st_mode & S_IFMT == S_IFREG,
            status.st_uid == allowedOwner,
            status.st_nlink == 1,
            status.st_mode & 0o022 == 0,
            status.st_size > 0
        else {
            throw PackageTrustError.unsafePackageFile
        }
        return RuntimePackageFileIdentity(
            device: status.st_dev,
            inode: status.st_ino,
            owner: status.st_uid,
            size: status.st_size,
            modifiedSeconds: status.st_mtimespec.tv_sec,
            modifiedNanoseconds: status.st_mtimespec.tv_nsec
        )
    }
}

public struct SHA256RuntimePackageDigester: RuntimePackageDigesting {
    public init() {}

    public func sha256(of file: OpenRuntimePackageFile) async throws -> String {
        var hasher = SHA256()
        var offset: off_t = 0
        var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
        while true {
            try Task.checkCancellation()
            let count = Darwin.pread(file.fileDescriptor, &buffer, buffer.count, offset)
            guard count >= 0 else {
                if errno == EINTR {
                    continue
                }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            guard count > 0 else { break }
            hasher.update(data: Data(buffer.prefix(count)))
            offset += off_t(count)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public struct RuntimePackageVerifier: Sendable {
    private let digester: any RuntimePackageDigesting
    private let signature: any PackageSignatureVerifying
    private let inspector: any RuntimePackageInspecting

    public init(
        digester: any RuntimePackageDigesting,
        signature: any PackageSignatureVerifying,
        inspector: any RuntimePackageInspecting
    ) {
        self.digester = digester
        self.signature = signature
        self.inspector = inspector
    }

    public func verify(
        packageAt url: URL,
        against manifest: RuntimePackageManifest
    ) async throws -> VerifiedRuntimePackage {
        let file = try OpenRuntimePackageFile(packageAt: url)
        return try await verify(openFile: file, against: manifest)
    }

    public func verify(
        openFile file: OpenRuntimePackageFile,
        against manifest: RuntimePackageManifest
    ) async throws -> VerifiedRuntimePackage {
        do {
            try manifest.validate()
        } catch {
            throw PackageTrustError.invalidManifest
        }

        let digest = try await digester.sha256(of: file)
        guard digest == manifest.sha256 else { throw PackageTrustError.digestMismatch }

        let signatureReport = try await signature.verifySignature(of: file)
        guard signatureReport.notarized else { throw PackageTrustError.notarizationRejected }
        guard signatureReport.teamID == manifest.installerTeamID else { throw PackageTrustError.teamIDMismatch }
        guard signatureReport.commonName == manifest.signerCommonName else {
            throw PackageTrustError.signerCommonNameMismatch
        }

        let inspection = try await inspector.inspect(file)
        guard inspection.runtimeVersion == manifest.runtimeVersion else { throw PackageTrustError.versionMismatch }
        guard inspection.receiptIdentifier == manifest.receiptIdentifier else {
            throw PackageTrustError.receiptMismatch
        }
        guard inspection.installLocation == manifest.installLocation else {
            throw PackageTrustError.installLocationMismatch
        }
        guard inspection.payload == manifest.payload else {
            let firstDifference = zip(manifest.payload, inspection.payload)
                .first { $0 != $1 }
                .map { expected, actual in
                    expected.relativePath == actual.relativePath
                        ? expected.relativePath
                        : "\(expected.relativePath) != \(actual.relativePath)"
                }
            throw PackageTrustError.payloadMismatch(
                expectedCount: manifest.payload.count,
                actualCount: inspection.payload.count,
                firstDifference: firstDifference
            )
        }
        try file.revalidateIdentity()

        return VerifiedRuntimePackage(
            runtimeVersion: inspection.runtimeVersion,
            sha256: digest,
            installerTeamID: signatureReport.teamID,
            signerCommonName: signatureReport.commonName,
            receiptIdentifier: inspection.receiptIdentifier,
            installLocation: inspection.installLocation,
            payload: inspection.payload,
            openFile: file
        )
    }
}

private struct RuntimePackageFileIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
    let owner: uid_t
    let size: off_t
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
}
