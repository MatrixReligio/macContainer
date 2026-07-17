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
    }
}
