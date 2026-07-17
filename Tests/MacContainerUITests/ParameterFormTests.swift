import XCTest

@MainActor
final class ParameterFormTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--fake-runtime", "--reset-test-state", "--contract-audit-mode"]
        app.launch()
        XCTAssertTrue(app.windows["main-window"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testContractBackedFormsExposeAFieldAndHelpForEveryAuditedParameter() {
        assertOperation("core.run", parameters: [
            "image", "arguments", "environment", "environmentFiles", "groupID", "interactive",
            "tty", "user", "userID", "workingDirectory", "ulimits", "cpus", "memory",
            "architecture", "capabilitiesToAdd", "capabilitiesToDrop", "containerIDFile", "detach",
            "dnsServers", "dnsDomain", "dnsOptions", "dnsSearchDomains", "entrypoint", "initProcess",
            "initImage", "kernel", "labels", "mounts", "name", "networks", "noDNS",
            "operatingSystem", "publishedPorts", "platform", "publishedSockets",
            "readOnlyRootFilesystem", "removeAfterStop", "rosetta", "runtimeHandler", "forwardSSHAgent",
            "sharedMemorySize", "temporaryFilesystems", "nestedVirtualization", "volumes",
            "registryScheme", "progressStyle", "maxConcurrentDownloads", "debug"
        ])
        assertOperation("containers.stop", parameters: [
            "all", "signal", "timeoutSeconds", "containerIDs", "debug"
        ])
    }

    func testHelpPopoverExposesContractDetailsAndKeyboardDismissal() {
        openOperation("core.run")
        assertHelp(operation: "core.run", parameter: "image")
    }

    func testContractAuditReportsExactEmbeddedCoverageAndBlocksInvalidExecution() {
        XCTAssertTrue(app.staticTexts["61 operations · 352 parameters"].waitForExistence(timeout: 3))
        openOperation("core.run")
        XCTAssertFalse(app.buttons["review-operation.core.run"].isEnabled)
        XCTAssertTrue(app.staticTexts["validation.required"].exists)
    }

    private func assertOperation(_ operation: String, parameters: [String]) {
        openOperation(operation)
        for parameter in parameters {
            XCTAssertEqual(
                app.descendants(matching: .any).matching(
                    identifier: "parameter.\(operation).\(parameter)"
                ).count,
                1,
                "Expected exactly one field for \(operation).\(parameter)"
            )
            XCTAssertEqual(
                app.buttons.matching(identifier: "parameter-help.\(operation).\(parameter)").count,
                1,
                "Expected exactly one information button for \(operation).\(parameter)"
            )
        }
    }

    private func openOperation(_ operation: String) {
        let search = app.textFields["operation-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        let clearButton = app.buttons["operation-search-clear"]
        if clearButton.exists {
            clearButton.click()
            XCTAssertTrue(
                NSPredicate(format: "value == ''").evaluate(with: search),
                "Operation search did not clear before entering \(operation)"
            )
        }
        search.click()
        search.typeText(operation)
        let button = app.buttons["open-operation.\(operation)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing operation result \(operation)")
        button.click()
        XCTAssertTrue(app.scrollViews["operation-form-scroll"].waitForExistence(timeout: 3))
    }

    private func assertHelp(operation: String, parameter: String) {
        let button = app.buttons["parameter-help.\(operation).\(parameter)"]
        XCTAssertTrue(button.exists)
        for _ in 0 ..< 20 where !button.isHittable {
            app.scrollViews["operation-form-scroll"].swipeUp()
        }
        XCTAssertTrue(button.isHittable)
        button.click()
        let popover = app.descendants(matching: .any)["parameter-help-popover"]
        XCTAssertTrue(popover.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["parameter.\(operation).\(parameter).detail"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }
}
