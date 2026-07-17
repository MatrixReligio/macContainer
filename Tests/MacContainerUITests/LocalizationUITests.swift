import XCTest

@MainActor
final class LocalizationUITests: XCTestCase {
    func testSidebarUsesRequestedLanguage() {
        let expectedByLanguage = [
            "en": "Overview",
            "zh-Hans": "概览",
            "zh-Hant": "概覽",
            "ja": "概要",
            "ko": "개요"
        ]
        let requested = Locale.preferredLanguages.first ?? "en"
        let language = expectedByLanguage.keys.first(where: { requested.hasPrefix($0) }) ?? "en"

        let app = XCUIApplication()
        app.launchArguments = [
            "--fake-runtime",
            "--reset-test-state",
            "-container.matrixreligio.com.app-language",
            "system",
            "-AppleLanguages",
            "(\(language))",
            "-AppleLocale",
            language
        ]
        app.launch()

        XCTAssertTrue(app.windows["main-window"].waitForExistence(timeout: 10))
        let overview = app.buttons["route.overview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        XCTAssertEqual(overview.label, expectedByLanguage[language])
        app.terminate()
    }
}
