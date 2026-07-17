import XCTest

@MainActor
final class PhysicalRuntimeUITests: XCTestCase {
    func testProductionRuntimeExposesAuthoritativeResourcesWithoutRegisteringBackgroundAgents() throws {
        let environment = ProcessInfo.processInfo.environment
        let runID = try XCTUnwrap(environment["PHYSICAL_RUN_ID"])
        try XCTSkipUnless(
            environment["PHYSICAL_TEST_AUTHORIZATION"] == runID,
            "Exact physical UI authorization is required"
        )

        let app = XCUIApplication()
        app.launchArguments = ["--physical-runtime-ui-test"]
        app.launchEnvironment = try [
            "PHYSICAL_RUN_ID": runID,
            "PHYSICAL_RUN_ROOT": XCTUnwrap(environment["PHYSICAL_RUN_ROOT"]),
            "PHYSICAL_TEST_AUTHORIZATION": runID
        ]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.windows["main-window"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["overview-content"].waitForExistence(timeout: 5))

        for route in ["containers", "images", "networks", "volumes", "machines", "system"] {
            let routeButton = app.buttons["route.\(route)"]
            XCTAssertTrue(routeButton.waitForExistence(timeout: 5), "Missing production route \(route)")
            routeButton.click()
            let authoritativeInventory = app.descendants(matching: .any).matching(
                NSPredicate(
                    format: "identifier == %@ OR identifier == %@",
                    "resource-table.\(route)",
                    "resource-empty.\(route)"
                )
            ).firstMatch
            XCTAssertTrue(authoritativeInventory.waitForExistence(timeout: 10),
                          "Production runtime did not expose \(route)")
            XCTAssertFalse(app.descendants(matching: .any)["resource-error.\(route)"].exists,
                           "Production runtime reported an error for \(route)")
            XCTAssertTrue(app.buttons["refresh-resources.\(route)"].exists)
        }
        try recordPhysicalResult("ui.production-resource-navigation", environment: environment)
    }

    func testProductionRuntimePassesFiveLanguageAccessibilityCoverage() throws {
        let environment = try authorizedEnvironment()
        let languageCoverage = [
            (language: "en", label: "Overview", resultID: "ui.production-language-en-accessibility"),
            (language: "zh-Hans", label: "概览", resultID: "ui.production-language-zh-Hans-accessibility"),
            (language: "zh-Hant", label: "概覽", resultID: "ui.production-language-zh-Hant-accessibility"),
            (language: "ja", label: "概要", resultID: "ui.production-language-ja-accessibility"),
            (language: "ko", label: "개요", resultID: "ui.production-language-ko-accessibility")
        ]
        let routes = [
            "overview", "containers", "images", "builds", "machines",
            "networks", "volumes", "registries", "system"
        ]

        for coverage in languageCoverage {
            let language = coverage.language
            let app = try launchProductionApp(language: language, environment: environment)
            defer { app.terminate() }

            let overview = app.buttons["route.overview"]
            XCTAssertTrue(overview.waitForExistence(timeout: 5), "Missing overview in \(language)")
            XCTAssertEqual(overview.label, coverage.label)

            for route in routes {
                let routeButton = app.buttons["route.\(route)"]
                XCTAssertTrue(routeButton.waitForExistence(timeout: 5), "Missing \(route) in \(language)")
                routeButton.click()
                let contentIdentifier = route == "overview" ? "overview-content" : "\(route)-content"
                XCTAssertTrue(
                    app.descendants(matching: .any)[contentIdentifier].waitForExistence(timeout: 10),
                    "Missing \(route) content in \(language)"
                )
                try assertProductionAccessibilityAuditPasses(
                    app: app,
                    language: language,
                    route: route
                )
            }

            try recordPhysicalResult(coverage.resultID, environment: environment)
            app.terminate()
        }
    }

    private func authorizedEnvironment() throws -> [String: String] {
        let environment = ProcessInfo.processInfo.environment
        let runID = try XCTUnwrap(environment["PHYSICAL_RUN_ID"])
        try XCTSkipUnless(
            environment["PHYSICAL_TEST_AUTHORIZATION"] == runID,
            "Exact physical UI authorization is required"
        )
        return environment
    }

    private func launchProductionApp(
        language: String,
        environment: [String: String]
    ) throws -> XCUIApplication {
        let runID = try XCTUnwrap(environment["PHYSICAL_RUN_ID"])
        let app = XCUIApplication()
        app.launchArguments = [
            "--physical-runtime-ui-test",
            "--physical-runtime-language=\(language)"
        ]
        app.launchEnvironment = try [
            "PHYSICAL_RUN_ID": runID,
            "PHYSICAL_RUN_ROOT": XCTUnwrap(environment["PHYSICAL_RUN_ROOT"]),
            "PHYSICAL_TEST_AUTHORIZATION": runID
        ]
        app.launch()
        XCTAssertTrue(app.windows["main-window"].waitForExistence(timeout: 15))
        return app
    }

    private func assertProductionAccessibilityAuditPasses(
        app: XCUIApplication,
        language: String,
        route: String
    ) throws {
        var issues: [String] = []
        try app.performAccessibilityAudit(for: .all) { issue in
            if self.isKnownFrameworkAccessibilityArtifact(issue, app: app, route: route) {
                return true
            }
            let element = issue.element.map {
                "identifier=\($0.identifier), label=\($0.label), type=\($0.elementType.rawValue), frame=\($0.frame)"
            } ?? "no associated element"
            issues.append("\(issue.compactDescription): \(element)")
            return true
        }
        XCTAssertTrue(
            issues.isEmpty,
            "Production accessibility audit failed for \(language)/\(route):\n\(issues.joined(separator: "\n"))"
        )
    }

    private func isKnownFrameworkAccessibilityArtifact(
        _ issue: XCUIAccessibilityAuditIssue,
        app: XCUIApplication,
        route: String
    ) -> Bool {
        let element = issue.element
        let frame = element?.frame ?? .infinite
        let windowFrame = app.windows["main-window"].frame
        let isUndescribed = element?.identifier.isEmpty != false && element?.label.isEmpty != false

        let touchBar = element?.elementType == .touchBar && isUndescribed
        let structuralGroup = issue.auditType == .sufficientElementDescription &&
            element?.elementType == .group && element?.isEnabled == false && isUndescribed
        let titlebar = issue.auditType == .contrast && element?.elementType == .staticText &&
            isUndescribed && abs(frame.minY - windowFrame.minY) <= 2 && frame.height <= 52
        let offscreenContrast = issue.auditType == .contrast && element?.isHittable == false &&
            windowFrame.intersects(frame) == false
        let sidebarIcon = issue.auditType == .parentChild && element?.elementType == .group &&
            element?.isEnabled == false && element?.isHittable == false && isUndescribed &&
            frame.width <= 16 && frame.height <= 16
        let resourceTable = app.outlines["resource-table.\(route)"]
        let resourceTableCell = route != "overview" && resourceTable.exists &&
            issue.auditType == .sufficientElementDescription &&
            element?.elementType == .group && element?.isEnabled == false && isUndescribed &&
            frame.height <= 24 && resourceTable.frame.contains(frame)

        return touchBar || structuralGroup || titlebar || offscreenContrast || sidebarIcon || resourceTableCell
    }

    private func recordPhysicalResult(_ id: String, environment: [String: String]) throws {
        let runID = try XCTUnwrap(environment["PHYSICAL_RUN_ID"])
        let requestedRoot = try URL(
            fileURLWithPath: XCTUnwrap(environment["PHYSICAL_RESULTS_ROOT"]),
            isDirectory: true
        )
        .standardizedFileURL
        let expectedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("maccontainer-physical-results-\(runID)", isDirectory: true)
            .standardizedFileURL
        let resultsRoot = try XCTUnwrap(
            requestedRoot == expectedRoot ? requestedRoot : nil,
            "Physical UI results must remain inside the test runner sandbox"
        )
        if FileManager.default.fileExists(atPath: resultsRoot.path) == false {
            try FileManager.default.createDirectory(
                at: resultsRoot,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        }
        let destination = resultsRoot.appendingPathComponent("\(id).json")
        let data = Data("{\"id\":\"\(id)\",\"passed\":true}\n".utf8)
        if FileManager.default.fileExists(atPath: destination.path) {
            XCTAssertEqual(try Data(contentsOf: destination), data)
        } else {
            try data.write(to: destination, options: [.withoutOverwriting])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }
    }
}
