import XCTest

@MainActor
final class AutomaticUpdateUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--fake-runtime", "--reset-test-state", "--lifecycle-audit"]
        app.launch()
        XCTAssertTrue(app.windows["main-window"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["install-compatible-update"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testGuardedUpdateExposesPostflightRollbackAndRecoveryStates() {
        XCTAssertTrue(app.staticTexts["Compatible update: 1.1.0"].exists)
        app.buttons["install-compatible-update"].click()
        XCTAssertTrue(app.staticTexts["Upgrade installed; full compatibility postflight pending"].exists)

        app.buttons["simulate-upgrade-failure"].click()
        XCTAssertTrue(app.staticTexts["Compatibility failed — rolled back to 1.0.0"].exists)
        XCTAssertTrue(app.staticTexts["Failed compatibility probe: images"].exists)

        app.buttons["retry-runtime-update"].click()
        app.buttons["install-compatible-update"].click()
        app.buttons["simulate-update-recovery"].click()
        XCTAssertTrue(
            app.staticTexts[
                "Rollback could not restore a verified runtime — recovery required (rollback.previous-probes.run)"
            ].exists
        )
    }

    func testManualCheckNeverSkipsTheTypedCheckingState() {
        app.buttons["check-runtime-update"].click()
        XCTAssertTrue(app.staticTexts["Checking for reviewed runtime updates"].exists)
        app.buttons["complete-update-check"].click()
        XCTAssertTrue(app.staticTexts["Compatible update: 1.1.0"].exists)
    }
}
