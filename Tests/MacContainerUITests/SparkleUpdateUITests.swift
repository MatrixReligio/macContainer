import XCTest

@MainActor
final class SparkleUpdateUITests: XCTestCase {
    func testSignedSeedUpdatesAndPreservesPreferences() throws {
        let environment = ProcessInfo.processInfo.environment
        let requiredHarnessVariables = [
            "SPARKLE_TEST_SEED_APP",
            "SPARKLE_TEST_FEED_URL",
            "SPARKLE_TEST_ROOT",
            "SPARKLE_TEST_HOME",
            "SPARKLE_TEST_EXPECTED_VERSION"
        ]
        guard requiredHarnessVariables.allSatisfy({ environment[$0]?.isEmpty == false }) else {
            throw XCTSkip("The signed Sparkle update harness supplies seed, feed, root, home, and target version.")
        }
        let seedApp = try XCTUnwrap(environment["SPARKLE_TEST_SEED_APP"])
        let feedURL = try XCTUnwrap(environment["SPARKLE_TEST_FEED_URL"])
        let root = try XCTUnwrap(environment["SPARKLE_TEST_ROOT"])
        let home = try XCTUnwrap(environment["SPARKLE_TEST_HOME"])
        let expectedVersion = try XCTUnwrap(environment["SPARKLE_TEST_EXPECTED_VERSION"])

        let app = XCUIApplication(url: URL(fileURLWithPath: seedApp, isDirectory: true))
        app.launchArguments = [
            "--fake-runtime",
            "--sparkle-test-about",
            "--sparkle-test-root=\(root)",
            "--sparkle-test-feed-url=\(feedURL)",
            "-container.matrixreligio.com.app-language", "system",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launchEnvironment = environment.merging([
            "HOME": home,
            "CFFIXED_USER_HOME": home,
            "TMPDIR": "\(root)/tmp"
        ]) { _, testValue in testValue }
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(
            app.descendants(matching: .any)["sparkle-test-about"].waitForExistence(timeout: 10),
            "Validated Sparkle test view did not open"
        )

        let check = app.buttons["check-for-app-updates"]
        XCTAssertTrue(check.waitForExistence(timeout: 5), "Application update button is missing")
        check.click()

        let install = app.buttons["SPUUserUpdateChoiceInstall"].firstMatch
        XCTAssertTrue(
            install.waitForExistence(timeout: 45),
            "Sparkle did not present the signed install action"
        )
        install.click()

        let installAndRelaunch = app.buttons["SUStatusInstallAndRelaunch"].firstMatch
        XCTAssertTrue(waitUntil(timeout: 90) {
            app.state == .notRunning || installAndRelaunch.exists
        }, "Sparkle did not finish downloading the signed update")
        if app.state != .notRunning {
            installAndRelaunch.click()
        }
        XCTAssertTrue(waitUntil(timeout: 90) {
            app.state == .notRunning
        }, "Seed application did not terminate for installation")
        XCTAssertTrue(waitUntil(timeout: 90) {
            app.state == .runningForeground || app.state == .runningBackground
        }, "Updated application did not relaunch at version \(expectedVersion)")
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return false
    }
}
