import XCTest

@MainActor
final class AccessibilityAuditTests: XCTestCase {
    func testOverviewAndEveryResourceFixturePassNativeAccessibilityAudit() throws {
        try withLaunchedApp { app in
            try audit(app: app, fixtures: [
                "overview", "containers", "images", "builds", "machines", "networks", "volumes",
                "registries", "system"
            ])
        }
    }

    func testOperationCatalogPassesNativeAccessibilityAudit() throws {
        try withLaunchedApp { try audit(app: $0, fixtures: ["operation"]) }
    }

    func testOperationFormPassesNativeAccessibilityAudit() throws {
        try withLaunchedApp { try audit(app: $0, fixtures: ["operation-form"]) }
    }

    func testTemplateAndActivityFixturesPassNativeAccessibilityAudit() throws {
        try withLaunchedApp { try audit(app: $0, fixtures: ["templates", "template-review", "activity"]) }
    }

    func testSettingsFixturesPassNativeAccessibilityAudit() throws {
        try withLaunchedApp { app in
            try audit(app: app, fixtures: [
                "settings",
                "settings-general", "settings-runtime", "settings-updates", "settings-compatibility"
            ])
        }
    }

    func testDefaultsAdvancedAndAboutSettingsPassNativeAccessibilityAudit() throws {
        try withLaunchedApp {
            try audit(app: $0, fixtures: ["settings-about", "settings-advanced", "settings-defaults"])
        }
    }

    func testLifecycleFixturePassesNativeAccessibilityAudit() throws {
        try withLaunchedApp { try audit(app: $0, fixtures: ["lifecycle"]) }
    }

    func testTerminalAndErrorFixturesPassNativeAccessibilityAudit() throws {
        try withLaunchedApp { try audit(app: $0, fixtures: ["terminal", "error"]) }
    }

    private func audit(app: XCUIApplication, fixtures: [String]) throws {
        for fixture in fixtures {
            let button = app.buttons["audit.fixture.\(fixture)"]
            XCTAssertTrue(button.waitForExistence(timeout: 3), "Missing audit fixture \(fixture)")
            let navigation = app.descendants(matching: .any)["audit.fixture-navigation"]
            for _ in 0 ..< 15 where !button.isHittable {
                navigation.swipeUp()
            }
            for _ in 0 ..< 15 where !button.isHittable {
                navigation.swipeDown()
            }
            XCTAssertTrue(button.isHittable, "Audit fixture is not reachable: \(fixture)")
            button.click()
            XCTAssertTrue(
                app.descendants(matching: .any)["audit.content.\(fixture)"].waitForExistence(timeout: 3),
                "Fixture did not become visible: \(fixture)"
            )
            try assertAuditPasses(app: app, fixture: fixture)
            if fixture == "templates" {
                let configure = app.buttons["template-section.configuration"]
                XCTAssertTrue(configure.waitForExistence(timeout: 3))
                configure.click()
                XCTAssertEqual(configure.value as? String, "Selected")
                try assertAuditPasses(app: app, fixture: "templates-configuration")
            }
            if fixture == "operation-form" {
                let scrollView = app.scrollViews["operation-form-scroll"]
                XCTAssertTrue(scrollView.exists)
                for _ in 0 ..< 5 {
                    scrollView.swipeUp()
                }
                try assertAuditPasses(app: app, fixture: "operation-form-middle")
                for _ in 0 ..< 20 where !app.descendants(matching: .any)["parameter.core.run.debug"].isHittable {
                    scrollView.swipeUp()
                }
                XCTAssertTrue(app.descendants(matching: .any)["parameter.core.run.debug"].isHittable)
                try assertAuditPasses(app: app, fixture: "operation-form-bottom")
            }
        }
    }

    private func assertAuditPasses(app: XCUIApplication, fixture: String) throws {
        var issues: [String] = []
        try app.performAccessibilityAudit(for: .all) { issue in
            let windowFrame = app.windows["main-window"].frame
            let elementFrame = issue.element?.frame ?? .infinite
            if self.shouldIgnore(
                issue,
                app: app,
                fixture: fixture,
                windowFrame: windowFrame,
                elementFrame: elementFrame
            ) {
                return true
            }
            issues.append(self.issueDescription(issue))
            return true
        }
        if issues.isEmpty == false {
            XCTFail(
                "Accessibility audit failed for \(fixture); main window \(app.windows["main-window"].frame):\n" +
                    issues.joined(separator: "\n")
            )
        }
    }

    private func shouldIgnore(
        _ issue: XCUIAccessibilityAuditIssue,
        app: XCUIApplication,
        fixture: String,
        windowFrame: CGRect,
        elementFrame: CGRect
    ) -> Bool {
        isFrameworkTouchBar(issue) ||
            isStructuralNavigationGroup(issue) ||
            isTemplateReviewHeader(issue, fixture: fixture, windowFrame: windowFrame, frame: elementFrame) ||
            isResourceTableCell(issue, app: app, fixture: fixture) ||
            isWindowRootGroup(issue, windowFrame: windowFrame, frame: elementFrame) ||
            isFrameworkTitlebar(issue, windowFrame: windowFrame, frame: elementFrame) ||
            isOffscreenContrastSample(issue, windowFrame: windowFrame, frame: elementFrame) ||
            isSidebarToggleIcon(issue)
    }

    /// XCTest on macOS 26 synthesizes an empty Touch Bar node even when the app
    /// declares no Touch Bar UI. Filter only that framework-owned node.
    private func isFrameworkTouchBar(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        issue.element?.elementType == .touchBar &&
            issue.element?.identifier.isEmpty != false &&
            issue.element?.label.isEmpty != false
    }

    /// NavigationSplitView exposes disabled, non-hittable structural AX groups.
    private func isStructuralNavigationGroup(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        issue.auditType == .sufficientElementDescription &&
            issue.element?.elementType == .group &&
            issue.element?.isEnabled == false &&
            issue.element?.isHittable == false &&
            isUndescribed(issue)
    }

    /// A SwiftUI List section header wraps its separately exposed text in an empty group.
    private func isTemplateReviewHeader(
        _ issue: XCUIAccessibilityAuditIssue,
        fixture: String,
        windowFrame: CGRect,
        frame: CGRect
    ) -> Bool {
        fixture == "template-review" &&
            (issue.auditType == .sufficientElementDescription || issue.auditType == .parentChild) &&
            issue.element?.elementType == .group &&
            issue.element?.isEnabled == false &&
            isUndescribed(issue) &&
            abs(frame.height - 28) <= 1 &&
            frame.width >= 700 &&
            windowFrame.contains(frame)
    }

    /// SwiftUI Table exposes an empty native-cell group alongside described cell text.
    private func isResourceTableCell(
        _ issue: XCUIAccessibilityAuditIssue,
        app: XCUIApplication,
        fixture: String
    ) -> Bool {
        Self.resourceFixtures.contains(fixture) &&
            issue.auditType == .sufficientElementDescription &&
            issue.element?.elementType == .group &&
            issue.element?.isEnabled == false &&
            isUndescribed(issue) &&
            (issue.element?.frame.height ?? .infinity) <= 24 &&
            app.outlines["resource-table.\(fixture)"].frame.contains(issue.element?.frame ?? .infinite)
    }

    /// SwiftUI contributes disabled root groups matching the main content region.
    private func isWindowRootGroup(
        _ issue: XCUIAccessibilityAuditIssue,
        windowFrame: CGRect,
        frame: CGRect
    ) -> Bool {
        issue.auditType == .sufficientElementDescription &&
            issue.element?.elementType == .group &&
            issue.element?.isEnabled == false &&
            isUndescribed(issue) &&
            abs(frame.minX - windowFrame.minX) <= 4 &&
            abs(frame.minY - windowFrame.minY) <= 4 &&
            abs(frame.width - windowFrame.width) <= 16 &&
            abs(frame.height - windowFrame.height) <= 12
    }

    /// The macOS 26 contrast audit samples the titlebar as synthetic static text.
    private func isFrameworkTitlebar(
        _ issue: XCUIAccessibilityAuditIssue,
        windowFrame: CGRect,
        frame: CGRect
    ) -> Bool {
        issue.auditType == .contrast &&
            issue.element?.elementType == .staticText &&
            isUndescribed(issue) &&
            abs(frame.minY - windowFrame.minY) <= 2 &&
            frame.height <= 52 &&
            frame.width >= windowFrame.width / 2
    }

    /// Offscreen SwiftUI text is audited again after the test scrolls it into view.
    private func isOffscreenContrastSample(
        _ issue: XCUIAccessibilityAuditIssue,
        windowFrame: CGRect,
        frame: CGRect
    ) -> Bool {
        issue.auditType == .contrast &&
            issue.element?.isHittable == false &&
            windowFrame.intersects(frame) == false
    }

    /// The sidebar toggle includes a private, empty 14-point icon group.
    private func isSidebarToggleIcon(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        issue.auditType == .parentChild &&
            issue.element?.elementType == .group &&
            issue.element?.isEnabled == false &&
            issue.element?.isHittable == false &&
            isUndescribed(issue) &&
            (issue.element?.frame.width ?? .infinity) <= 16 &&
            (issue.element?.frame.height ?? .infinity) <= 16
    }

    private func isUndescribed(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        issue.element?.identifier.isEmpty != false && issue.element?.label.isEmpty != false
    }

    private func issueDescription(_ issue: XCUIAccessibilityAuditIssue) -> String {
        let element = issue.element.map {
            "audit=\(issue.auditType.rawValue), identifier=\($0.identifier), label=\($0.label), " +
                "type=\($0.elementType.rawValue), frame=\($0.frame), " +
                "enabled=\($0.isEnabled), hittable=\($0.isHittable)"
        } ?? "no associated element"
        return "\(issue.compactDescription): \(element); \(issue.detailedDescription)"
    }

    private static let resourceFixtures: Set<String> = [
        "containers", "images", "builds", "machines",
        "networks", "volumes", "registries", "system"
    ]

    private func withLaunchedApp(_ body: (XCUIApplication) throws -> Void) rethrows {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fake-runtime", "--reset-test-state", "--accessibility-fixtures"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.windows["main-window"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["accessibility-audit-ready"].waitForExistence(timeout: 5))
        try body(app)
    }
}
