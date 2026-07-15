# Native SwiftUI Application Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the complete HIG-aligned native SwiftUI interface, with every operation reachable, every affecting parameter validated and explained, safe templates, lifecycle UI, terminal sessions, settings, keyboard access, and accessibility.

**Architecture:** `MCAppCore` exposes main-actor observable feature models backed by injected bridge/lifecycle protocols. SwiftUI uses a three-column `NavigationSplitView`, reusable resource tables/details, contract-driven operation forms, and a single `ParameterHelpButton`; AppKit is isolated to a SwiftTerm `NSViewRepresentable` adapter.

**Tech Stack:** SwiftUI, Swift Observation, AppKit interop, SwiftTerm 1.13.0, Sparkle UI hooks, Swift Testing, XCTest/XCUITest, accessibility audits.

---

## File map

- Create: `Sources/MCAppCore/AppEnvironment.swift`, `AppState.swift`, `ActivityCenter.swift`, `OperationExecutor.swift`, `SettingsStore.swift`
- Create: `App/MacContainer/MacContainerApp.swift`, `Commands/MacContainerCommands.swift`
- Create: `App/MacContainer/Scenes/RootScene.swift`, `SettingsScene.swift`, `TerminalScene.swift`
- Create: `App/MacContainer/Views/Navigation/*`, `Overview/*`, `Resources/*`, `Operations/*`, `Templates/*`, `Lifecycle/*`, `Settings/*`, `Terminal/*`, `Shared/*`
- Create: `App/MacContainer/Resources/Assets.xcassets` and initial English string catalog
- Create: unit tests under `Tests/MCAppCoreTests`
- Create: UI tests under `Tests/MacContainerUITests`
- Modify: `docs/reviews/stage-5.md`
- Create: `docs/reviews/stage-6.md`

### Task 1: Build observable app state and a structured Activity Center

**Files:**
- Create: `Sources/MCModel/Activity.swift`
- Create: `Sources/MCAppCore/AppEnvironment.swift`
- Create: `Sources/MCAppCore/AppState.swift`
- Create: `Sources/MCAppCore/ActivityCenter.swift`
- Test: `Tests/MCAppCoreTests/ActivityCenterTests.swift`

- [ ] **Step 1: Write failing lifecycle/progress/cancellation tests**

```swift
import Testing
@testable import MCAppCore

@MainActor
@Suite("Activity Center")
struct ActivityCenterTests {
    @Test func activityPublishesStructuredProgressAndCompletion() async throws {
        let center = ActivityCenter()
        let id = center.start(titleKey: "activity.image.pull", cancellable: true)
        center.update(id, phaseKey: "activity.phase.downloading", completed: 50, total: 100)
        #expect(center.activities[id]?.progress == 0.5)
        #expect(center.activities[id]?.phaseKey == "activity.phase.downloading")
        center.finish(id, outcome: .succeeded)
        #expect(center.activities[id]?.outcome == .succeeded)
    }

    @Test func cancellationPropagatesToOwnedTask() async throws {
        let center = ActivityCenter()
        let cancelled = CancellationRecorder()
        let id = center.start(titleKey: "activity.build", cancellable: true) {
            await withTaskCancellationHandler { try? await Task.sleep(for: .seconds(30)) } onCancel: { cancelled.record() }
        }
        center.cancel(id)
        await cancelled.wait()
        #expect(cancelled.wasCancelled)
    }
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter ActivityCenterTests`

Expected: FAIL because Activity Center types are undefined.

- [ ] **Step 3: Implement observable state**

```swift
public struct ActivityRecord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let titleKey: String
    public var phaseKey: String
    public var completed: Int64?
    public var total: Int64?
    public var startedAt: Date
    public var outcome: ActivityOutcome?
    public var error: UserFacingError?
    public var isCancellable: Bool
    public var progress: Double? {
        guard let completed, let total, total > 0 else { return nil }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

@MainActor @Observable
public final class ActivityCenter {
    public private(set) var activities: [UUID: ActivityRecord] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    // start/update/finish/cancel remove task ownership deterministically.
}
```

`AppEnvironment` contains injected bridge, lifecycle manager, compatibility service, settings store, date/UUID providers, and fake/production modes. `AppState` owns selection, resource snapshots, global health, sheets, and Activity Center; all UI mutation occurs on the main actor.

- [ ] **Step 4: Run state tests**

Run: `swift test --filter MCAppCoreTests`

Expected: PASS including progress clamp, cancellation, retry, partial batch failure, elapsed time, and task cleanup.

- [ ] **Step 5: Commit**

```bash
git add Sources/MCModel/Activity.swift Sources/MCAppCore Tests/MCAppCoreTests
git commit -m "feat: orchestrate observable app activities"
```

### Task 2: Build the three-column root, sidebar, commands, and Overview

**Files:**
- Modify: `App/MacContainer/MacContainerApp.swift`
- Create: `App/MacContainer/Commands/MacContainerCommands.swift`
- Create: `App/MacContainer/Scenes/RootScene.swift`
- Create: `App/MacContainer/Views/Navigation/Sidebar.swift`
- Create: `App/MacContainer/Views/Overview/OverviewView.swift`
- Create: `App/MacContainer/Views/Shared/EmptyStateView.swift`
- Test: `Tests/MacContainerUITests/NavigationTests.swift`

- [ ] **Step 1: Write failing navigation/keyboard tests**

```swift
func testAllSidebarDomainsAndKeyboardNavigation() throws {
    let app = launchFakeRuntime()
    let sidebar = app.outlines["sidebar"]
    for id in ["overview", "containers", "images", "builds", "machines", "networks", "volumes", "registries", "system"] {
        XCTAssertTrue(sidebar.cells[id].exists, "missing sidebar item \(id)")
    }
    app.typeKey("2", modifierFlags: [.command])
    XCTAssertTrue(app.groups["containers-content"].waitForExistence(timeout: 2))
    app.typeKey("l", modifierFlags: [.command, .shift])
    XCTAssertTrue(app.windows["activity-center"].waitForExistence(timeout: 2))
}
```

- [ ] **Step 2: Run and verify RED**

Run: `xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerUITests/NavigationTests CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because navigation views are absent.

- [ ] **Step 3: Implement native navigation**

```swift
struct RootScene: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView(columnVisibility: $state.columnVisibility) {
            Sidebar(selection: $state.selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } content: {
            ResourceContent(selection: state.selection)
                .navigationSplitViewColumnWidth(min: 420, ideal: 620)
        } detail: {
            ResourceInspector(selection: state.detailSelection)
                .navigationSplitViewColumnWidth(min: 300, ideal: 380)
        }
        .frame(minWidth: 940, minHeight: 620)
        .accessibilityIdentifier("main-window")
    }
}
```

Use system sidebar styling, standard toolbar sidebar toggle, searchable content, `Commands` with Cmd-1...9 domain selection, Cmd-N context creation, Cmd-R refresh, Cmd-Shift-L Activity Center, and Settings. Overview shows installation/service/compatibility health, disk usage, running counts, pending activities, and contextual next actions without custom dashboard chrome.

- [ ] **Step 4: Run navigation and window-size tests**

Run: `xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerUITests/NavigationTests CODE_SIGNING_ALLOWED=NO test`

Expected: PASS at minimum window size, default size, and large accessibility text.

- [ ] **Step 5: Commit**

```bash
git add App/MacContainer Tests/MacContainerUITests/NavigationTests.swift
git commit -m "feat: add native MacContainer navigation"
```

### Task 3: Build reusable resource tables, inspectors, and safe actions

**Files:**
- Create: `App/MacContainer/Views/Resources/ResourceTable.swift`
- Create: one focused table and inspector file per containers, images, builds/builders, machines, networks, volumes, registries, system
- Create: `App/MacContainer/Views/Shared/DestructiveConfirmation.swift`
- Test: `Tests/MacContainerUITests/ResourceManagementTests.swift`

- [ ] **Step 1: Write failing table interaction tests**

Test every resource domain for search, sort, selection, detail display, context menu, keyboard delete/refresh, multi-selection where supported, empty state, structured partial failure, and destructive confirmation showing exact affected IDs.

- [ ] **Step 2: Run and verify RED**

Run: `xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerUITests/ResourceManagementTests CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because resource views are absent.

- [ ] **Step 3: Implement tables and inspectors using standard controls**

Each domain uses SwiftUI `Table`, native `searchable`, typed `SortOrder`, context menus, `Commands`, and inspectors with state/configuration/activity/log/metrics sections. Status includes text plus symbol, never color alone. Destructive confirmation has:

```swift
struct DestructiveConfirmation: View {
    let titleKey: LocalizedStringKey
    let resourceIDs: [String]
    let consequenceKey: LocalizedStringKey
    let recoveryKey: LocalizedStringKey?
    let confirm: @Sendable () async -> Void

    var body: some View {
        Form {
            Section { ForEach(resourceIDs, id: \.self) { Text($0).textSelection(.enabled) } }
            Section("confirmation.consequences") { Text(consequenceKey) }
            if let recoveryKey { Section("confirmation.recovery") { Text(recoveryKey) } }
        }
        .accessibilityIdentifier("destructive-confirmation")
    }
}
```

No view calls an upstream client directly; all actions enter `OperationExecutor`, acquire appropriate coordinator locks, create Activity records, and map errors.

- [ ] **Step 4: Run all resource tests**

Run: `xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerUITests/ResourceManagementTests CODE_SIGNING_ALLOWED=NO test`

Expected: PASS for every resource domain and partial failure case.

- [ ] **Step 5: Commit**

```bash
git add App/MacContainer/Views/Resources App/MacContainer/Views/Shared Tests/MacContainerUITests/ResourceManagementTests.swift Sources/MCAppCore
git commit -m "feat: manage every resource natively"
```

### Task 4: Build contract-driven operation forms and the universal information button

**Files:**
- Create: `App/MacContainer/Views/Operations/OperationForm.swift`
- Create: `App/MacContainer/Views/Operations/ParameterField.swift`
- Create: `App/MacContainer/Views/Operations/ParameterHelpButton.swift`
- Create: `App/MacContainer/Views/Operations/OperationReview.swift`
- Create: `Sources/MCAppCore/OperationExecutor.swift`
- Test: `Tests/MCAppCoreTests/OperationExecutorTests.swift`
- Test: `Tests/MacContainerUITests/ParameterFormTests.swift`

- [ ] **Step 1: Write failing contract-to-form parity tests**

```swift
func testEveryParameterHasFieldAndInformationButton() throws {
    let app = launchFakeRuntime(arguments: ["--contract-audit-mode"])
    for operation in ContractFixture110.operations {
        app.buttons["open-operation.\(operation.id)"].click()
        for parameter in operation.parameters {
            XCTAssertTrue(app.descendants(matching: .any)["parameter.\(operation.id).\(parameter.id)"].exists)
            let help = app.buttons["parameter-help.\(operation.id).\(parameter.id)"]
            XCTAssertTrue(help.exists)
            help.click()
            XCTAssertTrue(app.popovers["parameter-help-popover"].staticTexts[parameter.detailedHelpKey].exists)
            app.typeKey(.escape, modifierFlags: [])
        }
        app.typeKey(.escape, modifierFlags: [])
    }
}
```

- [ ] **Step 2: Run and verify RED**

Run: `xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerUITests/ParameterFormTests CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because form/help views are absent.

- [ ] **Step 3: Implement complete parameter rendering**

```swift
struct ParameterHelpButton: View {
    let operation: OperationContract
    let parameter: ParameterContract
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.plain)
        .help(Text(String(localized: String.LocalizationValue(parameter.conciseHelpKey))))
        .accessibilityLabel(Text(String(localized: String.LocalizationValue("parameter.help.accessibility"), defaultValue: "\(parameter.labelKey) information")))
        .accessibilityIdentifier("parameter-help.\(operation.id).\(parameter.id)")
        .popover(isPresented: $isPresented) {
            ParameterHelpPopover(operation: operation, parameter: parameter)
                .frame(idealWidth: 420)
                .accessibilityIdentifier("parameter-help-popover")
        }
    }
}
```

`ParameterField` exhaustively switches all `ParameterValueType` cases to native controls: Toggle, TextField, Stepper, duration/byte format fields, Picker, fileImporter, repeatable tables, port/mount editors, and signal/platform pickers. It displays inline validation and visible warnings for destructive/security-sensitive options. `OperationReview` shows generated values, provenance, diff, affected resources, and explicit Run/Cancel.

`OperationExecutor` maps each of 62 operation IDs to one typed bridge invocation and rejects unknown/disabled capabilities. List-format/quiet contract metadata maps to native sort/export choices, never terminal strings.

- [ ] **Step 4: Run executor, form parity, keyboard, and help tests**

Run:

```bash
swift test --filter OperationExecutorTests
xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerUITests/ParameterFormTests CODE_SIGNING_ALLOWED=NO test
```

Expected: PASS; every affecting parameter has exactly one field/help button, invalid input cannot execute, and Full Keyboard Access reaches help popovers.

- [ ] **Step 5: Commit**

```bash
git add App/MacContainer/Views/Operations Sources/MCAppCore/OperationExecutor.swift Tests/MCAppCoreTests/OperationExecutorTests.swift Tests/MacContainerUITests/ParameterFormTests.swift
git commit -m "feat: render complete explained operation forms"
```

### Task 5: Add approachable onboarding, Simple Mode, and template management

**Files:**
- Create: `App/MacContainer/Views/Templates/OnboardingView.swift`
- Create: `App/MacContainer/Views/Templates/SimpleModeView.swift`
- Create: `App/MacContainer/Views/Templates/TemplateReviewView.swift`
- Create: `App/MacContainer/Views/Templates/TemplateLibraryView.swift`
- Test: `Tests/MacContainerUITests/SimpleModeTests.swift`

- [ ] **Step 1: Write failing eight-template workflow tests**

For every built-in template, launch onboarding/fake host+image, fill only required user choices, inspect generated review rows/source labels/upstream diff, edit an advanced value, save/duplicate/export/import custom template, and execute through the fake bridge. Test secure, database, Rosetta, and nested-virtualization safeguards explicitly.

- [ ] **Step 2: Run and verify RED**

Run: `xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerUITests/SimpleModeTests CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because template UI is absent.

- [ ] **Step 3: Implement progressive disclosure**

Onboarding checks OS/chip/runtime status, introduces install without Terminal, explains auto-update consent, recommends Simple Mode, and never enables automatic runtime install without explicit toggle + helper authorization. Simple Mode shows scenario cards with plain-language outcome and risk, only required choices, then a fully editable review. Advanced mode is one control away and preserves draft values.

Template import uses `fileImporter`, decodes/migrates before showing preview, rejects secrets/future schema safely, and obtains no persistent security-scope permission after import. Export writes through `fileExporter` and proves no secrets.

- [ ] **Step 4: Run onboarding and template workflows**

Run: `xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerUITests/SimpleModeTests CODE_SIGNING_ALLOWED=NO test`

Expected: PASS for eight scenarios and all safeguard cases.

- [ ] **Step 5: Commit**

```bash
git add App/MacContainer/Views/Templates Tests/MacContainerUITests/SimpleModeTests.swift
git commit -m "feat: add safe Simple Mode workflows"
```

### Task 6: Add Runtime, update, compatibility, and uninstall settings UI

**Files:**
- Create: `App/MacContainer/Scenes/SettingsScene.swift`
- Create: `App/MacContainer/Views/Settings/GeneralSettingsView.swift`
- Create: `App/MacContainer/Views/Settings/RuntimeSettingsView.swift`
- Create: `App/MacContainer/Views/Settings/RuntimeUpdateSettingsView.swift`
- Create: `App/MacContainer/Views/Settings/CompatibilitySettingsView.swift`
- Create: `App/MacContainer/Views/Settings/DefaultsSettingsView.swift`
- Create: `App/MacContainer/Views/Settings/AdvancedSettingsView.swift`
- Create: `App/MacContainer/Views/Settings/AboutSettingsView.swift`
- Create: `App/MacContainer/Views/Lifecycle/InstallRuntimeView.swift`
- Create: `App/MacContainer/Views/Lifecycle/UninstallRuntimeView.swift`
- Test: `Tests/MacContainerUITests/RuntimeLifecycleUITests.swift`

- [ ] **Step 1: Write failing lifecycle UX tests**

Tests cover install trust summary/admin explanation, manual update, unknown-version hold, rollback history, helper authorization, complete-uninstall inventory/irreversibility, distinct preserve-data action, inaccessible residue, and exact “Uninstall incomplete” recovery details. Assert no UI claims success before postflight/audit.

- [ ] **Step 2: Run and verify RED**

Run: `xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerUITests/RuntimeLifecycleUITests CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because lifecycle settings are absent.

- [ ] **Step 3: Implement all settings panes and lifecycle presentations**

Use a standard macOS `Settings` scene with General, Runtime, Runtime Updates, Compatibility, Defaults & Templates, Advanced, and About tabs. Install view displays exact version/source/signer/disk impact/digest status before admin approval. Complete uninstall requires fresh inventory, a typed confirmation phrase localized by meaning but compared to a stable confirmation token, and displays every residue result. Preserve-data action uses different title, explanation, result model, and accessibility identifier.

- [ ] **Step 4: Run lifecycle UX tests**

Run: `xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerUITests/RuntimeLifecycleUITests CODE_SIGNING_ALLOWED=NO test`

Expected: PASS for success, partial failure, rollback, held update, and residue cases.

- [ ] **Step 5: Commit**

```bash
git add App/MacContainer/Scenes/SettingsScene.swift App/MacContainer/Views/Settings App/MacContainer/Views/Lifecycle Tests/MacContainerUITests/RuntimeLifecycleUITests.swift
git commit -m "feat: expose complete runtime lifecycle in settings"
```

### Task 7: Integrate direct interactive sessions through SwiftTerm

**Files:**
- Create: `App/MacContainer/Scenes/TerminalScene.swift`
- Create: `App/MacContainer/Views/Terminal/TerminalSessionView.swift`
- Create: `App/MacContainer/Views/Terminal/SwiftTermRepresentable.swift`
- Create: `App/MacContainer/Views/Terminal/PlainProcessOutputView.swift`
- Test: `Tests/MacContainerIntegrationTests/TerminalAdapterTests.swift`
- Test: `Tests/MacContainerUITests/TerminalUITests.swift`

- [ ] **Step 1: Write failing byte/resize/close tests**

Feed UTF-8, invalid UTF-8, ANSI control sequences, and 1 MiB output chunks through a fake `ProcessSession`; verify direct input bytes, debounced resize, safe clipboard behavior, reduced-motion presentation, detach/terminate close choices, stdout/stderr separation for non-TTY, and session task cleanup.

- [ ] **Step 2: Run and verify RED**

Run: `xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerIntegrationTests/TerminalAdapterTests -only-testing:MacContainerUITests/TerminalUITests CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because terminal views are absent.

- [ ] **Step 3: Implement isolated AppKit interop**

```swift
struct SwiftTermRepresentable: NSViewRepresentable {
    let session: any ProcessSession

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        context.coordinator.attach(to: view)
        return view
    }
    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {}
    static func dismantleNSView(_ view: LocalProcessTerminalView, coordinator: Coordinator) {
        coordinator.detachView()
    }
}
```

Coordinator sends bytes to `ProcessSession.send`, feeds `.terminal` bytes into SwiftTerm, debounces geometry to `resize`, and owns one structured reader task cancelled at dismantle. OSC clipboard/title requests and dangerous escape capabilities are disabled unless a reviewed safe subset is required.

- [ ] **Step 4: Run terminal integration/UI tests**

Run: `xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerIntegrationTests/TerminalAdapterTests -only-testing:MacContainerUITests/TerminalUITests CODE_SIGNING_ALLOWED=NO test`

Expected: PASS with no leaked task/file handle.

- [ ] **Step 5: Commit**

```bash
git add App/MacContainer/Scenes/TerminalScene.swift App/MacContainer/Views/Terminal Tests/MacContainerIntegrationTests/TerminalAdapterTests.swift Tests/MacContainerUITests/TerminalUITests.swift
git commit -m "feat: add direct interactive terminal sessions"
```

### Task 8: Implement structured localized errors and recovery actions

**Files:**
- Create: `Sources/MCModel/UserFacingError.swift`
- Create: `Sources/MCAppCore/ErrorMapper.swift`
- Create: `App/MacContainer/Views/Shared/ErrorPresentation.swift`
- Test: `Tests/MCAppCoreTests/ErrorMapperTests.swift`

- [ ] **Step 1: Write failing redaction/recovery tests**

```swift
@Test func mapsAuthenticationFailureWithoutSecret() {
    let raw = TestError("Authorization: Bearer abc; password=hunter2")
    let mapped = ErrorMapper().map(raw, domain: .registry, operationID: "registries.login")
    #expect(mapped.retryIsSafe)
    #expect(mapped.recoveryActions.map(\.id).contains("edit-credentials"))
    #expect(mapped.diagnosticDetail.contains("abc") == false)
    #expect(mapped.diagnosticDetail.contains("hunter2") == false)
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter ErrorMapperTests`

Expected: FAIL because mapper/types are absent.

- [ ] **Step 3: Implement errors and presentation**

`UserFacingError` contains domain, operation ID, title/explanation localization keys, redacted detail, safe-retry flag, concrete recovery actions, activity ID, and timestamp. `ErrorPresentation` uses an alert for immediate local errors and an inspector/activity detail for long-running/partial errors; batch results remain per-resource.

- [ ] **Step 4: Run error and diagnostic tests**

Run: `swift test --filter ErrorMapperTests`

Expected: PASS for credentials, environment variables, authorization headers, usernames, private paths, malformed upstream data, and helper failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/MCModel/UserFacingError.swift Sources/MCAppCore/ErrorMapper.swift App/MacContainer/Views/Shared/ErrorPresentation.swift Tests/MCAppCoreTests/ErrorMapperTests.swift
git commit -m "feat: present safe actionable errors"
```

### Task 9: Complete HIG, keyboard, VoiceOver, contrast, and accessibility automation

**Files:**
- Create: `Tests/MacContainerUITests/AccessibilityAuditTests.swift`
- Create: `Tests/MacContainerUITests/KeyboardNavigationTests.swift`
- Create: `Tests/MacContainerUITests/VisualAdaptationTests.swift`
- Create: `docs/reviews/stage-6.md`
- Modify: `docs/reviews/stage-5.md`

- [ ] **Step 1: Add failing accessibility audits for every major screen**

```swift
func testMajorScreensHaveNoAccessibilityAuditFailure() throws {
    let app = launchFakeRuntime(arguments: ["--accessibility-fixtures"])
    for route in MajorRoute.allCases {
        app.buttons["route.\(route.rawValue)"].click()
        try app.performAccessibilityAudit(for: [.all])
    }
}
```

Major routes include Overview, every resource table/detail, all creation/operation forms, eight template reviews, Activity Center, all Settings tabs, install/update/rollback/uninstall, terminal, and every error/recovery state.

- [ ] **Step 2: Run and verify RED**

Run: `xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerUITests/AccessibilityAuditTests CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL with concrete missing labels/contrast/hit-region issues before fixes.

- [ ] **Step 3: Fix and test accessibility behavior**

Ensure explicit labels/values/hints for custom status/help/progress/terminal controls, deterministic keyboard order, menu equivalents, no color-only status, textual phase, reduced motion, increased contrast, resizable layouts, 44-point practical hit targets where HIG calls for them, and native focus behavior. Do not suppress audit classes globally; document any OS-framework false positive with a minimal isolated reproduction and narrowly scoped assertion.

- [ ] **Step 4: Run Stage 5/6 UI gates**

```bash
xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerUITests CODE_SIGNING_ALLOWED=NO test
swift test --filter MCAppCoreTests
swift scripts/check-bridge-coverage.swift Sources/MCContracts/Resources/apple-container-1.1.0.json Config/contracts/apple-container-1.1.0-bridge-map.json
git diff --check
```

Expected: PASS and all 62 operations are reachable in the UI registry.

- [ ] **Step 5: Perform and record stage reviews**

Review functional coverage, error paths, HIG hierarchy, usability for a new user, advanced completeness, destructive safety, keyboard navigation, VoiceOver, large text, reduced motion, contrast, empty/loading/error states, terminal containment, and lifecycle truthfulness. Fix every finding and rerun.

```bash
git add docs/reviews/stage-5.md docs/reviews/stage-6.md
git commit -m "docs: close native experience reviews"
git push origin main
```

Expected: Stage 5 and Stage 6 both say `Gate: PASS` with no unresolved finding.

