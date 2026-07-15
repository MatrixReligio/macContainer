import XCTest

final class BuildSmokeTests: XCTestCase {
    func testReleaseIdentityIsEmbedded() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "container.matrixreligio.com")
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String,
            "public.app-category.developer-tools"
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String,
            "Copyright 2026 MatrixReligio LLC. Licensed under Apache-2.0."
        )
    }
}
