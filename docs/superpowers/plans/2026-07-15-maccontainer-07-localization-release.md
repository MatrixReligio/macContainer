# Localization Documentation and Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship complete five-language UI/help and key documentation, dependency/license evidence, reproducible CI, signed/notarized distribution, Sparkle application updates, SBOM, and a verified public GitHub release.

**Architecture:** An English string catalog is authoritative and parity scripts require all four translations for every key. English documents carry stable section IDs/source revisions mirrored in translated trees. Release scripts reuse the proven GameMaster certificate/notarization secret contract but use MacContainer-specific identifiers and EdDSA key, signing helper/agent/framework/app inside-out before notarization and asset publication.

**Tech Stack:** String Catalogs, SwiftUI localization, XCTest/XCUITest, Markdown, SPDX/CycloneDX, XcodeGen, codesign, notarytool, hdiutil, Sparkle 2.9.4, GitHub Actions/CLI.

---

## File map

- Create: `App/MacContainer/Resources/Localizable.xcstrings`, `InfoPlist.xcstrings`
- Create: `Sources/MCAppCore/AppLanguage.swift`, `LanguageController.swift`
- Create: `scripts/check-localizations.swift`, `check-parameter-help.swift`, `check-doc-parity.swift`, `check-licenses.swift`, `generate-sbom.swift`
- Create/complete: root OSS documents and `docs/{en,zh-Hans,zh-Hant,ja,ko}/` key document trees
- Create: `ThirdPartyLicenses/` exact license texts and machine-readable dependency inventory
- Create: `scripts/sign.sh`, `package.sh`, `notarize.sh`, `generate-appcast.sh`, `release.sh`, `verify-release.sh`, `verify-sparkle-update.sh`
- Create: `.github/workflows/release.yml`, `release-verify.yml`
- Modify: `project.yml` with final Sparkle public key and release settings
- Create: localization/release tests under `Tests/MCAppCoreTests`, `Tests/MacContainerUITests`, `Tests/ToolingTests`
- Create: `docs/reviews/stage-8.md`

### Task 1: Implement system-following and explicit five-language selection

**Files:**
- Create: `Sources/MCAppCore/AppLanguage.swift`
- Create: `Sources/MCAppCore/LanguageController.swift`
- Modify: `App/MacContainer/MacContainerApp.swift`
- Modify: `App/MacContainer/Views/Settings/GeneralSettingsView.swift`
- Test: `Tests/MCAppCoreTests/LanguageControllerTests.swift`

- [x] **Step 1: Write failing language resolution tests**

```swift
import Testing
@testable import MCAppCore

@Suite("App language")
struct LanguageControllerTests {
    @Test(arguments: [
        (AppLanguage.system, ["zh-Hans-CN"], "zh-Hans"),
        (.system, ["zh-Hant-TW"], "zh-Hant"),
        (.system, ["ja-JP"], "ja"),
        (.system, ["ko-KR"], "ko"),
        (.system, ["fr-FR"], "en"),
        (.english, ["zh-Hans"], "en"),
        (.simplifiedChinese, ["en"], "zh-Hans")
    ])
    func resolves(_ input: (AppLanguage, [String], String)) {
        #expect(LanguageController.resolve(selection: input.0, preferredLanguages: input.1) == input.2)
    }
}
```

- [x] **Step 2: Run and verify RED**

Run: `swift test --filter LanguageControllerTests`

Expected: FAIL because language types are undefined.

- [x] **Step 3: Implement language choice and safe relaunch requirement**

```swift
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system, english = "en", simplifiedChinese = "zh-Hans", traditionalChinese = "zh-Hant", japanese = "ja", korean = "ko"
}

@MainActor @Observable
public final class LanguageController {
    public private(set) var selection: AppLanguage
    public private(set) var pendingSelection: AppLanguage?
    public var requiresRelaunch: Bool { pendingSelection != nil && pendingSelection != selection }

    public func request(_ language: AppLanguage, hasUnsavedWork: Bool) -> LanguageChangeResult {
        pendingSelection = language
        return hasUnsavedWork ? .saveBeforeRelaunch : .readyToRelaunch
    }
}
```

System resolution performs exact/normalized BCP-47 matching in the required order and falls back to English. The app persists only the enum selection, not remote strings. Change UI shows Save/Cancel/Relaunch and never discards drafts or active activities.

- [x] **Step 4: Run language controller tests**

Run: `swift test --filter LanguageControllerTests`

Expected: PASS for system fallback, explicit choices, unsaved draft, active terminal/activity, persistence corruption, and relaunch cases.

- [x] **Step 5: Commit**

```bash
git add Sources/MCAppCore/AppLanguage.swift Sources/MCAppCore/LanguageController.swift App/MacContainer/MacContainerApp.swift App/MacContainer/Views/Settings/GeneralSettingsView.swift Tests/MCAppCoreTests/LanguageControllerTests.swift
git commit -m "feat: select app language safely"
```

### Task 2: Create complete five-language string catalogs and parameter help

**Files:**
- Create: `App/MacContainer/Resources/Localizable.xcstrings`
- Create: `App/MacContainer/Resources/InfoPlist.xcstrings`
- Create: `scripts/check-localizations.swift`
- Create: `scripts/check-parameter-help.swift`
- Test: `Tests/ToolingTests/localization-policy.bats`

- [x] **Step 1: Add failing parity checks**

The checker decodes Xcode string catalogs, requires development language `en` plus `zh-Hans`, `zh-Hant`, `ja`, `ko`, rejects missing/empty/stale/needs-review translations, rejects positional-format type mismatch, and reports unused keys. Parameter checker reads the 1.1.0 contract and requires label/concise/detail/validation/recovery strings in every language.

Run: `zsh Tests/ToolingTests/localization-policy.bats`

Expected: FAIL listing absent catalogs and all required contract keys.

- [x] **Step 2: Build the authoritative English catalog**

Extract every `LocalizedStringKey`, `String(localized:)`, menu title, error/recovery key, template key, accessibility label/hint, notification, Info.plist string, and all contract help keys. English parameter detail follows one fixed, complete structure: purpose; upstream default; accepted values/format; repeat/order behavior; dependencies; conflicts; OS/hardware/runtime limits; security/data-loss impact; example; recovery.

- [x] **Step 3: Add professional Simplified Chinese, Traditional Chinese, Japanese, and Korean translations**

Preserve technical identifiers, paths, image references, signals, units, and code spans; translate container concepts consistently through a committed glossary embedded in `docs/en/LOCALIZATION_GLOSSARY.md` and its four translated counterparts. Do not machine-copy Simplified Chinese into Traditional Chinese. Validate grammatical placeholders and accelerator collisions.

- [x] **Step 4: Run parity and all five UI language suites**

```bash
swift scripts/check-localizations.swift App/MacContainer/Resources
swift scripts/check-parameter-help.swift Sources/MCContracts/Resources/apple-container-1.1.0.json App/MacContainer/Resources/Localizable.xcstrings
for language in en zh-Hans zh-Hant ja ko; do
  xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerUITests/LocalizationUITests -testLanguage "$language" CODE_SIGNING_ALLOWED=NO test
done
```

Expected: all commands PASS; parameter checker reports every contract parameter complete in five languages.

Validated on 2026-07-16: signed XCUITest passed for English, Simplified Chinese, and Traditional Chinese.
After macOS `testmanagerd` stopped completing its automation-mode handshake, Japanese and Korean were
validated through an independent macOS Accessibility automation pass against the signed fake-runtime app;
both exposed localized window, sidebar, overview, summary, and primary-action labels. No TCC settings were changed.

- [x] **Step 5: Commit**

```bash
git add App/MacContainer/Resources scripts/check-localizations.swift scripts/check-parameter-help.swift Tests/ToolingTests/localization-policy.bats docs/*/LOCALIZATION_GLOSSARY.md Tests/MacContainerUITests/LocalizationUITests.swift
git commit -m "feat: localize app and parameter help"
```

### Task 3: Complete key documents in all five languages

**Files:**
- Create: `docs/en/{USER_GUIDE,INSTALLATION,RUNTIME_UPDATES,COMPLETE_UNINSTALLATION,TROUBLESHOOTING}.md`
- Create: matching files under `docs/zh-Hans`, `docs/zh-Hant`, `docs/ja`, `docs/ko`
- Create: localized `README.zh-Hans.md`, `README.zh-Hant.md`, `README.ja.md`, `README.ko.md`
- Create: `scripts/check-doc-parity.swift`
- Test: `Tests/ToolingTests/document-parity.bats`

- [x] **Step 1: Add a failing document parity checker**

The checker requires six key docs per language (README plus five guides), reads YAML front matter `source_revision`, `language`, `document_id`, compares stable heading IDs, validates local/internal/external link syntax, checks command-free UI instructions, and rejects a translation whose source revision differs from English.

Run: `zsh Tests/ToolingTests/document-parity.bats`

Expected: FAIL listing absent translated documents.

- [x] **Step 2: Write complete authoritative English documents**

Every guide explains UI workflows without requiring Terminal. Installation documents signer/digest/admin approval. Runtime Updates explains three modes, embedded allowlist, idle checks, probes, unknown holds, rollback. Complete Uninstallation enumerates all residue categories and the Unified Logging exclusion. Troubleshooting maps error/recovery IDs and diagnostic redaction. User Guide covers every domain, Simple/Advanced modes, keyboard shortcuts, accessibility, templates, terminal, settings, export, and support.

- [x] **Step 3: Translate and link the complete corpus**

Each translation links to English, displays the exact English source commit, retains stable heading IDs through explicit anchors, and uses the glossary. Root README links all languages and clearly states platform/early version/security/support/repository/license status.

- [x] **Step 4: Run document parity and link checks**

Run: `swift scripts/check-doc-parity.swift docs README.md README.*.md`

Expected: `Document parity PASS: 30 localized documents, 0 stale revisions, 0 broken links`.

- [x] **Step 5: Commit**

```bash
git add README.md README.*.md docs scripts/check-doc-parity.swift Tests/ToolingTests/document-parity.bats
git commit -m "docs: publish five-language user documentation"
```

### Task 4: Generate complete dependency licenses, notices, and SBOM

**Files:**
- Create: `ThirdPartyLicenses/`
- Create: `Config/dependencies.json`
- Create: `scripts/check-licenses.swift`
- Create: `scripts/import-dependency-licenses.swift`
- Create: `scripts/generate-sbom.swift`
- Modify: `THIRD_PARTY_NOTICES`
- Test: `Tests/ToolingTests/license-policy.bats`

- [x] **Step 1: Add failing dependency-to-license parity tests**

The test resolves `Package.resolved`, recursively inspects shipped package products, requires exact name/version/source/revision/license/SPDX/license-file hash for each, requires a copied license text, rejects unreviewed copyleft/network-copyleft/unknown licenses, and verifies notices include direct shipped dependencies.

Run: `zsh Tests/ToolingTests/license-policy.bats`

Expected: FAIL until inventory and license texts are complete.

- [x] **Step 2: Populate reviewed dependency inventory and exact license texts**

Inventory includes Apple container 1.1.0 and all transitively shipped products, Sparkle 2.9.4, SwiftTerm 1.13.0, with source URLs, immutable revision, license ID, copyright notice, and SHA-256 of copied license text. Never invent a license classification; resolve conflicts from authoritative upstream license files.

- [x] **Step 3: Generate deterministic CycloneDX and SPDX SBOMs**

`generate-sbom.swift` sorts components by package URL, includes exact resolved revision, package/product relationship, license, checksums, source URL, app version/build/commit, and emits `dist/MacContainer.cdx.json` and `dist/MacContainer.spdx.json` with `SOURCE_DATE_EPOCH` controlling timestamps.

- [x] **Step 4: Run license/SBOM reproducibility checks**

Run:

```bash
swift scripts/check-licenses.swift MacContainer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved Config/dependencies.json ThirdPartyLicenses THIRD_PARTY_NOTICES
SOURCE_DATE_EPOCH=1784044800 swift scripts/generate-sbom.swift
shasum -a 256 dist/MacContainer.cdx.json dist/MacContainer.spdx.json
SOURCE_DATE_EPOCH=1784044800 swift scripts/generate-sbom.swift
shasum -a 256 -c dist/sbom-checksums.txt
```

Expected: PASS and identical hashes across regeneration.

- [x] **Step 5: Commit**

```bash
git add ThirdPartyLicenses Config/dependencies.json THIRD_PARTY_NOTICES scripts/check-licenses.swift scripts/import-dependency-licenses.swift scripts/generate-sbom.swift Tests/ToolingTests/license-policy.bats
git commit -m "docs: account for shipped dependencies"
```

### Task 5: Integrate Sparkle application updates with a separate key

**Files:**
- Create: `Sources/MCAppCore/AppUpdateController.swift`
- Modify: `App/MacContainer/MacContainerApp.swift`
- Modify: `App/MacContainer/Views/Settings/AboutSettingsView.swift`
- Modify: `project.yml`
- Test: `Tests/MCAppCoreTests/AppUpdateControllerTests.swift`

- [x] **Step 1: Write failing updater-policy tests**

Test scheduled daily checks, user manual check, disabled automatic checks, relaunch safety with active operations, update errors, appcast URL exactness, and the distinction between app updates (Sparkle) and runtime updates (compatibility coordinator).

- [x] **Step 2: Run and verify RED**

Run: `swift test --filter AppUpdateControllerTests`

Expected: FAIL because controller is undefined.

- [x] **Step 3: Implement Sparkle controller and create MacContainer-specific EdDSA key**

`AppUpdateController` wraps `SPUStandardUpdaterController`, exposes observable check state, and gates relaunch until drafts/activities are safely saved or cancelled by their own policy. `SUFeedURL` is `https://github.com/matrixreligio/macContainer/releases/latest/download/appcast.xml`; scheduled interval is 86400. Generate a new EdDSA key in a mode-0600 temporary file, add only the public `SUPublicEDKey` to `project.yml`, migrate the seed directly to the repository's `SPARKLE_PRIVATE_KEY`, then securely delete the temporary file. This avoids changing the developer Mac's login Keychain. Never read/copy GameMaster's Sparkle private key.

- [x] **Step 4: Build and inspect final Info.plist**

Run: `xcodegen generate --spec project.yml && xcodebuild -project MacContainer.xcodeproj -scheme MacContainer CODE_SIGNING_ALLOWED=NO build && plutil -p .artifacts/DerivedData/Build/Products/Debug/MacContainer.app/Contents/Info.plist | rg 'SUFeedURL|SUPublicEDKey|SUScheduledCheckInterval'`

Expected: exact feed URL, nonempty MacContainer public key, interval 86400.

- [x] **Step 5: Commit only the public key/configuration**

```bash
git add Sources/MCAppCore/AppUpdateController.swift App/MacContainer project.yml MacContainer.xcodeproj Tests/MCAppCoreTests/AppUpdateControllerTests.swift
git commit -m "feat: update MacContainer securely with Sparkle"
```

### Task 6: Implement inside-out signing, notarization, packaging, and verification

**Files:**
- Create: `scripts/sign.sh`, `scripts/package.sh`, `scripts/notarize.sh`, `scripts/generate-appcast.sh`, `scripts/release.sh`, `scripts/verify-release.sh`
- Create: `Tests/ToolingTests/release-script-policy.bats`

- [x] **Step 1: Write failing release-policy tests**

Test that scripts require a clean tracked worktree, tag/version/build agreement, exact Developer ID identity/team, hardened runtime, helper/agent mutual designated requirements, notarization/stapling, Gatekeeper assessment of app inside mounted DMG, a fresh EdDSA appcast, SHA-256 checksums, SBOMs, release notes, cleanup traps, and no secret output. Reject release if any step is skipped.

- [x] **Step 2: Run and verify RED**

Run: `zsh Tests/ToolingTests/release-script-policy.bats`

Expected: FAIL because release scripts are absent.

- [x] **Step 3: Implement deterministic release scripts**

`sign.sh` signs nested Sparkle XPC services/tools/frameworks, SwiftTerm/upstream dylibs if present, update agent, helper, app frameworks, then app; verifies Team ID `4DUQGD879H`, bundle IDs, entitlements, and designated requirements after each phase. `package.sh` creates a clean staging directory, copies App and Applications symlink, builds a reproducible-layout DMG, and removes staging/mounts through traps. `notarize.sh` submits DMG with profile `maccontainer-notary`, staples DMG/app where applicable, mounts read-only, and runs `spctl --assess --type execute` plus `codesign --verify --deep --strict` on the app inside. `generate-appcast.sh` writes a fresh appcast using the MacContainer EdDSA key and rejects stale output. `release.sh` orchestrates version/tag validation, Release archive, signing, DMG, notarization, appcast, checksums, SBOM, notes. `verify-release.sh` independently repeats signature/notary/Gatekeeper/appcast/checksum/SBOM/version checks.

- [x] **Step 4: Run unsigned policy and local signed rehearsal**

Run: `zsh Tests/ToolingTests/release-script-policy.bats && scripts/release.sh --policy-check`

Expected: policy PASS. If the Developer ID identity and local notarization profile are available, run `scripts/release.sh --local-rehearsal 0.1.0-seed` and `scripts/verify-release.sh dist`; otherwise this signed command remains a required physical Stage 8/9 gate rather than being reported passed.

Result: unsigned policy, mutation, Ed25519 verification, SBOM, and isolated DMG layout checks pass. The development Mac exposes only an Apple Development identity, so the Developer ID/notarization rehearsal remains an explicit final release-runner gate.

- [x] **Step 5: Commit**

```bash
git add scripts Tests/ToolingTests/release-script-policy.bats RELEASE.md
git commit -m "build: sign notarize and verify releases"
```

### Task 7: Add secret-isolated GitHub release workflows

**Files:**
- Create: `.github/workflows/release.yml`
- Create: `.github/workflows/release-verify.yml`
- Modify: `.github/workflows/ci.yml`
- Test: `Tests/ToolingTests/release-workflow-policy.bats`

- [x] **Step 1: Write failing workflow secret/supply-chain tests**

Reject release permissions before verification, fork/PR secret access, mutable third-party action refs, floating tool downloads, Homebrew in secret-bearing jobs, unmasked secrets, persistent keychain, missing cleanup, unverified assets, tag/input/version mismatch, or use of GameMaster appcast key material.

- [x] **Step 2: Run and verify RED**

Run: `zsh Tests/ToolingTests/release-workflow-policy.bats`

Expected: FAIL until workflows are complete.

- [x] **Step 3: Implement the release workflow using the shared certificate secret contract**

Manual input is strict `vMAJOR.MINOR.PATCH`. A secret-free verification job runs all tests first. The release job uses `macos-26`, downloads checksum-pinned XcodeGen 2.45.4 and Sparkle 2.9.4 tools, imports `DEVELOPER_ID_CERT_P12` with `DEVELOPER_ID_CERT_PASSWORD` into a random ephemeral keychain, stores `ASC_KEY_P8`/`ASC_KEY_ID`/`ASC_ISSUER_ID` under `maccontainer-notary`, exposes repository-specific `SPARKLE_PRIVATE_KEY` only to appcast generation, runs release/independent verification, creates tag/release only after all artifact checks, uploads DMG/appcast/checksums/SBOM/release notes, then verifies the public non-draft release. Cleanup always deletes keychain and credential files.

- [x] **Step 4: Run policy and GitHub workflow syntax checks**

Run: `zsh Tests/ToolingTests/release-workflow-policy.bats && scripts/check-workflow-policy.sh`

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add .github/workflows Tests/ToolingTests/release-workflow-policy.bats
git commit -m "ci: publish verified notarized releases"
```

### Task 8: Prove first-release Sparkle update from a signed seed

**Files:**
- Create: `scripts/verify-sparkle-update.sh`
- Create: `Tests/Fixtures/sparkle/seed-expectations.json`
- Create: `Tests/MacContainerUITests/SparkleUpdateUITests.swift`

- [x] **Step 1: Add a failing seed-to-release harness policy test**

Harness requires a locally signed lower-version seed with the same bundle ID/team/public key/feed, a locally served release appcast/archive signed by the new MacContainer EdDSA key, Sparkle download/verification/install/relaunch, exact upgraded version/build, preserved preferences, no Gatekeeper failure, and cleanup of server/cache/seed/update artifacts.

- [x] **Step 2: Run policy and verify RED**

Run: `scripts/verify-sparkle-update.sh --policy-check`

Expected: FAIL until the harness is complete.

- [x] **Step 3: Implement isolated Sparkle update verification**

Use a unique temporary home/cache under `.artifacts/sparkle-test/${RUN_UUID}`, a loopback-only HTTP server, a generated test appcast signed with the MacContainer key, and XCUITest to press Check for Updates and relaunch. The script captures result summary then deletes app copies, cache, server root, logs, and temporary key files through traps. It never changes `/Applications` or the user's normal Sparkle cache.

- [ ] **Step 4: Run signed seed test**

Run: `scripts/verify-sparkle-update.sh --seed dist/MacContainer-0.0.1-seed.dmg --candidate dist/MacContainer-0.1.0.dmg`

Expected: `Sparkle update PASS: 0.0.1 (seed) -> 0.1.0 (candidate), cleanup empty`.

Local Apple Development rehearsal passed with the exact seed/candidate versions, EdDSA feed,
two-stage install/relaunch flow, preserved preferences, and empty cleanup. The Developer ID,
notarized, Gatekeeper-required run remains part of the final release gate.

- [x] **Step 5: Commit non-secret harness and evidence schema**

```bash
git add scripts/verify-sparkle-update.sh Tests/Fixtures/sparkle Tests/MacContainerUITests/SparkleUpdateUITests.swift
git commit -m "test: verify first-release Sparkle update"
```

### Task 9: Complete Stage 8 localization and release review

**Files:**
- Create: `docs/reviews/stage-8.md`

- [ ] **Step 1: Run full localization/document/license/CI gates**

```bash
scripts/check-repository.sh
swift scripts/check-localizations.swift App/MacContainer/Resources
swift scripts/check-parameter-help.swift Sources/MCContracts/Resources/apple-container-1.1.0.json App/MacContainer/Resources/Localizable.xcstrings
swift scripts/check-doc-parity.swift docs README.md README.*.md
swift scripts/check-licenses.swift MacContainer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved Config/dependencies.json ThirdPartyLicenses THIRD_PARTY_NOTICES
zsh Tests/ToolingTests/release-script-policy.bats
zsh Tests/ToolingTests/release-workflow-policy.bats
git diff --check
```

Expected: PASS.

- [ ] **Step 2: Run signed release rehearsal and Sparkle seed test**

Use the available MatrixReligio Developer ID Application certificate and ASC credentials following macGameMaster's secret names, but a separate MacContainer Sparkle key. Verify signed helper/agent/app, notarization, staple, Gatekeeper, appcast, checksums, SBOM, and seed update. Delete local release test artifacts after compact evidence extraction.

- [ ] **Step 3: Review five-language UX and release supply chain**

Inspect every major screen in each language for truncation, terminology, format/plural, menu accelerator, VoiceOver, help completeness, and relaunch safety. Inspect documents for semantic parity. Inspect release paths for secret lifetime, action/tool pins, nested signing order, notarization truth, appcast identity, asset verification, and cleanup. Fix all findings and rerun.

- [ ] **Step 4: Commit Stage 8 PASS**

```bash
git add docs/reviews/stage-8.md
git commit -m "docs: close localization and release review"
git push origin main
```

Expected: `Gate: PASS`; signed evidence paths/hashes are recorded without any private key or credential.
