import XCTest

@MainActor
final class VisualAdaptationTests: XCTestCase {
    func testCompactWindowKeepsPrimaryNavigationAndContentVisible() {
        let app = launch(arguments: ["--audit-compact-window"])
        defer { app.terminate() }

        let window = app.windows["main-window"]
        XCTAssertTrue(waitForWindow(window) { $0 <= 1000 })
        XCTAssertLessThanOrEqual(window.frame.width, 1000)
        XCTAssertGreaterThanOrEqual(window.frame.width, 940)
        XCTAssertTrue(app.buttons["audit.fixture.overview"].isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["audit.content.overview"].isHittable)
    }

    func testWideDarkHighContrastFixturePreservesReadableLifecycleActions() {
        let app = launch(
            arguments: ["--audit-wide-window"],
            environment: [
                "AppleInterfaceStyle": "Dark",
                "AppleIncreaseContrast": "1",
                "NSReduceMotion": "1"
            ]
        )
        defer { app.terminate() }

        let window = app.windows["main-window"]
        XCTAssertTrue(waitForWindow(window) { $0 >= 1400 })
        XCTAssertGreaterThanOrEqual(window.frame.width, 1400)
        let lifecycle = app.buttons["audit.fixture.lifecycle"]
        let navigation = app.descendants(matching: .any)["audit.fixture-navigation"]
        for _ in 0 ..< 15 where !lifecycle.isHittable {
            navigation.swipeUp()
        }
        XCTAssertTrue(lifecycle.isHittable)
        lifecycle.click()
        XCTAssertTrue(app.buttons["install-runtime"].isHittable)
        XCTAssertTrue(app.buttons["complete-uninstall"].exists)
        XCTAssertTrue(app.staticTexts["Fresh inventory: 15 owned artifact categories checked"].exists)
    }

    private func launch(
        arguments: [String],
        environment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--fake-runtime", "--reset-test-state", "--accessibility-fixtures"] + arguments
        app.launchEnvironment = environment
        app.launch()
        XCTAssertTrue(app.windows["main-window"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["accessibility-audit-ready"].waitForExistence(timeout: 5))
        return app
    }

    private func waitForWindow(
        _ window: XCUIElement,
        widthMatches: @escaping (CGFloat) -> Bool
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement else { return false }
                return widthMatches(element.frame.width)
            },
            object: window
        )
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }
}
