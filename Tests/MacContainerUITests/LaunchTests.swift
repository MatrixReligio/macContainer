import XCTest

final class LaunchTests: XCTestCase {
    func testApplicationLaunchesInFakeRuntimeMode() {
        let app = XCUIApplication()
        app.launchArguments = ["--fake-runtime", "--reset-test-state"]
        app.launch()

        let mainWindow = app.windows["main-window"]
        guard mainWindow.waitForExistence(timeout: 10) else {
            XCTFail("Main window was not exposed to accessibility.\n\(app.debugDescription)")
            return
        }
    }
}
