import MCSystemLifecycle
import XCTest

final class UpdateAgentTests: XCTestCase {
    func testLaunchAgentUsesDailyBackgroundScheduleWithBackoff() throws {
        let data = try Data(contentsOf: sourceRoot
            .appending(path: "App/UpdateAgent/container.matrixreligio.com.update-agent.plist"))
        let value = try PropertyListSerialization.propertyList(from: data, format: nil)
        let plist = try XCTUnwrap(value as? [String: Any])

        XCTAssertEqual(plist["Label"] as? String, "container.matrixreligio.com.update-agent")
        XCTAssertEqual(plist["StartInterval"] as? Int, 86400)
        XCTAssertEqual(plist["ThrottleInterval"] as? Int, 900)
        XCTAssertEqual(plist["ProcessType"] as? String, "Background")
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, false)
        XCTAssertEqual(plist["LowPriorityIO"] as? Bool, true)
    }

    func testAgentHasNoPrivilegedEntitlement() throws {
        let data = try Data(contentsOf: sourceRoot.appending(path: "App/UpdateAgent/UpdateAgent.entitlements"))
        let value = try PropertyListSerialization.propertyList(from: data, format: nil)
        let entitlements = try XCTUnwrap(value as? [String: Any])

        XCTAssertNil(entitlements["com.apple.security.application-groups"])
        XCTAssertNil(entitlements["com.apple.security.temporary-exception.files.absolute-path.read-write"])
        XCTAssertNil(entitlements["com.apple.security.cs.disable-library-validation"])
    }

    func testUpdateAgentBuildSmokeDoesNotTouchRuntime() throws {
        let products = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        let executable = products.appending(path: "MacContainerUpdateAgent")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path))

        let process = Process()
        process.executableURL = executable
        process.arguments = ["--build-smoke-test"]
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, EXIT_SUCCESS)
    }

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
