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
}

enum PhysicalTestGateError: Error {
    case authorizationMissing
    case packageMissing
    case packageOutsideRunRoot
    case unreviewedPackageVersion
}
