import Darwin
import Foundation
import MCContainerBridge
import MCSystemLifecycle

enum PhysicalTestGate {
    static let environment = ProcessInfo.processInfo.environment

    static var runID: UUID? {
        environment["PHYSICAL_RUN_ID"].flatMap(UUID.init(uuidString:))
    }

    static var runRoot: URL? {
        environment["PHYSICAL_RUN_ROOT"].map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
        }
    }

    static var isAuthorized: Bool {
        guard
            let runID,
            let runRoot,
            environment["PHYSICAL_TEST_AUTHORIZATION"] == runID.uuidString.lowercased(),
            runRoot.lastPathComponent == runID.uuidString.lowercased(),
            runRoot.path.hasPrefix("/"),
            FileManager.default.fileExists(atPath: runRoot.path)
        else {
            return false
        }
        return true
    }

    static var namespace: String {
        "mct-e2e-\(runID?.uuidString.lowercased() ?? "unauthorized")"
    }

    static var phase: String? {
        environment["PHYSICAL_TEST_PHASE"]
    }

    static func packageURL(version: String) throws -> URL {
        guard isAuthorized, let runRoot else {
            throw PhysicalTestGateError.authorizationMissing
        }
        let key = switch version {
        case "1.0.0": "PHYSICAL_PACKAGE_100"
        case "1.1.0": "PHYSICAL_PACKAGE_110"
        default: throw PhysicalTestGateError.unreviewedPackageVersion
        }
        guard let path = environment[key], !path.isEmpty else {
            throw PhysicalTestGateError.packageMissing
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let expectedParent = runRoot.appendingPathComponent("downloads", isDirectory: true)
        guard url.deletingLastPathComponent() == expectedParent,
              FileManager.default.fileExists(atPath: url.path)
        else {
            throw PhysicalTestGateError.packageOutsideRunRoot
        }
        return url
    }

    static func upgradeStateRoot() throws -> URL {
        guard isAuthorized, let runRoot,
              let path = environment["PHYSICAL_UPGRADE_STATE"], !path.isEmpty
        else {
            throw PhysicalTestGateError.authorizationMissing
        }
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        guard url == runRoot.appendingPathComponent("upgrade-state", isDirectory: true),
              FileManager.default.fileExists(atPath: url.path)
        else {
            throw PhysicalTestGateError.packageOutsideRunRoot
        }
        return url
    }

    static func productionBridge() throws -> AppleRuntimeBridge {
        guard isAuthorized, let runRoot else {
            throw PhysicalTestGateError.authorizationMissing
        }
        return AppleRuntimeBridge(
            kernelTemporaryRoot: runRoot.appendingPathComponent("kernel-downloads", isDirectory: true)
        )
    }

    static func record(_ ids: String...) throws {
        guard isAuthorized, let runID,
              let path = environment["PHYSICAL_RESULTS_ROOT"]
        else {
            throw PhysicalTestGateError.authorizationMissing
        }
        let resultsRoot = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let expectedName = "maccontainer-physical-results-\(runID.uuidString.lowercased())"
        var status = stat()
        guard resultsRoot.deletingLastPathComponent() == FileManager.default.temporaryDirectory.standardizedFileURL,
              resultsRoot.lastPathComponent == expectedName,
              lstat(resultsRoot.path, &status) == 0,
              status.st_mode & S_IFMT == S_IFDIR,
              status.st_uid == geteuid(),
              status.st_mode & 0o077 == 0
        else {
            throw PhysicalTestGateError.resultsRootMissing
        }
        for id in ids {
            guard id.range(of: "^[a-z0-9.-]+$", options: .regularExpression) != nil else {
                throw PhysicalTestGateError.invalidResultID
            }
            let destination = resultsRoot.appendingPathComponent("\(id).json")
            let bytes = Data("{\"id\":\"\(id)\",\"passed\":true}\n".utf8)
            let descriptor = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            let isMatchingExistingResult = descriptor < 0 && errno == EEXIST &&
                (try? Data(contentsOf: destination, options: [.uncached])) == bytes
            if isMatchingExistingResult {
                continue
            }
            guard descriptor >= 0 else {
                throw PhysicalTestGateError.duplicateOrUnsafeResult
            }
            defer { close(descriptor) }
            let written = bytes.withUnsafeBytes { buffer in
                Darwin.write(descriptor, buffer.baseAddress, buffer.count)
            }
            guard written == bytes.count, fsync(descriptor) == 0 else {
                throw PhysicalTestGateError.resultWriteFailed
            }
        }
    }
}

enum PhysicalTestGateError: Error {
    case authorizationMissing
    case packageMissing
    case packageOutsideRunRoot
    case resultsRootMissing
    case invalidResultID
    case duplicateOrUnsafeResult
    case resultWriteFailed
    case unreviewedPackageVersion
}

struct PhysicalSignedAppInstallHelper: InstallPrivilegedHelping, UpgradePrivilegedHelping {
    func install(_ package: VerifiedRuntimePackage) async throws {
        try package.openFile.revalidateIdentity()
        let expected = try PhysicalTestGate.packageURL(version: package.runtimeVersion)
        guard package.openFile.sourceURL.standardizedFileURL == expected else {
            throw PhysicalSignedAppOperationError.packageIdentityMismatch
        }
        _ = try await PhysicalSignedAppOperations.invoke("install-\(package.runtimeVersion)")
    }
}

struct PhysicalSignedAppOperationResult: Decodable, Equatable, Sendable {
    let operation: String
    let succeeded: Bool
    let completion: String?
    let auditEmpty: Bool?
    let auditComplete: Bool?
    let preservedCount: Int?
    let errorDomain: String?
    let errorCode: Int?
}

enum PhysicalSignedAppOperations {
    static func roundTripDNS() async throws {
        _ = try await invoke("dns-round-trip")
    }

    static func completeUninstall() async throws -> PhysicalSignedAppOperationResult {
        try await invoke("complete-uninstall")
    }

    static func invoke(_ operation: String) async throws -> PhysicalSignedAppOperationResult {
        guard PhysicalTestGate.isAuthorized,
              let runID = PhysicalTestGate.runID,
              let runRoot = PhysicalTestGate.runRoot,
              let appPath = PhysicalTestGate.environment["PHYSICAL_TEST_APP"]
        else {
            throw PhysicalSignedAppOperationError.authorizationMissing
        }
        let app = URL(fileURLWithPath: appPath, isDirectory: true).standardizedFileURL
        guard app.pathExtension == "app",
              FileManager.default.isExecutableFile(
                  atPath: app.appendingPathComponent("Contents/MacOS/MacContainer").path
              )
        else {
            throw PhysicalSignedAppOperationError.appUnavailable
        }

        let invocationID = UUID().uuidString.lowercased()
        let temporaryRoot = FileManager.default.temporaryDirectory.standardizedFileURL
        let output = temporaryRoot.appendingPathComponent(
            "helper-operation-\(invocationID).json",
            isDirectory: false
        )
        defer { try? FileManager.default.removeItem(at: output) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [
            "-n", "-W",
            "--env", "PHYSICAL_AUDIT_AUTHORIZATION=\(invocationID)",
            "--env", "PHYSICAL_AUDIT_ROOT=\(temporaryRoot.path)",
            "--env", "PHYSICAL_RUN_ID=\(runID.uuidString.lowercased())",
            "--env", "PHYSICAL_RUN_ROOT=\(runRoot.path)",
            app.path,
            "--args",
            "--physical-helper-operation=\(operation)",
            "--physical-helper-operation-output=\(output.path)"
        ]
        let terminationStatus: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        guard terminationStatus == 0, FileManager.default.fileExists(atPath: output.path) else {
            throw PhysicalSignedAppOperationError.appInvocationFailed
        }
        let result = try JSONDecoder().decode(
            PhysicalSignedAppOperationResult.self,
            from: Data(contentsOf: output, options: [.uncached])
        )
        guard result.operation == operation else {
            throw PhysicalSignedAppOperationError.resultMismatch
        }
        guard result.succeeded else {
            throw PhysicalSignedAppOperationError.operationFailed(
                domain: result.errorDomain ?? "unknown",
                code: result.errorCode ?? -1
            )
        }
        return result
    }
}

enum PhysicalSignedAppOperationError: Error, Equatable {
    case appInvocationFailed
    case appUnavailable
    case authorizationMissing
    case operationFailed(domain: String, code: Int)
    case packageIdentityMismatch
    case resultMismatch
}
