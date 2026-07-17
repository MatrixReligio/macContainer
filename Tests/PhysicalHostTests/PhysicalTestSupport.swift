import Darwin
import Foundation
import MCContainerBridge

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
        guard isAuthorized, let runRoot else {
            throw PhysicalTestGateError.authorizationMissing
        }
        let resultsRoot = runRoot.appendingPathComponent("results", isDirectory: true)
        guard resultsRoot.path == environment["PHYSICAL_RESULTS_ROOT"],
              FileManager.default.fileExists(atPath: resultsRoot.path)
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
