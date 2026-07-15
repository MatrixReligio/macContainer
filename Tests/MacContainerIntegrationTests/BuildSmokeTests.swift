import XCTest

final class BuildSmokeTests: XCTestCase {
    func testReleaseIdentityIsEmbedded() throws {
        let applicationBundle = try XCTUnwrap(builtApplicationBundle())
        XCTAssertEqual(applicationBundle.bundleIdentifier, "container.matrixreligio.com")
        XCTAssertEqual(
            applicationBundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String,
            "public.app-category.developer-tools"
        )
        XCTAssertEqual(
            applicationBundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String,
            "Copyright 2026 MatrixReligio LLC. Licensed under Apache-2.0."
        )
        XCTAssertEqual(
            applicationBundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String,
            "AppIcon"
        )
    }

    private func builtApplicationBundle() -> Bundle? {
        let testBundle = Bundle(for: Self.self).bundleURL
        return Bundle(url: testBundle.deletingLastPathComponent().appendingPathComponent("MacContainer.app"))
    }
}
