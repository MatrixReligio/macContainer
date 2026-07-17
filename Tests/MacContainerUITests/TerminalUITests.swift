import XCTest

@MainActor
final class TerminalUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--fake-runtime", "--reset-test-state", "--terminal-audit"]
        app.launch()
        XCTAssertTrue(app.windows["main-window"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["terminal-session"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testTerminalIsContainedAccessibleAndDefaultsToSafeRemoteCapabilities() {
        XCTAssertTrue(app.staticTexts["Direct interactive session"].exists)
        XCTAssertTrue(app.staticTexts["Remote clipboard, links, notifications, and title changes are blocked."].exists)
        XCTAssertTrue(app.staticTexts["Reduced motion: terminal output updates without decorative animation."].exists)
        XCTAssertTrue(app.descendants(matching: .any)["swiftterm-surface"].exists)
        XCTAssertTrue(app.buttons["terminal-detach"].exists)
        XCTAssertTrue(app.buttons["terminal-terminate"].exists)
    }

    func testCloseOffersDetachAndTerminateWithoutLeakingTheSession() {
        app.buttons["terminal-detach"].click()
        XCTAssertTrue(app.staticTexts["Detached — workload keeps running"].exists)
        XCTAssertTrue(app.staticTexts["Reader task stopped"].exists)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["terminal-session"].waitForExistence(timeout: 5))
        app.buttons["terminal-terminate"].click()
        XCTAssertTrue(app.staticTexts["Terminated with SIGTERM"].exists)
        XCTAssertTrue(app.staticTexts["Reader task stopped"].exists)
    }
}
