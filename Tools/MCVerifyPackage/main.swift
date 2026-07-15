import Foundation
import MCSystemLifecycle

@main
enum MCVerifyPackage {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard arguments.count == 3, arguments[0] == "--manifest" else {
                throw CommandError.usage
            }
            let manifestURL = try repositoryRelativeURL(arguments[1])
            let packageURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
            let manifest = try RuntimePackageManifest.load(from: manifestURL)
            let report = try await RuntimePackageVerifier.system.verify(packageAt: packageURL, against: manifest)
            print("Package trust PASS: Apple container \(report.runtimeVersion)")
            print("SHA-256: \(report.sha256)")
            print("Installer Team ID: \(report.installerTeamID)")
            print("Receipt: \(report.receiptIdentifier) at \(report.installLocation)")
            print("Payload entries: \(report.payload.count)")
        } catch {
            FileHandle.standardError.write(Data("Package trust FAIL: \(redacted(error))\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func repositoryRelativeURL(_ argument: String) throws -> URL {
        guard !argument.hasPrefix("/"), !argument.split(separator: "/").contains("..") else {
            throw CommandError.unsafeManifestPath
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).standardizedFileURL
        let url = root.appendingPathComponent(argument).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { throw CommandError.unsafeManifestPath }
        return url
    }

    private static func redacted(_ error: Error) -> String {
        switch error {
        case CommandError.usage:
            "usage: mc-verify-package --manifest <repository-relative.json> <package.pkg>"
        case CommandError.unsafeManifestPath:
            "unsafe manifest path"
        case let trust as PackageTrustError:
            String(describing: trust)
        case let manifest as RuntimePackageManifestError:
            String(describing: manifest)
        case let inspection as PackageInspectionError:
            String(describing: inspection)
        default:
            "verification failed"
        }
    }
}

private enum CommandError: Error {
    case unsafeManifestPath
    case usage
}
