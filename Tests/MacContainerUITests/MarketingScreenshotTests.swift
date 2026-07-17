import XCTest

@MainActor
final class MarketingScreenshotTests: XCTestCase {
    func testCaptureRequiresAnExplicitOutputDirectory() {
        let directory = ProcessInfo.processInfo.environment["MARKETING_SCREENSHOT_DIR"]
        XCTAssertTrue(directory == nil || directory?.isEmpty == true)
    }

    func testEnglishMarketingFixturesAreReadyForCapture() {
        for fixture in ["overview", "templates", "upgrade", "uninstall", "terminal", "error"] {
            let app = launch(fixture: fixture)
            XCTAssertTrue(
                app.descendants(matching: .any)["marketing.\(fixture).ready"]
                    .waitForExistence(timeout: 5),
                "Marketing fixture did not become ready: \(fixture)"
            )
            app.terminate()
        }
    }

    func testCaptureSixEnglishProductHuntScreenshots() {
        let cases = [
            ("overview", "01-overview"),
            ("templates", "02-scenario-templates"),
            ("upgrade", "03-compatible-upgrade"),
            ("uninstall", "04-complete-uninstall"),
            ("terminal", "05-terminal-safety"),
            ("error", "06-actionable-error")
        ]

        for (fixture, filename) in cases {
            let app = launch(fixture: fixture)
            XCTAssertTrue(
                app.descendants(matching: .any)["marketing.\(fixture).ready"]
                    .waitForExistence(timeout: 5),
                "Marketing fixture did not become ready: \(fixture)"
            )
            capture(filename, app: app)
            app.terminate()
        }
    }

    private func launch(fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--fake-runtime",
            "--reset-test-state",
            "--marketing-fixture=\(fixture)",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
        XCTAssertTrue(app.windows["main-window"].waitForExistence(timeout: 10))
        return app
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let screenshot = app.windows["main-window"].screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        let outputRequested = ProcessInfo.processInfo.environment["MARKETING_SCREENSHOT_DIR"]?
            .isEmpty == false
        attachment.lifetime = outputRequested ? .keepAlways : .deleteOnSuccess
        add(attachment)
    }
}
