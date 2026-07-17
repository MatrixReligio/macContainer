import XCTest

@MainActor
final class RuntimeLifecycleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--fake-runtime", "--reset-test-state", "--lifecycle-audit"]
        app.launch()
        XCTAssertTrue(app.windows["main-window"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["runtime-lifecycle"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testInstallShowsVerifiedTrustAndNeverClaimsSuccessBeforePostflight() {
        XCTAssertTrue(app.staticTexts["Apple container 1.1.0"].exists)
        XCTAssertTrue(app.staticTexts["Source: developer.apple.com"].exists)
        XCTAssertTrue(app.staticTexts["Signer: Apple Inc. - Containerization (UPBK2H6LZM)"].exists)
        XCTAssertTrue(app.staticTexts["SHA-256 digest verified"].exists)
        XCTAssertTrue(app.staticTexts["Disk impact: up to 420 MB"].exists)
        XCTAssertTrue(app.staticTexts["Administrator approval is requested only when installation begins."].exists)

        app.buttons["install-runtime"].click()
        XCTAssertTrue(app.staticTexts["Installing — compatibility postflight pending"].exists)
        XCTAssertFalse(app.staticTexts["Runtime ready"].exists)

        app.buttons["simulate-install-postflight"].click()
        XCTAssertTrue(app.staticTexts["Runtime ready"].exists)
    }

    func testManualUpdateUnknownVersionHoldAndRollbackAreExplicit() {
        XCTAssertTrue(app.staticTexts["Compatible update: 1.1.0"].exists)
        XCTAssertTrue(app.staticTexts["Unknown version 1.2.0 is held — no automatic install"].exists)
        XCTAssertTrue(app.buttons["check-runtime-update"].exists)
        XCTAssertTrue(app.buttons["install-compatible-update"].exists)
        XCTAssertTrue(app.staticTexts["Rollback point: 1.0.0 · verified · retained"].exists)

        app.buttons["install-compatible-update"].click()
        XCTAssertTrue(app.staticTexts["Upgrade installed; full compatibility postflight pending"].exists)
        XCTAssertFalse(app.staticTexts["Upgrade complete"].exists)

        app.buttons["simulate-upgrade-failure"].click()
        XCTAssertTrue(app.staticTexts["Compatibility failed — rolled back to 1.0.0"].exists)
        XCTAssertTrue(app.buttons["retry-runtime-update"].exists)
    }

    func testCompleteUninstallUsesFreshInventoryTypedConfirmationAndRecoveryDetails() {
        for kind in [
            "launchService", "process", "receipt", "receiptPayload", "applicationSupport",
            "configuration", "defaultsDomain", "registryCredential", "resolver", "packetFilter",
            "downloadedPackage", "rollbackPoint", "testFixture", "downloadCache", "runtimeOwnedDirectory"
        ] {
            XCTAssertTrue(app.descendants(matching: .any)["residue.\(kind)"].exists, "Missing residue kind \(kind)")
        }

        XCTAssertTrue(app.staticTexts["Fresh inventory: 15 owned artifact categories checked"].exists)
        let irreversible = "This permanently removes runtime data, credentials, caches, and rollback points."
        XCTAssertTrue(app.staticTexts[irreversible].exists)
        XCTAssertFalse(app.buttons["complete-uninstall"].isEnabled)

        let confirmation = app.textFields["complete-uninstall-confirmation"]
        confirmation.click()
        confirmation.typeText("REMOVE")
        confirmation.typeKey(.space, modifierFlags: [])
        confirmation.typeText("APPLE")
        confirmation.typeKey(.space, modifierFlags: [])
        confirmation.typeText("CONTAINER")
        confirmation.typeKey(.tab, modifierFlags: [])
        XCTAssertEqual(confirmation.value as? String, "REMOVE APPLE CONTAINER")
        let completeButton = app.buttons["complete-uninstall"]
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: completeButton)
        waitForExpectations(timeout: 2)
        completeButton.click()

        XCTAssertTrue(app.staticTexts["Uninstall incomplete"].exists)
        XCTAssertFalse(app.staticTexts["Uninstall complete"].exists)
        XCTAssertTrue(app.staticTexts["Could not verify resolver cleanup"].exists)
        XCTAssertTrue(app.staticTexts["Recovery: retry the residue audit after restoring administrator access."].exists)
    }

    func testPreserveDataIsASeparateNonDestructiveAction() {
        XCTAssertTrue(app.buttons["preserve-data-uninstall"].exists)
        XCTAssertTrue(app.staticTexts["Remove runtime, preserve container data"].exists)
        XCTAssertTrue(app.staticTexts["Keeps images, volumes, configuration, and registry credentials."].exists)
        XCTAssertFalse(app.buttons["complete-uninstall"].isEnabled)

        app.buttons["preserve-data-uninstall"].click()
        XCTAssertTrue(app.staticTexts["Runtime removed; user data preserved"].exists)
        XCTAssertFalse(app.staticTexts["Uninstall complete"].exists)
    }
}
