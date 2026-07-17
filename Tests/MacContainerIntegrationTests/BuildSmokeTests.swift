import XCTest

final class BuildSmokeTests: XCTestCase {
    func testReleaseIdentityIsEmbedded() throws {
        let applicationBundle = try XCTUnwrap(builtApplicationBundle())
        let infoData = try Data(contentsOf: applicationBundle.bundleURL
            .appending(path: "Contents/Info.plist"))
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
        )
        XCTAssertEqual(applicationBundle.bundleIdentifier, "container.matrixreligio.com")
        XCTAssertEqual(
            info["LSApplicationCategoryType"] as? String,
            "public.app-category.developer-tools"
        )
        XCTAssertEqual(
            info["NSHumanReadableCopyright"] as? String,
            "Copyright 2026 MatrixReligio LLC. Licensed under Apache-2.0."
        )
        XCTAssertEqual(
            info["CFBundleIconName"] as? String,
            "AppIcon"
        )
    }

    private func builtApplicationBundle() -> Bundle? {
        let testBundle = Bundle(for: Self.self).bundleURL
        return Bundle(url: testBundle.deletingLastPathComponent().appendingPathComponent("MacContainer.app"))
    }
}
