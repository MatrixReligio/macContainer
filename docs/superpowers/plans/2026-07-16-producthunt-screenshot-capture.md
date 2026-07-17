# Product Hunt Screenshot Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate and validate six English Product Hunt screenshots directly from deterministic macOS UI tests without capturing desktop or user data.

**Architecture:** A focused UI test launches fake-runtime marketing fixtures and captures only the identified app window. An explicit Scheme value retains named XCTest attachments; after the Runner exits, a shell driver exports those attachments from `.xcresult`, validates the six PNG files, generates a digest manifest, and removes all temporary test artifacts. This avoids granting the UI test Runner arbitrary-directory write access.

**Implementation note:** macOS TCC correctly rejected direct writes from the UI test Runner, so the implementation uses `.xcresult` attachment export. Two isolated driver runs completed successfully. Layout and content were stable; the user explicitly accepted pixel-only variance from native focus, toggle, and terminal cursor rendering, so identical SHA-256 output is not a release gate.

**Tech Stack:** Swift 6, XCTest/XCUITest, macOS 26 AppKit/SwiftUI, POSIX shell, `sips`, `shasum`, `xcodebuild`.

---

## File map

- Create `Tests/MacContainerUITests/MarketingScreenshotTests.swift`: deterministic English window capture scenarios and opt-in named attachment writer.
- Modify `App/MacContainer/Scenes/RootScene.swift`: route explicit fake-runtime marketing launch modes without changing production behavior.
- Create `App/MacContainer/Views/Shared/MarketingFixturesView.swift`: compose upgrade, uninstall, terminal, and recovery states without the audit navigation sidebar.
- Create `scripts/capture-producthunt-screenshots.sh`: isolated build/test runner, PNG validation, digest manifest, and cleanup trap.
- Create `docs/marketing/producthunt/README.md`: image order, suggested captions, regeneration command, privacy contract.
- Generate `docs/marketing/producthunt/screenshots/en/*.png` and `manifest.sha256` from the test runner.

### Task 1: Capture writer contract

**Files:**
- Create: `Tests/MacContainerUITests/MarketingScreenshotTests.swift`

- [x] **Step 1: Write the failing output-contract test**

```swift
func testCaptureRequiresAnExplicitOutputDirectory() {
    XCTAssertNil(ProcessInfo.processInfo.environment["MARKETING_SCREENSHOT_DIR"])
}
```

- [x] **Step 2: Run the focused test without an output directory**

Run:

```bash
xcodebuild -project MacContainer.xcodeproj -scheme MacContainer \
  -only-testing:MacContainerUITests/MarketingScreenshotTests/testCaptureRequiresAnExplicitOutputDirectory \
  test
```

Expected: PASS, proving ordinary UI runs cannot write marketing assets.

- [x] **Step 3: Add the window-only capture helper**

```swift
private func capture(_ name: String, app: XCUIApplication) throws {
    let screenshot = app.windows["main-window"].screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
    guard let directory = ProcessInfo.processInfo.environment["MARKETING_SCREENSHOT_DIR"] else { return }
    let output = URL(fileURLWithPath: directory, isDirectory: true)
        .appendingPathComponent("\(name).png")
    try FileManager.default.createDirectory(
        at: output.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try screenshot.pngRepresentation.write(to: output, options: .atomic)
}
```

- [x] **Step 4: Build the UI test target**

Run: `xcodebuild -quiet -project MacContainer.xcodeproj -scheme MacContainer build-for-testing`

Expected: exit 0 with no warning from `MarketingScreenshotTests.swift`.

- [x] **Step 5: Commit the capture helper**

```bash
git add Tests/MacContainerUITests/MarketingScreenshotTests.swift MacContainer.xcodeproj/project.pbxproj
git commit -m "test: add private window screenshot writer"
```

### Task 2: Marketing-only English fixtures

**Files:**
- Create: `App/MacContainer/Views/Shared/MarketingFixturesView.swift`
- Modify: `App/MacContainer/Scenes/RootScene.swift`
- Test: `Tests/MacContainerUITests/MarketingScreenshotTests.swift`

- [x] **Step 1: Write failing fixture-readiness assertions**

```swift
for fixture in ["overview", "templates", "upgrade", "uninstall", "terminal", "error"] {
    let app = launch(fixture: fixture)
    XCTAssertTrue(app.descendants(matching: .any)["marketing.\(fixture).ready"].waitForExistence(timeout: 5))
    app.terminate()
}
```

- [x] **Step 2: Run and verify RED**

Run: `xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerUITests/MarketingScreenshotTests test`

Expected: FAIL because the `--marketing-fixture` route and readiness identifiers do not exist.

- [x] **Step 3: Route explicit test-only fixtures**

Add to `RootScene` before other audit modes:

```swift
if let fixture = MarketingFixture.from(arguments: arguments), arguments.contains("--fake-runtime") {
    MarketingFixturesView(fixture: fixture)
} else if arguments.contains("--accessibility-fixtures") {
    AccessibilityAuditFixturesView()
}
```

`MarketingFixturesView` must expose `marketing.<fixture>.ready`, use only existing fake models, set a 1180×760 minimum presentation, and contain no audit navigation. The upgrade fixture shows the signed 1.1.0 candidate, compatibility-approved state, retained 1.0.0 rollback point, and automatic-install policy. The uninstall fixture shows typed confirmation and all 15 owned-artifact categories. The error fixture uses `registry.example.invalid` and the existing actionable error model.

- [x] **Step 4: Capture six named windows**

```swift
let cases = [
    ("overview", "01-overview"),
    ("templates", "02-scenario-templates"),
    ("upgrade", "03-compatible-upgrade"),
    ("uninstall", "04-complete-uninstall"),
    ("terminal", "05-terminal-safety"),
    ("error", "06-actionable-error")
]
for (fixture, filename) in cases {
    let app = launch(fixture: fixture)
    XCTAssertTrue(app.descendants(matching: .any)["marketing.\(fixture).ready"].waitForExistence(timeout: 5))
    try capture(filename, app: app)
    app.terminate()
}
```

- [x] **Step 5: Run and verify GREEN**

Run with `MARKETING_SCREENSHOT_DIR=/private/tmp/maccontainer-producthunt` and the normal manual-signing overrides.

Expected: PASS and exactly six valid PNG files in the explicit temporary output directory.

- [x] **Step 6: Commit fixtures and tests**

```bash
git add App/MacContainer/Scenes/RootScene.swift \
  App/MacContainer/Views/Shared/MarketingFixturesView.swift \
  Tests/MacContainerUITests/MarketingScreenshotTests.swift \
  MacContainer.xcodeproj/project.pbxproj
git commit -m "test: capture English product launch screens"
```

### Task 3: Reproducible asset driver and validation

**Files:**
- Create: `scripts/capture-producthunt-screenshots.sh`
- Create: `docs/marketing/producthunt/README.md`
- Generate: `docs/marketing/producthunt/screenshots/en/*.png`
- Generate: `docs/marketing/producthunt/screenshots/en/manifest.sha256`

- [x] **Step 1: Write the driver with an unconditional cleanup trap**

The script must resolve the repository root, use `${TMPDIR}/maccontainer-producthunt-$$` for DerivedData/result data, set `MARKETING_SCREENSHOT_DIR` only for the selected UI test, and install:

```bash
cleanup() {
  rm -rf "$temporary_root"
}
trap cleanup EXIT INT TERM
```

- [x] **Step 2: Validate the output contract**

For the six exact filenames, require `file` to report PNG, use `sips -g pixelWidth -g pixelHeight` to require width at least 1000 and height at least 620, reject any extra PNG, and write sorted SHA-256 lines with:

```bash
find "$output_dir" -maxdepth 1 -name '*.png' -print0 \
  | sort -z | xargs -0 shasum -a 256 > "$output_dir/manifest.sha256"
```

- [x] **Step 3: Document captions and privacy constraints**

The README maps each English filename to one short Product Hunt caption, records the regeneration command, and states that the fixtures use fake runtime data and window-only capture.

- [x] **Step 4: Run the driver twice and compare digests**

Run: `scripts/capture-producthunt-screenshots.sh` twice.

Expected: both runs exit 0 and produce the same six validated English views. The manifest records each final asset; pixel-only native-control variance is accepted.

- [x] **Step 5: Inspect all six PNG files**

Open each generated image with the local image viewer. Expected: no desktop pixels, audit sidebar, pointer, debug overlay, clipping, user path, or credential.

- [x] **Step 6: Commit final English assets**

```bash
git add scripts/capture-producthunt-screenshots.sh docs/marketing/producthunt
git commit -m "docs: add verified English Product Hunt screenshots"
```

## Self-review

- Spec coverage: six English-only key pages, deterministic capture, explicit output opt-in, privacy, validation, cleanup, documentation, and visual inspection are each mapped to a task.
- Placeholder scan: no TBD/TODO or unspecified implementation step remains.
- Type consistency: fixture names, readiness identifiers, output variable, filenames, and capture helper signatures match across all tasks.
