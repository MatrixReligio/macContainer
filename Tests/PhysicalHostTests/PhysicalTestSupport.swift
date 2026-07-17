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
}
