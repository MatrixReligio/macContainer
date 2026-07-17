import XCTest

@MainActor
final class NavigationTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--fake-runtime", "--reset-test-state"]
        app.launch()
        XCTAssertTrue(app.windows["main-window"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testAllSidebarDomainsAndKeyboardNavigation() {
        for route in [
            "overview", "containers", "images", "builds", "machines",
            "networks", "volumes", "registries", "system"
        ] {
            XCTAssertTrue(app.buttons["route.\(route)"].exists, "Missing sidebar route \(route)")
        }

        app.typeKey("2", modifierFlags: [.command])
        XCTAssertTrue(app.groups["containers-content"].waitForExistence(timeout: 2))

        app.typeKey("l", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.windows["activity-center"].waitForExistence(timeout: 2))
    }

    func testOverviewExposesTruthfulHealthAndPrimaryAction() {
        XCTAssertTrue(app.descendants(matching: .any)["overview-content"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["runtime-health-value"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["compatibility-health-value"].exists)
        XCTAssertTrue(app.buttons["overview-primary-action"].exists)
    }
}
