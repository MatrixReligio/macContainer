import CryptoKit
import Foundation
import MCCompatibility

private struct ExpectationsDocument: Codable {
    let sourceCommit: String
    let appBundleIdentifier: String
    let appVersion: String
    let appBuild: String
    let appDesignatedRequirementHash: String
    let runtimeVersion: String
    let runtimePackageSHA256: String
    let testPlanVersion: String
    let requiredOperationIDs: Set<String>
    let verificationNow: Date
    let maximumAge: TimeInterval
    let futureTolerance: TimeInterval

    var value: PhysicalAttestationExpectations {
        .init(
            sourceCommit: sourceCommit,
            appBundleIdentifier: appBundleIdentifier,
            appVersion: appVersion,
            appBuild: appBuild,
            appDesignatedRequirementHash: appDesignatedRequirementHash,
            runtimeVersion: runtimeVersion,
            runtimePackageSHA256: runtimePackageSHA256,
            testPlanVersion: testPlanVersion,
            requiredOperationIDs: requiredOperationIDs,
            now: verificationNow,
            maximumAge: maximumAge,
            futureTolerance: futureTolerance
        )
    }
}

private enum ToolError: Error, CustomStringConvertible {
    case invalidArguments
    case unsafePrivateKey

    var description: String {
        switch self {
        case .invalidArguments: "invalid arguments"
        case .unsafePrivateKey: "private key must be an owner-only regular file"
        }
    }
}

@main
private enum MCAttestationTool {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let command = arguments.first else { throw ToolError.invalidArguments }
            switch command {
            case "verify":
                try await verify(Array(arguments.dropFirst()))
            case "sign":
                try sign(Array(arguments.dropFirst()))
            default:
                throw ToolError.invalidArguments
            }
        } catch let error as AttestationVerificationError {
            FileHandle.standardError.write(Data("Physical attestation FAIL: \(error.rawValue)\n".utf8))
            exit(EXIT_FAILURE)
        } catch {
            FileHandle.standardError.write(Data("Physical attestation FAIL: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func verify(_ arguments: [String]) async throws {
        guard let attestationPath = arguments.first else { throw ToolError.invalidArguments }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let attestationURL = URL(fileURLWithPath: attestationPath, relativeTo: root).standardizedFileURL
        let signerURL = option("--trusted-signers", in: arguments)
            .map { URL(fileURLWithPath: $0, relativeTo: root).standardizedFileURL }
            ?? root.appending(path: "Config/compatibility/trusted-attestation-signers.json")
        let expectationsURL = option("--expectations", in: arguments)
            .map { URL(fileURLWithPath: $0, relativeTo: root).standardizedFileURL }
            ?? attestationURL.deletingPathExtension().appendingPathExtension("expectations.json")

        let attestation = try PhysicalTestAttestation.decode(Data(contentsOf: attestationURL))
        let signers = try TrustedAttestationSignerConfiguration.decode(Data(contentsOf: signerURL))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ExpectationsDocument.self, from: Data(contentsOf: expectationsURL))
        let verifier = AttestationVerifier(
            trustedSigners: signers.signers,
            replayStore: InMemoryAttestationReplayStore()
        )
        try await verifier.verify(attestation, expectations: document.value)
        print(
            "Physical attestation PASS: \(attestation.runtimeVersion) \(attestation.testPlanVersion), " +
                "\(attestation.operationResults.count) operations, zero residue"
        )
    }

    private static func sign(_ arguments: [String]) throws {
        guard arguments.count >= 2,
              let privateKeyPath = option("--private-key", in: arguments)
        else {
            throw ToolError.invalidArguments
        }
        let inputURL = URL(fileURLWithPath: arguments[0]).standardizedFileURL
        let outputURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
        let keyURL = URL(fileURLWithPath: privateKeyPath).standardizedFileURL
        let attributes = try FileManager.default.attributesOfItem(atPath: keyURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o077 == 0
        else {
            throw ToolError.unsafePrivateKey
        }

        let unsigned = try PhysicalTestAttestation.decode(Data(contentsOf: inputURL))
        guard unsigned.signature.isEmpty else { throw ToolError.invalidArguments }
        let keyPEM = try String(contentsOf: keyURL, encoding: .utf8)
        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: keyPEM)
        let signature = try privateKey.signature(for: unsigned.canonicalSigningData())
        let signed = unsigned.replacing(signature: signature.derRepresentation.base64EncodedString())
        try signed.encoded().write(to: outputURL, options: [.atomic, .completeFileProtection])
    }

    private static func option(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
