import XCTest

@MainActor
final class SimpleModeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--fake-runtime", "--reset-test-state", "--simple-mode-audit"]
        app.launch()
        XCTAssertTrue(app.windows["main-window"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["simple-mode"].waitForExistence(timeout: 5))
    }

    override func tearDown() async throws {
        app.terminate()
        app = nil
    }

    func testAllEightBuiltInScenariosAreAvailableWithSafePlainLanguageDefaults() {
        for template in [
            "quick-run", "interactive-shell", "web-service", "development-workspace",
            "local-database", "restricted-secure", "cross-architecture", "linux-machine-workspace"
        ] {
            XCTAssertEqual(app.buttons.matching(identifier: "template.\(template)").count, 1)
        }

        app.buttons["template.quick-run"].click()
        XCTAssertTrue(app.textFields["template-choice.image"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.textFields["template-choice.image"].value as? String, "alpine:latest")
        XCTAssertTrue(app.buttons["template-review"].isEnabled)
    }

    func testEveryScenarioProducesTransparentEditableReview() {
        for template in [
            "quick-run", "interactive-shell", "web-service", "development-workspace",
            "local-database", "restricted-secure", "cross-architecture", "linux-machine-workspace"
        ] {
            app.buttons["template.\(template)"].click()
            let review = app.buttons["template-review"]
            XCTAssertTrue(review.waitForExistence(timeout: 2), "Missing review for \(template)")
            XCTAssertTrue(review.isEnabled, "Invalid safe defaults for \(template)")
            review.click()
            XCTAssertTrue(app.buttons["template-run"].waitForExistence(timeout: 2))
            XCTAssertTrue(app.staticTexts["Review \(template)"].exists)
            XCTAssertTrue(app.staticTexts["value.source.user"].exists)
            app.buttons["template-review-back"].click()
        }
    }

    func testSecurityDatabaseRosettaAndVirtualizationSafeguardsAreExplicit() {
        app.buttons["template.restricted-secure"].click()
        XCTAssertTrue(app.staticTexts["Read-only root filesystem"].exists)
        XCTAssertTrue(app.staticTexts["Network and DNS disabled"].exists)

        app.buttons["template.local-database"].click()
        XCTAssertTrue(app.staticTexts["Persistent data: maccontainer-data"].exists)
        XCTAssertTrue(app.staticTexts["Graceful stop: 30 seconds"].exists)

        app.buttons["template.cross-architecture"].click()
        XCTAssertTrue(app.staticTexts["Rosetta is required and will be checked before run."].exists)

        app.buttons["template.linux-machine-workspace"].click()
        XCTAssertTrue(app.staticTexts["Home sharing: Off · Nested virtualization: Off"].exists)
        app.switches["consent.home-sharing"].click()
        XCTAssertTrue(app.staticTexts["Home sharing: On · Nested virtualization: Off"].exists)
        app.switches["consent.home-sharing"].click()
        XCTAssertTrue(app.staticTexts["Home sharing: Off · Nested virtualization: Off"].exists)
    }

    func testAdvancedModePreservesChoicesAndLibraryActionsAreReachable() {
        app.buttons["template.quick-run"].click()
        let image = app.textFields["template-choice.image"]
        image.click()
        image.typeKey("a", modifierFlags: [.command])
        image.typeText("example/custom")

        let advanced = app.buttons["template-advanced"]
        for _ in 0 ..< 8 where !advanced.isHittable {
            app.scrollViews["template-configuration-scroll"].swipeUp()
        }
        advanced.click()
        XCTAssertEqual(image.value as? String, "example/custom")
        XCTAssertTrue(app.staticTexts["Generated values remain fully editable in review."].exists)

        app.buttons["manage-templates"].click()
        XCTAssertTrue(app.staticTexts["Template Library"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["import-template"].exists)
        XCTAssertTrue(app.buttons["export-template"].exists)
        XCTAssertTrue(app.buttons["duplicate-template"].exists)
        app.buttons["template-library-done"].click()
    }

    func testOnboardingRequiresExplicitAutomaticInstallConsent() {
        app.terminate()
        app.launchArguments = ["--fake-runtime", "--reset-test-state", "--onboarding-mode"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["onboarding"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["macOS 26 · Apple silicon · Runtime ready"].exists)
        XCTAssertTrue(app.staticTexts["Current automatic install setting: Off"].exists)
        app.switches["onboarding.auto-install"].click()
        XCTAssertTrue(app.staticTexts["Current automatic install setting: On"].exists)
        app.switches["onboarding.auto-install"].click()
        XCTAssertTrue(app.staticTexts["Current automatic install setting: Off"].exists)
        XCTAssertTrue(app.staticTexts["Automatic installation is off until you opt in."].exists)
    }
}
