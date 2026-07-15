import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("Runtime package verifier")
struct RuntimePackageVerifierTests {
    @Test func `accepts only the exact reviewed package`() async throws {
        let file = try PackageFileFixture()
        defer { file.cleanup() }
        let verifier = RuntimePackageVerifier(
            digester: FakePackageDigester(value: ManifestFixture.reviewed.sha256),
            signature: FakePackageSignatureVerifier(report: .reviewed),
            inspector: FakePackageInspector(inspection: .reviewed)
        )

        let report = try await verifier.verify(packageAt: file.url, against: ManifestFixture.reviewed)

        #expect(report.sha256 == "0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714")
        #expect(report.receiptIdentifier == "com.apple.container-installer")
        #expect(report.installLocation == "/usr/local")
        #expect(report.runtimeVersion == "1.1.0")
        #expect(report.openFile.fileDescriptor >= 0)
    }

    @Test(arguments: PackageMutation.allCases)
    fileprivate func `rejects every trust mismatch`(_ mutation: PackageMutation) async throws {
        let file = try PackageFileFixture()
        defer { file.cleanup() }
        let verifier = RuntimePackageVerifier.fixture(mutation: mutation)

        await #expect(throws: PackageTrustError.self) {
            _ = try await verifier.verify(packageAt: file.url, against: ManifestFixture.reviewed)
        }
    }

    @Test func `rejects symlink and hard linked package before trust adapters run`() async throws {
        let file = try PackageFileFixture()
        defer { file.cleanup() }
        let verifier = RuntimePackageVerifier.fixture(mutation: nil)

        await #expect(throws: PackageTrustError.unsafePackageFile) {
            _ = try await verifier.verify(packageAt: file.symlinkURL, against: ManifestFixture.reviewed)
        }
        try file.createHardLink()
        await #expect(throws: PackageTrustError.unsafePackageFile) {
            _ = try await verifier.verify(packageAt: file.hardLinkURL, against: ManifestFixture.reviewed)
        }
    }

    @Test func `rejects traversal duplicates and malformed immutable manifests`() {
        let unsafePaths = ["/absolute", "../escape", "bin/../escape", "./bin", "bin//tool"]
        for path in unsafePaths {
            let manifest = ManifestFixture.reviewed.replacingPayload([
                PayloadEntry(relativePath: path, kind: .file, sha256: String(repeating: "a", count: 64))
            ])
            #expect(throws: RuntimePackageManifestError.self) {
                try manifest.validate()
            }
        }

        let duplicate = ManifestFixture.reviewed.replacingPayload([
            .init(relativePath: "bin", kind: .directory),
            .init(relativePath: "bin", kind: .directory)
        ])
        #expect(throws: RuntimePackageManifestError.duplicatePayloadPath("bin")) {
            try duplicate.validate()
        }
    }

    @Test func `detects in place mutation after inspection`() async throws {
        let file = try PackageFileFixture()
        defer { file.cleanup() }
        let verifier = RuntimePackageVerifier(
            digester: FakePackageDigester(value: ManifestFixture.reviewed.sha256),
            signature: FakePackageSignatureVerifier(report: .reviewed),
            inspector: MutatingPackageInspector(url: file.url)
        )

        await #expect(throws: PackageTrustError.packageChangedDuringVerification) {
            _ = try await verifier.verify(packageAt: file.url, against: ManifestFixture.reviewed)
        }
    }
}

private enum PackageMutation: CaseIterable, Sendable {
    case unsigned
    case notarizationRejected
    case wrongTeamID
    case wrongCommonName
    case wrongDigest
    case wrongVersion
    case wrongReceipt
    case wrongInstallLocation
    case extraPayload
    case symlinkSubstitution
}

private struct FakePackageDigester: RuntimePackageDigesting {
    let value: String

    func sha256(of _: OpenRuntimePackageFile) async throws -> String {
        value
    }
}

private struct FakePackageSignatureVerifier: PackageSignatureVerifying {
    let report: PackageSignatureReport
    let error: PackageTrustError?

    init(report: PackageSignatureReport, error: PackageTrustError? = nil) {
        self.report = report
        self.error = error
    }

    func verifySignature(of _: OpenRuntimePackageFile) async throws -> PackageSignatureReport {
        if let error {
            throw error
        }
        return report
    }
}

private struct FakePackageInspector: RuntimePackageInspecting {
    let inspection: RuntimePackageInspection

    func inspect(_ file: OpenRuntimePackageFile) async throws -> RuntimePackageInspection {
        _ = file
        return inspection
    }
}

private struct MutatingPackageInspector: RuntimePackageInspecting {
    let url: URL

    func inspect(_: OpenRuntimePackageFile) async throws -> RuntimePackageInspection {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("mutation".utf8))
        try handle.synchronize()
        try handle.close()
        return .reviewed
    }
}

private extension RuntimePackageVerifier {
    // A table-driven test builder is clearer than ten near-identical fixture types.
    // swiftlint:disable:next cyclomatic_complexity
    static func fixture(mutation: PackageMutation?) -> Self {
        var digest = ManifestFixture.reviewed.sha256
        var signature = PackageSignatureReport.reviewed
        var inspection = RuntimePackageInspection.reviewed
        var signatureError: PackageTrustError?

        switch mutation {
        case .unsigned:
            signatureError = .unsignedPackage
        case .notarizationRejected:
            signature = signature.replacing(notarized: false)
        case .wrongTeamID:
            signature = signature.replacing(teamID: "ATTACKER")
        case .wrongCommonName:
            signature = signature.replacing(commonName: "Developer ID Installer: Other")
        case .wrongDigest:
            digest = String(repeating: "0", count: 64)
        case .wrongVersion:
            inspection = inspection.replacing(runtimeVersion: "9.9.9")
        case .wrongReceipt:
            inspection = inspection.replacing(receiptIdentifier: "example.wrong")
        case .wrongInstallLocation:
            inspection = inspection.replacing(installLocation: "/tmp")
        case .extraPayload:
            inspection = inspection.replacing(payload: inspection.payload + [
                .init(relativePath: "bin/surprise", kind: .file, sha256: String(repeating: "f", count: 64))
            ])
        case .symlinkSubstitution:
            var payload = inspection.payload
            payload[1] = .init(relativePath: "bin/container", kind: .symlink, linkTarget: "/tmp/attacker")
            inspection = inspection.replacing(payload: payload)
        case nil:
            break
        }

        return Self(
            digester: FakePackageDigester(value: digest),
            signature: FakePackageSignatureVerifier(report: signature, error: signatureError),
            inspector: FakePackageInspector(inspection: inspection)
        )
    }
}

private enum ManifestFixture {
    static let payload: [PayloadEntry] = [
        .init(relativePath: "bin", kind: .directory),
        .init(relativePath: "bin/container", kind: .file, sha256: String(repeating: "a", count: 64))
    ]

    static let reviewed = RuntimePackageManifest(
        runtimeVersion: "1.1.0",
        assetName: "container-1.1.0-installer-signed.pkg",
        sha256: "0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714",
        installerTeamID: "UPBK2H6LZM",
        signerCommonName: "Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)",
        receiptIdentifier: "com.apple.container-installer",
        installLocation: "/usr/local",
        payload: payload
    )
}

private extension PackageSignatureReport {
    static let reviewed = Self(
        teamID: "UPBK2H6LZM",
        commonName: "Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)",
        notarized: true
    )

    func replacing(
        teamID: String? = nil,
        commonName: String? = nil,
        notarized: Bool? = nil
    ) -> Self {
        Self(
            teamID: teamID ?? self.teamID,
            commonName: commonName ?? self.commonName,
            notarized: notarized ?? self.notarized
        )
    }
}

private extension RuntimePackageInspection {
    static let reviewed = Self(
        runtimeVersion: "1.1.0",
        receiptIdentifier: "com.apple.container-installer",
        installLocation: "/usr/local",
        payload: ManifestFixture.payload
    )

    func replacing(
        runtimeVersion: String? = nil,
        receiptIdentifier: String? = nil,
        installLocation: String? = nil,
        payload: [PayloadEntry]? = nil
    ) -> Self {
        Self(
            runtimeVersion: runtimeVersion ?? self.runtimeVersion,
            receiptIdentifier: receiptIdentifier ?? self.receiptIdentifier,
            installLocation: installLocation ?? self.installLocation,
            payload: payload ?? self.payload
        )
    }
}

private final class PackageFileFixture: @unchecked Sendable {
    let root: URL
    let url: URL
    let symlinkURL: URL
    let hardLinkURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainerPackageVerifierTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        url = root.appendingPathComponent("runtime.pkg")
        symlinkURL = root.appendingPathComponent("runtime-link.pkg")
        hardLinkURL = root.appendingPathComponent("runtime-hardlink.pkg")
        try Data("fixture".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: url)
    }

    func createHardLink() throws {
        try FileManager.default.linkItem(at: url, to: hardLinkURL)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private extension RuntimePackageManifest {
    func replacingPayload(_ payload: [PayloadEntry]) -> Self {
        Self(
            runtimeVersion: runtimeVersion,
            assetName: assetName,
            sha256: sha256,
            installerTeamID: installerTeamID,
            signerCommonName: signerCommonName,
            receiptIdentifier: receiptIdentifier,
            installLocation: installLocation,
            payload: payload
        )
    }
}
