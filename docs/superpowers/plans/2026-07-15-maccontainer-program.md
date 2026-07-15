# MacContainer Program Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver, verify, publish, and release the complete native MacContainer application defined by the approved product specification.

**Architecture:** A Swift Package contains focused domain, contract, template, direct-API bridge, compatibility, lifecycle, and app-core modules. An XcodeGen project composes those modules into a SwiftUI app, a networkless privileged launch daemon, a scheduled update agent, XCTest integration targets, and XCUITest targets; every stage closes with a committed evidence report before the next stage starts.

**Tech Stack:** Swift 6.3, SwiftUI, Swift Observation, Swift Testing, XCTest/XCUITest, XPC, ServiceManagement, Security, Apple container 1.1.0, SwiftTerm 1.13.0, Sparkle 2.9.4, XcodeGen 2.45.4, GitHub Actions, shell verification scripts.

---

## 1. Authoritative inputs and immutable project contract

- Product specification: `docs/superpowers/specs/2026-07-15-maccontainer-design.md`
- Public repository: `https://github.com/matrixreligio/macContainer`
- Default branch: `main`
- Main application bundle identifier: `container.matrixreligio.com`
- Helper bundle identifier and Mach service: `container.matrixreligio.com.helper`
- Update agent bundle identifier: `container.matrixreligio.com.update-agent`
- UI test runner identifier: `container.matrixreligio.com.ui-tests`
- Apple Developer Team ID: `4DUQGD879H`
- Contact and security-reporting address: `contact@matrixreligio.com`
- Minimum host: Apple silicon, macOS 26.0
- Initial Apple runtime contract: exact tag `1.1.0`
- Reviewed upstream main snapshot: `608902412d61761ebd1efc285a9d0a1727e6e2c1`
- Apple installer receipt: `com.apple.container-installer`
- Apple 1.1.0 signed package SHA-256: `0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714`
- Apple installer Team ID: `UPBK2H6LZM`
- Sparkle release key: a new MacContainer-specific EdDSA key; never reuse GameMaster's key.

Any implementation that changes an item in this section must first update the specification and obtain explicit user approval.

## 2. Plan set and execution order

| Order | Detailed plan | Stage output | Entry condition | Exit evidence |
| --- | --- | --- | --- | --- |
| 1 | `2026-07-15-maccontainer-01-foundation.md` | Stages 0-1 | This program plan is committed | Contract matrix, green hosted-equivalent checks, `docs/reviews/stage-0.md`, `docs/reviews/stage-1.md` |
| 2 | `2026-07-15-maccontainer-02-models-templates.md` | Stage 2 | Stages 0-1 green | Model, validation, recommendation, template and migration suites; `docs/reviews/stage-2.md` |
| 3 | `2026-07-15-maccontainer-03-direct-runtime-bridge.md` | Stages 3 and 5 backend | Stage 2 green | Fake-service and adapter suites cover every direct API domain; no-CLI audit; `docs/reviews/stage-3.md`, backend section of `stage-5.md` |
| 4 | `2026-07-15-maccontainer-04-privileged-lifecycle.md` | Stage 4 | Stage 3 green | Helper security, install, update, rollback, uninstall and residue failure-injection suites; `docs/reviews/stage-4.md` |
| 5 | `2026-07-15-maccontainer-05-native-application.md` | Stages 5-6 | Stage 4 green | Every operation reachable in UI, complete parameter help, fake-runtime XCUITest and accessibility evidence; completed `stage-5.md`, `docs/reviews/stage-6.md` |
| 6 | `2026-07-15-maccontainer-06-automatic-compatibility-updates.md` | Stage 7 | Stage 6 green | Signed embedded catalog, idle-only agent, probes, rollback, release-monitoring and attestation verification; `docs/reviews/stage-7.md` |
| 7 | `2026-07-15-maccontainer-07-localization-release.md` | Stage 8 | Stage 7 green | Five-language app and key docs, OSS corpus, signed/notarized build rehearsal, Sparkle seed update, workflows; `docs/reviews/stage-8.md` |
| 8 | `2026-07-15-maccontainer-08-physical-validation.md` | Stage 9 | Stage 8 green and local preflight finds no user runtime/data | Real-runtime E2E, baseline restoration, comprehensive review, public repository and verified release; `docs/reviews/stage-9.md`, `docs/reviews/final.md` |

Execution is sequential in the main thread because the repository instructions explicitly map subagent work to sequential work. Use `superpowers:executing-plans` for implementation, `superpowers:test-driven-development` for every behavior, `superpowers:systematic-debugging` for any unexpected failure, and `superpowers:verification-before-completion` before every stage completion claim.

## 3. Source tree locked by this plan set

```text
.
├── .github/
│   ├── CODEOWNERS
│   ├── dependabot.yml
│   ├── ISSUE_TEMPLATE/
│   ├── pull_request_template.md
│   └── workflows/
├── App/
│   ├── MacContainer/
│   │   ├── MacContainerApp.swift
│   │   ├── Commands/
│   │   ├── Resources/
│   │   ├── Scenes/
│   │   └── Views/
│   ├── PrivilegedHelper/
│   └── UpdateAgent/
├── Config/
│   ├── compatibility/
│   ├── contracts/
│   └── release-tools.json
├── Documentation.docc/
├── Sources/
│   ├── MCAppCore/
│   ├── MCCompatibility/
│   ├── MCContainerBridge/
│   ├── MCContracts/
│   ├── MCModel/
│   ├── MCSystemLifecycle/
│   └── MCTemplates/
├── Tests/
│   ├── MCAppCoreTests/
│   ├── MCCompatibilityTests/
│   ├── MCContainerBridgeTests/
│   ├── MCContractsTests/
│   ├── MCModelTests/
│   ├── MCSystemLifecycleTests/
│   ├── MCTemplatesTests/
│   ├── MacContainerIntegrationTests/
│   ├── MacContainerUITests/
│   ├── PhysicalHostTests/
│   └── TestSupport/
├── docs/
│   ├── en/
│   ├── ja/
│   ├── ko/
│   ├── reviews/
│   ├── superpowers/
│   ├── zh-Hans/
│   └── zh-Hant/
├── scripts/
├── Package.swift
├── Package.resolved
└── project.yml
```

Each production Swift file has one primary responsibility and each mutable external dependency is hidden behind an app-owned protocol so the full hosted test suite is deterministic and non-privileged.

## 4. Stage protocol

For each detailed plan:

- [ ] Create or update the corresponding checklist in `docs/reviews/stage-N.md` before changing production behavior.
- [ ] Execute every RED step and record the failing command plus the intended failure in the commit message or review report.
- [ ] Execute every GREEN step and preserve the exact command/result in the stage report.
- [ ] Run the plan-specific focused suite.
- [ ] Run `swift test --parallel` for all package modules that exist at that stage.
- [ ] Run `xcodegen generate --spec project.yml` and the relevant `xcodebuild` tests once Xcode targets exist.
- [ ] Run `git diff --check` and `scripts/check-clean-generated-state.sh`.
- [ ] Review current code against the approved specification rather than reviewing only the diff.
- [ ] Classify findings as blocker, high, medium, or low and resolve every in-scope item.
- [ ] Re-run the commands affected by each fix.
- [ ] Commit the completed stage report and require it to contain `Gate: PASS` before starting the next plan.

The report format is fixed:

```markdown
# Stage 0 Review

- Specification revision: value printed by `git log -1 --format=%H -- docs/superpowers/specs/2026-07-15-maccontainer-design.md`
- Implementation revision reviewed: value printed by `git rev-parse HEAD`
- Reviewer: Codex main-thread independent pass
- Gate: PASS

## Verification

| Requirement | Command or inspection | Result | Evidence path |
| --- | --- | --- | --- |
| Exact operation coverage | `swift scripts/check-contract-coverage.swift Config/contracts/apple-container-1.1.0-acceptance.json Sources/MCContracts/Resources/apple-container-1.1.0.json` | PASS | `Config/contracts/apple-container-1.1.0-acceptance.json` |

## Findings

| Severity | Finding | Resolution | Reverification |
| --- | --- | --- | --- |
| None | No unresolved in-scope findings | N/A | N/A |

## Deferred limitations

None.
```

A committed stage report replaces the two revision descriptions with the actual full hashes printed by their commands. `scripts/check-plan-placeholders.sh` rejects explanatory revision text in a completed report.

## 5. Requirement-to-evidence ledger

| Acceptance criterion | Owning plan | Final authoritative evidence |
| --- | --- | --- |
| Every built-in operation is executable from UI | 03, 05, 08 | Contract/UI reachability test plus physical operation result bundle |
| Production never launches Apple `container` CLI/scripts | 03, 04, 08 | Source scanner and process-exec observer report |
| All affecting parameters and five-language help | 01, 05, 07 | Contract-to-form-to-string parity verifier and UI audit |
| Safe built-in templates and editable generated values | 02, 05, 08 | Property/unit tests and localized XCUITest |
| Signed runtime install without Terminal | 04, 05, 08 | Package trust report and physical onboarding XCUITest |
| Idle-only compatible automatic upgrade | 04, 06, 08 | Update-state-machine tests and physical upgrade attestation |
| Unknown/incompatible version hold | 06, 08 | Catalog decision tests and physical/fake hold report |
| Postflight probes cover every domain | 03, 06, 08 | Probe registry parity test and attestation |
| Failed upgrade restores verified previous runtime | 04, 06, 08 | Failure-injection suite and physical rollback attestation |
| Complete uninstall has empty residue audit | 04, 08 | Independent audit JSON and pre/post baseline diff |
| OS language plus five explicit choices | 05, 07, 08 | Localization parity and five XCUITest runs |
| HIG, keyboard, VoiceOver, accessibility | 05, 08 | `performAccessibilityAudit()` result bundles and manual checklist |
| Hosted CI, signing, notarization, Sparkle, release | 01, 07, 08 | Successful workflow URLs and verified public assets |
| First Sparkle seed-to-release update | 07, 08 | Update test transcript and signature verification |
| Complete open-source corpus | 01, 07 | Document/license/link/parity verifier |
| Local physical test restores baseline | 08 | Signed baseline-before/after report and empty cleanup ledger |
| Every stage reviewed and fixed | All | `docs/reviews/stage-0.md` through `stage-9.md` |
| Public source, tag, release and assets | 01, 07, 08 | GitHub API/`gh` verification captured in final review |

## 6. Program-level completion gate

- [ ] All eight detailed plans have every checkbox checked.
- [ ] Stage reports 0 through 9 say `Gate: PASS` and contain no unresolved finding.
- [ ] `docs/reviews/final.md` maps all 21 specification acceptance criteria to current evidence.
- [ ] The physical suite proves the local Mac returned to its captured baseline.
- [ ] The public `matrixreligio/macContainer` repository is visible without authentication.
- [ ] `main` and the release tag point to the reviewed commits.
- [ ] GitHub Actions required checks are green.
- [ ] The DMG contains the signed, notarized, stapled application.
- [ ] App/helper/agent signatures use Team ID `4DUQGD879H` and the expected designated requirements.
- [ ] Appcast EdDSA signature, checksums, SBOM, notices, and release notes are valid.
- [ ] A locally signed seed build updates to the first public release through Sparkle.
- [ ] The final response reports concrete paths, test commands, release links, asset identities, and any OS-owned exclusions; it does not infer completion from a subset.
