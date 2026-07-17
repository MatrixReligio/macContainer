import XCTest

@MainActor
final class ResourceManagementTests: XCTestCase {
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

    func testEveryResourceDomainHasNativeTableAndSafeActions() {
        for route in [
            "containers", "images", "builds", "machines", "networks",
            "volumes", "registries", "system"
        ] {
            app.buttons["route.\(route)"].click()
            XCTAssertTrue(
                app.descendants(matching: .any)["resource-table.\(route)"].waitForExistence(timeout: 2),
                "Missing resource table for \(route)"
            )
            XCTAssertTrue(app.searchFields["resource-search.\(route)"].exists)
            XCTAssertTrue(app.buttons["refresh-resources.\(route)"].exists)
        }
    }

    func testSelectionSearchAndDestructiveConfirmationNameExactResource() {
        app.buttons["route.containers"].click()
        let search = app.searchFields["resource-search.containers"]
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.click()
        search.typeText("demo-web")

        let resource = app.staticTexts["demo-web"].firstMatch
        XCTAssertTrue(resource.waitForExistence(timeout: 2))
        resource.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["resource-detail-id"].waitForExistence(timeout: 2)
        )

        app.buttons["delete-selected.containers"].click()
        XCTAssertTrue(
            app.descendants(matching: .any)["destructive-confirmation"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.staticTexts["demo-web"].exists)
        XCTAssertTrue(app.staticTexts["This action permanently removes the selected container."].exists)
        app.buttons["cancel-destructive-action"].click()
    }
}
