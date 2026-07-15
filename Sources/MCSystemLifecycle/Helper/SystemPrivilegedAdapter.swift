import Darwin
import Foundation

public struct PrivilegedVerifiedPackage: Sendable {
    public let runtimeVersion: String
    public let sha256: String
    public let openFile: OpenRuntimePackageFile

    public init(runtimeVersion: String, sha256: String, openFile: OpenRuntimePackageFile) {
        self.runtimeVersion = runtimeVersion
        self.sha256 = sha256
        self.openFile = openFile
    }
}

public protocol PrivilegedPackageVerifying: Sendable {
    func verify(_ package: FileHandle, against manifest: RuntimePackageManifest) throws -> PrivilegedVerifiedPackage
}

public protocol PrivilegedHostMutating: Sendable {
    func removePayload(manifest: RuntimePackageManifest) throws
    func forgetReceipt() throws
    func writeResolver(_ request: ResolverRequest) throws
    func removeResolver(name: String) throws
    func applyPacketFilter(_ request: PacketFilterRequest) throws
    func removePacketFilter() throws
    func removeKnownEmptyDirectories(manifest: RuntimePackageManifest) throws
}

public struct SystemPrivilegedAdapter: PrivilegedSystemAdapting {
    private let manifest: RuntimePackageManifest
    private let manifestID: String
    private let manifestSHA256: String
    private let packageVerifier: any PrivilegedPackageVerifying
    private let commandRunner: any FixedPrivilegedCommandRunning
    private let host: any PrivilegedHostMutating

    public init(packageOwner: uid_t = getuid()) {
        let runner = PosixSpawnFixedPrivilegedCommandRunner()
        let manifest = ReviewedRuntime110Manifest.package
        self.init(
            manifest: manifest,
            manifestID: ReviewedRuntime110Manifest.identifier,
            manifestSHA256: ReviewedRuntime110Manifest.sourceSHA256,
            packageVerifier: SystemPrivilegedPackageVerifier(allowedOwner: packageOwner),
            commandRunner: runner,
            host: SystemPrivilegedHostMutator(
                manifest: manifest,
                commandRunner: runner
            )
        )
    }

    public init(
        manifest: RuntimePackageManifest,
        manifestID: String,
        manifestSHA256: String,
        packageVerifier: any PrivilegedPackageVerifying,
        commandRunner: any FixedPrivilegedCommandRunning,
        host: any PrivilegedHostMutating
    ) {
        self.manifest = manifest
        self.manifestID = manifestID
        self.manifestSHA256 = manifestSHA256
        self.packageVerifier = packageVerifier
        self.commandRunner = commandRunner
        self.host = host
    }

    public func installVerifiedPackage(_ package: FileHandle, token: PackageInstallToken) throws {
        guard token.runtimeVersion == manifest.runtimeVersion, token.sha256 == manifest.sha256 else {
            throw SystemPrivilegedAdapterError.packageTokenMismatch
        }
        let verified = try packageVerifier.verify(package, against: manifest)
        guard verified.runtimeVersion == manifest.runtimeVersion, verified.sha256 == manifest.sha256 else {
            throw SystemPrivilegedAdapterError.verificationReportMismatch
        }
        try verified.openFile.revalidateIdentity()
        try commandRunner.run(.installPackage, package: verified.openFile)
    }

    public func removePayload(_ request: RemovePayloadRequest) throws {
        try validateManifest(request.manifestID, sha256: request.manifestSHA256)
        try host.removePayload(manifest: manifest)
    }

    public func forgetReceipt(identifier: String) throws {
        guard identifier == manifest.receiptIdentifier else {
            throw SystemPrivilegedAdapterError.receiptMismatch
        }
        try host.forgetReceipt()
    }

    public func writeResolver(_ request: ResolverRequest) throws {
        try PrivilegedRequest.writeResolver(request).validate(policy: .runtime110)
        try host.writeResolver(request)
    }

    public func removeResolver(name: String) throws {
        try PrivilegedRequest.removeResolver(name: name).validate(policy: .runtime110)
        try host.removeResolver(name: name)
    }

    public func applyPacketFilter(_ request: PacketFilterRequest) throws {
        try PrivilegedRequest.applyPacketFilter(request).validate(policy: .runtime110)
        try host.applyPacketFilter(request)
    }

    public func removePacketFilter(anchor: String) throws {
        try PrivilegedRequest.removePacketFilter(anchor: anchor).validate(policy: .runtime110)
        try host.removePacketFilter()
    }

    public func removeKnownEmptyDirectories(manifestID: String) throws {
        guard manifestID == self.manifestID else { throw SystemPrivilegedAdapterError.manifestMismatch }
        try host.removeKnownEmptyDirectories(manifest: manifest)
    }

    private func validateManifest(_ identifier: String, sha256: String) throws {
        guard identifier == manifestID, sha256 == manifestSHA256 else {
            throw SystemPrivilegedAdapterError.manifestMismatch
        }
    }
}

public struct SystemPrivilegedPackageVerifier: PrivilegedPackageVerifying {
    private let allowedOwner: uid_t
    private let verifier: RuntimePackageVerifier

    public init(
        allowedOwner: uid_t,
        verifier: RuntimePackageVerifier = .system
    ) {
        self.allowedOwner = allowedOwner
        self.verifier = verifier
    }

    public func verify(
        _ package: FileHandle,
        against manifest: RuntimePackageManifest
    ) throws -> PrivilegedVerifiedPackage {
        let openFile = try OpenRuntimePackageFile(
            duplicating: package.fileDescriptor,
            allowedOwner: allowedOwner
        )
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = VerificationResultBox()
        Task.detached {
            do {
                try await resultBox.store(.success(verifier.verify(openFile: openFile, against: manifest)))
            } catch {
                resultBox.store(.failure(error))
            }
            semaphore.signal()
        }
        semaphore.wait()
        let verified = try resultBox.take().get()
        try verified.openFile.revalidateIdentity()
        return PrivilegedVerifiedPackage(
            runtimeVersion: verified.runtimeVersion,
            sha256: verified.sha256,
            openFile: verified.openFile
        )
    }
}

public enum SystemPrivilegedAdapterError: Error, Equatable, Sendable {
    case manifestMismatch
    case packageTokenMismatch
    case receiptMismatch
    case verificationReportMismatch
}

private final class VerificationResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<VerifiedRuntimePackage, any Error>?

    func store(_ result: Result<VerifiedRuntimePackage, any Error>) {
        lock.withLock { self.result = result }
    }

    func take() -> Result<VerifiedRuntimePackage, any Error> {
        lock.withLock {
            precondition(result != nil)
            return result!
        }
    }
}
