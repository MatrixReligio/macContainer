import XCTest

@MainActor
final class KeyboardNavigationTests: XCTestCase {
    func testFixtureNavigationHasDeterministicKeyboardOrderAndEscapeRecovery() {
        let app = launch()
        defer { app.terminate() }
        let first = app.buttons["audit.fixture.overview"]
        first.click()

        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["audit.content.containers"].waitForExistence(timeout: 2))

        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["audit.content.overview"].waitForExistence(timeout: 2))

        app.buttons["audit.fixture.operation"].click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["audit.content.operation"].exists)
    }

    func testApplicationMenuShortcutsRemainReachableWithoutPointerInput() {
        let app = launch()
        defer { app.terminate() }
        app.typeKey("2", modifierFlags: [.command])
        XCTAssertTrue(app.descendants(matching: .any)["audit.content.containers"].waitForExistence(timeout: 2))

        app.typeKey("l", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.windows["activity-center"].waitForExistence(timeout: 2))
        app.typeKey("w", modifierFlags: [.command])
        XCTAssertFalse(app.windows["activity-center"].exists)
    }

    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fake-runtime", "--reset-test-state", "--accessibility-fixtures"]
        app.launch()
        XCTAssertTrue(app.windows["main-window"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["accessibility-audit-ready"].waitForExistence(timeout: 5))
        return app
    }
}
