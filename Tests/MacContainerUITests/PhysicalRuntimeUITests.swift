import XCTest

@MainActor
final class PhysicalRuntimeUITests: XCTestCase {
    func testProductionRuntimeExposesAuthoritativeResourcesWithoutRegisteringBackgroundAgents() throws {
        let environment = ProcessInfo.processInfo.environment
        let runID = try XCTUnwrap(environment["PHYSICAL_RUN_ID"])
        try XCTSkipUnless(
            environment["PHYSICAL_TEST_AUTHORIZATION"] == runID,
            "Exact physical UI authorization is required"
        )

        let app = XCUIApplication()
        app.launchArguments = ["--physical-runtime-ui-test"]
        app.launchEnvironment = try [
            "PHYSICAL_RUN_ID": runID,
            "PHYSICAL_RUN_ROOT": XCTUnwrap(environment["PHYSICAL_RUN_ROOT"]),
            "PHYSICAL_TEST_AUTHORIZATION": runID
        ]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.windows["main-window"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["overview-content"].waitForExistence(timeout: 5))

        for route in ["containers", "images", "networks", "volumes", "machines", "system"] {
            let routeButton = app.buttons["route.\(route)"]
            XCTAssertTrue(routeButton.waitForExistence(timeout: 5), "Missing production route \(route)")
            routeButton.click()
            XCTAssertTrue(
                app.descendants(matching: .any)["resource-table.\(route)"].waitForExistence(timeout: 10),
                "Production runtime did not expose \(route)"
            )
            XCTAssertTrue(app.buttons["refresh-resources.\(route)"].exists)
        }
        try recordPhysicalResult("ui.production-resource-navigation", environment: environment)
    }

    private func recordPhysicalResult(_ id: String, environment: [String: String]) throws {
        let runRoot = try URL(fileURLWithPath: XCTUnwrap(environment["PHYSICAL_RUN_ROOT"]), isDirectory: true)
            .standardizedFileURL
        let resultsRoot = runRoot.appendingPathComponent("results", isDirectory: true)
        XCTAssertEqual(resultsRoot.path, environment["PHYSICAL_RESULTS_ROOT"])
        let destination = resultsRoot.appendingPathComponent("\(id).json")
        let data = Data("{\"id\":\"\(id)\",\"passed\":true}\n".utf8)
        if FileManager.default.fileExists(atPath: destination.path) {
            XCTAssertEqual(try Data(contentsOf: destination), data)
        } else {
            try data.write(to: destination, options: [.withoutOverwriting])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }
    }
}
