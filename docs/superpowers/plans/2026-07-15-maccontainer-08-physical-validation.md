# Physical End-to-End Validation and Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove the complete product on the local physical Apple silicon Mac, restore the exact pre-test machine baseline with an empty cleanup ledger, complete the final review, and publish/verify the public release.

**Architecture:** A read-only preflight captures signed canonical machine state and stops before mutation if existing user runtime/data is present. A ledger-first physical runner owns every created artifact, drives the production app/helper/direct APIs and XCUITest, independently audits uninstall, compares post-state to pre-state, extracts compact evidence, then destroys test data; release publication occurs only after this physical attestation is valid.

**Tech Stack:** XCTest/XCUITest, Swift physical test executable, macOS launchd/PackageKit/Security/PF/resolver inspection, Apple container official signed packages 1.0.0 and 1.1.0, ephemeral local OCI registry, shell traps, codesign/notarytool/Gatekeeper, GitHub CLI/Actions.

---

## Fixed physical test identities

- Host requirement: current local Apple silicon Mac, macOS 26 or later.
- Main test target runtime: Apple container 1.1.0.
- Official 1.1.0 package SHA-256: `0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714`.
- Reviewed upgrade source/rollback package: Apple container 1.0.0.
- Official 1.0.0 package SHA-256: `13f45f26da94c354adcbefe1e8f7631e7f126e93c5d4dd6a5a538aa66b4f479d`.
- Both receipts: `com.apple.container-installer`, install location `/usr/local`, installer Team ID `UPBK2H6LZM`.
- 1.0.0 is an approved upgrade/rollback source only; the product's complete operation/parameter contract remains 1.1.0.
- Test namespace: `mct-e2e-${RUN_UUID}` for resources and `container.matrixreligio.com.tests.${RUN_UUID}` for temporary roots.
- Result root while running: `.artifacts/physical/${RUN_UUID}`.

## File map

- Create: `Sources/MCSystemLifecycle/Testing/MachineBaseline.swift`, `CleanupLedger.swift`, `GuardedCleanup.swift`
- Create: `Tests/PhysicalHostTests/PhysicalHostPreflightTests.swift`, `PhysicalOperationTests.swift`, `PhysicalUpgradeTests.swift`, `PhysicalUninstallTests.swift`
- Create: `Tests/MacContainerUITests/PhysicalOnboardingTests.swift`, `PhysicalWorkflowTests.swift`, `PhysicalLocalizationAccessibilityTests.swift`
- Create: `Tests/Fixtures/physical/` build context, tiny OCI image recipe, local registry configuration, deterministic files
- Create: `scripts/physical/preflight.swift`, `run.sh`, `recover.swift`, `summarize.swift`, `compare-baseline.swift`
- Create: `Config/physical-test-plan-v1.json`
- Create: `docs/reviews/stage-9.md`, `docs/reviews/final.md`
- Modify: compatibility package manifests/catalog with reviewed 1.0.0 upgrade-source identity and final signed physical attestation

### Task 1: Capture and compare a canonical read-only machine baseline

**Files:**
- Create: `Sources/MCSystemLifecycle/Testing/MachineBaseline.swift`
- Create: `scripts/physical/preflight.swift`
- Create: `scripts/physical/compare-baseline.swift`
- Test: `Tests/MCSystemLifecycleTests/MachineBaselineTests.swift`

- [ ] **Step 1: Write failing canonicalization and refusal tests**

```swift
@Test func canonicalBaselineIgnoresOnlyDocumentedVolatileFields() throws {
    let first = MachineBaseline.fixture(timestamp: .distantPast, processIDs: [100])
    let second = MachineBaseline.fixture(timestamp: .distantFuture, processIDs: [200])
    #expect(first.canonicalForComparison == second.canonicalForComparison)
}

@Test(arguments: ExistingStateFixture.userRuntimeStates)
func destructivePreflightRefusesExistingUserState(_ fixture: ExistingStateFixture) async throws {
    let result = try await PhysicalPreflight(environment: fixture.environment).run()
    #expect(result.permission == .refusedExistingState)
    #expect(await fixture.environment.mutationCount == 0)
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter MachineBaselineTests`

Expected: FAIL because baseline types are undefined.

- [ ] **Step 3: Implement complete read-only inventory**

```swift
public struct MachineBaseline: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let hostHardware: HostHardwareIdentity
    public let macOSVersion: String
    public let packageReceipt: ReceiptSnapshot?
    public let usrLocalPayload: [FileSnapshot]
    public let launchServices: [LaunchServiceSnapshot]
    public let runtimeProcesses: [ProcessSnapshot]
    public let runtimePaths: [PathSnapshot]
    public let defaults: DefaultsSnapshot?
    public let keychainItems: [KeychainMetadataSnapshot]
    public let resolvers: [FileSnapshot]
    public let packetFilter: PacketFilterSnapshot
    public let testCaches: [PathSnapshot]
    public let capturedAt: Date
}
```

Canonical comparison drops only capture time and PIDs while retaining executable path/hash/signature, service labels/state, receipt/version/payload, file type/mode/owner/size/hash/link target, defaults bytes, Keychain metadata (never secret data), resolver bytes, PF normalized rules, and test cache paths. Preflight refuses destructive tests if any receipt, runtime process/service, known payload/data/config/default/credential/resolver/PF entry, or unrecognized test cache exists. It never moves existing data.

- [ ] **Step 4: Run fixture and live read-only preflight**

Run:

```bash
swift test --filter MachineBaselineTests
swift scripts/physical/preflight.swift --output .artifacts/physical-preflight.json --read-only
```

Expected: fixture tests PASS. Live output is either `SAFE_TO_TEST` with zero existing runtime/data or `REFUSED_EXISTING_STATE` with exact read-only evidence; no machine mutation occurs. Remove this planning/preflight artifact after inspecting it unless it becomes the actual run baseline.

- [ ] **Step 5: Commit**

```bash
git add Sources/MCSystemLifecycle/Testing/MachineBaseline.swift scripts/physical/preflight.swift scripts/physical/compare-baseline.swift Tests/MCSystemLifecycleTests/MachineBaselineTests.swift
git commit -m "test: capture physical host baseline safely"
```

### Task 2: Build ledger-first cleanup and crash recovery

**Files:**
- Create: `Sources/MCSystemLifecycle/Testing/CleanupLedger.swift`
- Create: `Sources/MCSystemLifecycle/Testing/GuardedCleanup.swift`
- Create: `scripts/physical/recover.swift`
- Test: `Tests/MCSystemLifecycleTests/GuardedCleanupTests.swift`

- [ ] **Step 1: Write failing allowlist/traversal/crash tests**

```swift
@Test func recordsArtifactBeforeCreation() async throws {
    let storage = RecordingCleanupStorage()
    let ledger = CleanupLedger(storage: storage, runID: .fixture)
    try await ledger.plan(.temporaryDirectory(".artifacts/physical/run/tmp"))
    #expect(await storage.events == [.planned(.temporaryDirectory(".artifacts/physical/run/tmp"))])
}

@Test(arguments: ["/", "/Users", "/usr/local", "../other", ".artifacts/physical/other-run"])
func refusesPathOutsideRunNamespace(_ path: String) async {
    let cleanup = GuardedCleanup(policy: .fixtureRun)
    await #expect(throws: CleanupPolicyError.self) { try await cleanup.remove(.temporaryDirectory(path)) }
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter GuardedCleanupTests`

Expected: FAIL because cleanup types are undefined.

- [ ] **Step 3: Implement typed planned/created/removed ledger transitions**

```swift
public enum TestArtifact: Codable, Equatable, Sendable {
    case container(String), image(String), network(String), volume(String), machine(String), registryCredential(String)
    case runtimePackage(String), rollbackPoint(UUID), resolver(String), packetFilterAnchor(String)
    case temporaryDirectory(String), file(String), keychain(String), launchService(String), resultBundle(String)
}
public enum CleanupState: String, Codable, Sendable { case planned, created, removed, verifiedAbsent }
```

Every create wrapper writes/synchronizes `.planned`, performs creation, writes `.created`; cleanup accepts only artifacts in the current ledger and immutable prefix/type policy, verifies identity after opening, removes it, writes `.removed`, independently verifies absence, writes `.verifiedAbsent`. Recovery reads an exact run ID, inventories actual state, and refuses any unledgered/ambiguous target.

- [ ] **Step 4: Run crash/fuzz/recovery tests**

Run: `swift test --filter GuardedCleanupTests`

Expected: PASS across crashes after every state transition, path fuzzing, symlink/hard-link substitution, duplicate cleanup, missing artifact, and corrupt ledger. The test leaves no temporary fixture.

- [ ] **Step 5: Commit**

```bash
git add Sources/MCSystemLifecycle/Testing scripts/physical/recover.swift Tests/MCSystemLifecycleTests/GuardedCleanupTests.swift
git commit -m "test: recover physical test artifacts safely"
```

### Task 3: Define the complete physical test plan and outer runner

**Files:**
- Create: `Config/physical-test-plan-v1.json`
- Create: `scripts/physical/run.sh`
- Create: `scripts/physical/summarize.swift`
- Test: `Tests/ToolingTests/physical-runner-policy.bats`

- [ ] **Step 1: Write failing runner policy tests**

Require read-only preflight first, unique run root, trap for EXIT/HUP/INT/TERM, no mutation on existing state, package digest/signature check before helper, ledger plan before creation, bounded timeouts, no global Homebrew/Python install, project-local DerivedData/tools, production uninstall before final audit, independent baseline compare, evidence summary before `.xcresult` deletion, and final empty ledger/run root.

- [ ] **Step 2: Run and verify RED**

Run: `zsh Tests/ToolingTests/physical-runner-policy.bats`

Expected: FAIL until runner/plan exist.

- [ ] **Step 3: Implement the outer runner**

The JSON plan enumerates exact test IDs for platform/onboarding/system/templates/containers/images/builds/builder/networks/volumes/registries/machines/DNS/kernel/configuration/upgrade/unknown hold/probes/rollback/uninstall/languages/accessibility/cleanup. `run.sh` creates `.artifacts/physical/${RUN_UUID}` with `0700`, captures baseline, exits unchanged on refusal, downloads official packages into its run root, verifies fixed digests, builds into `.artifacts/DerivedData`, invokes signed app/helper tests, runs production complete uninstall, independent audit, baseline compare, summary/attestation, then guarded cleanup. Trap calls recovery and never deletes an unledgered path.

- [ ] **Step 4: Run runner policy and fake-physical simulation**

Run: `zsh Tests/ToolingTests/physical-runner-policy.bats && scripts/physical/run.sh --simulated-host`

Expected: `Physical simulation PASS: all test IDs exercised, baseline restored, cleanup ledger empty` and no run directory remains except the small committed/test summary fixture.

- [ ] **Step 5: Commit**

```bash
git add Config/physical-test-plan-v1.json scripts/physical Tests/ToolingTests/physical-runner-policy.bats
git commit -m "test: orchestrate isolated physical validation"
```

### Task 4: Exercise every direct runtime domain on the physical Mac

**Files:**
- Create: `Tests/PhysicalHostTests/PhysicalHostPreflightTests.swift`
- Create: `Tests/PhysicalHostTests/PhysicalOperationTests.swift`
- Create: `Tests/Fixtures/physical/Containerfile`
- Create: `Tests/Fixtures/physical/context/fixture.txt`
- Create: `Tests/Fixtures/physical/registry-config.json`

- [ ] **Step 1: Write the physical operation tests before installing runtime**

Tests call production bridge interfaces and use run-prefixed resources. Coverage includes system start/status/version/logs/df/config/stop; all eight templates; container create/run/start/stop/kill/exec/logs/stats/copy/export/delete/prune; image pull/push/save/load/tag/inspect/delete/prune; build and builder start/status/stop/delete; network create/list/inspect/delete/prune; volume create/list/inspect/delete/prune; registry login/list/logout against ephemeral loopback registry; machine create/run/list/inspect/set/set-default/logs/stop/delete; DNS create/list/delete; kernel recommended/local binary/local archive/verified loopback archive paths. Each test registers cleanup before creation.

- [ ] **Step 2: Run only preflight and verify tests are gated**

Run: `swift test --filter PhysicalHostPreflightTests`

Expected: PASS; operation tests skip with `PHYSICAL_TEST_AUTHORIZATION missing`, proving they cannot mutate accidentally.

- [ ] **Step 3: Add production-bridge physical implementations and fixtures**

Use a tiny reviewed image, deterministic local build context, loopback-only registry with temporary credentials, uniquely named resources, small CPU/memory/disk limits, bounded logs/stats, and no external host mount except run-owned fixtures. Kernel test restores the recommended 1.1.0 kernel at the end and verifies its digest. Source/runtime observer records every spawned executable and fails if `container`, `update-container.sh`, or `uninstall-container.sh` executes. `/usr/sbin/installer` is allowed only from the signed helper during a planned package phase; `/bin/launchctl` is allowed only from upstream `ContainerPlugin.ServiceManager` with its fixed service verbs and validated Apple container labels/plists.

- [ ] **Step 4: Run the signed physical operation phase through the outer runner**

Run: `scripts/physical/run.sh --phase install-and-operations`

Expected: all operation IDs PASS; no unplanned process/path; phase cleanup removes workload resources while preserving the runtime solely for upgrade tests. If preflight finds user state, runner exits unchanged and this gate remains not passed.

- [ ] **Step 5: Commit test source and compact non-machine-specific evidence schema**

```bash
git add Tests/PhysicalHostTests Tests/Fixtures/physical
git commit -m "test: cover every runtime domain physically"
```

### Task 5: Prove 1.0.0 to 1.1.0 automatic upgrade and rollback

**Files:**
- Create: `Tests/PhysicalHostTests/PhysicalUpgradeTests.swift`
- Modify: `Config/compatibility/apple-container-1.1.0-package.json`
- Create: `Config/compatibility/apple-container-1.0.0-upgrade-source.json`
- Modify: `Config/compatibility/catalog-v1.json`

- [ ] **Step 1: Write physical upgrade tests and failure assertions**

Test install official 1.0.0; verify receipt/binaries/service and baseline preflight; verify target 1.1.0 catalog allows this exact source; create no active work; automatically download/verify/install 1.1.0; run eleven baseline and representative physical probes; verify success. Then reinstall 1.0.0, inject one postflight failure after 1.1.0 install, verify rollback restores exact 1.0.0 package/config/service/probes and blocks 1.1.0. Also present an unknown fake `9.9.9` release metadata response and verify no download/install/service stop.

- [ ] **Step 2: Verify source package identity read-only**

Run: `swift run mc-verify-package --manifest Config/compatibility/apple-container-1.0.0-upgrade-source.json "$RUN_ROOT/downloads/container-1.0.0-installer-signed.pkg"`

Expected: digest `13f45f26da94c354adcbefe1e8f7631e7f126e93c5d4dd6a5a538aa66b4f479d`, notarized Apple signer `UPBK2H6LZM`, receipt/location match. The outer runner supplies the run-owned path and cleans it.

- [ ] **Step 3: Implement upgrade-source identity without broad 1.0.0 UI support**

The 1.1.0 entry adds `allowedUpgradeSources` with exact 1.0.0 package identity, required read-only preflight probe subset, rollback safety, and migration classification. It does not add a 1.0.0 operation contract or claim all 1.1.0 UI operations work before upgrade.

- [ ] **Step 4: Run physical upgrade/rollback phase**

Run: `scripts/physical/run.sh --phase upgrade-rollback`

Expected: `Physical upgrade PASS: 1.0.0 -> 1.1.0`, `Physical rollback PASS: injected 1.1.0 failure -> 1.0.0`, `Unknown version HOLD PASS`, with all downloaded/rollback temporary artifacts ledgered. The phase leaves 1.1.0 installed for UI tests only after a fresh clean upgrade.

- [ ] **Step 5: Commit reviewed source identity and test code**

```bash
git add Tests/PhysicalHostTests/PhysicalUpgradeTests.swift Config/compatibility
git commit -m "test: prove compatible runtime upgrade and rollback"
```

### Task 6: Run physical macOS UI automation in five languages

**Files:**
- Create: `Tests/MacContainerUITests/PhysicalOnboardingTests.swift`
- Create: `Tests/MacContainerUITests/PhysicalWorkflowTests.swift`
- Create: `Tests/MacContainerUITests/PhysicalLocalizationAccessibilityTests.swift`

- [ ] **Step 1: Write UI workflows using production runtime mode**

Tests drive first launch/install authorization/status, Simple Mode quick/web/secure workflows, Advanced parameter edits/help, tables/details/logs/stats, terminal input/resize/close, update pending/hold/rollback states, Settings, diagnostic export/redaction, complete-uninstall confirmation/result. For each of five languages, run every major screen, keyboard navigation, VoiceOver labels through accessibility tree, and `performAccessibilityAudit()`.

- [ ] **Step 2: Run in fake mode and verify deterministic selectors first**

Run: `xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerUITests/PhysicalOnboardingTests -only-testing:MacContainerUITests/PhysicalWorkflowTests -only-testing:MacContainerUITests/PhysicalLocalizationAccessibilityTests PHYSICAL_RUNTIME=NO CODE_SIGNING_ALLOWED=NO test`

Expected: PASS without system mutation.

- [ ] **Step 3: Run production-mode UI phase through the physical runner**

Run: `scripts/physical/run.sh --phase physical-ui`

Expected: all five language runs and accessibility audits PASS. Screenshots/result bundles are captured under the run root, summarized, then deleted; only compact redacted results/hashes remain in the attestation.

- [ ] **Step 4: Perform manual Accessibility Inspector and VoiceOver supplement**

Run the documented short checklist for sidebar, parameter help, destructive confirmation, Activity Center, terminal, runtime update, and uninstall result. Record observed labels/order/actions; do not type or expose credentials. Fix every finding and rerun affected automated audit.

- [ ] **Step 5: Commit UI test code**

```bash
git add Tests/MacContainerUITests/PhysicalOnboardingTests.swift Tests/MacContainerUITests/PhysicalWorkflowTests.swift Tests/MacContainerUITests/PhysicalLocalizationAccessibilityTests.swift
git commit -m "test: automate physical native workflows"
```

### Task 7: Prove complete uninstall and exact baseline restoration

**Files:**
- Create: `Tests/PhysicalHostTests/PhysicalUninstallTests.swift`
- Modify: `scripts/physical/run.sh`, `summarize.swift`, `compare-baseline.swift`

- [ ] **Step 1: Write physical residue assertions before invoking uninstall**

Test production complete-uninstall transaction and then independently check no `com.apple.container.*` service/process, receipt/payload, Application Support, config, defaults, registry Keychain entry, `containerization.*` resolver, PF anchor/rule, downloaded package, rollback point, test fixture/cache, or runtime-owned nonempty directory. Any permission error is failure. Verify shared `/usr/local/bin` and `/usr/local/libexec` remain and unrelated entries/hashes match baseline.

- [ ] **Step 2: Run physical uninstall phase**

Run: `scripts/physical/run.sh --phase complete-uninstall-and-restore`

Expected: production UI/transaction reports success only after empty audit; independent audit is empty; post-baseline canonical JSON equals pre-baseline; cleanup ledger has only `verifiedAbsent`; runner-owned temp/result/package roots are removed after summary.

- [ ] **Step 3: Prove recovery from interrupted uninstall**

Using test-owned installed state, inject termination after each artifact class, restart recovery, complete only ledgered allowlisted removals, and obtain the same empty audit/baseline result. Never run this test if preflight found user state.

- [ ] **Step 4: Verify there is no leftover test/process state**

Run:

```bash
swift scripts/physical/preflight.swift --output .artifacts/post-physical.json --read-only
swift scripts/physical/compare-baseline.swift .artifacts/physical-baseline.json .artifacts/post-physical.json
swift scripts/physical/recover.swift --assert-no-active-ledger
pgrep -fal 'MacContainer|container-apiserver|container-runtime|container-network' && exit 1 || true
```

Expected: baseline comparison PASS, no active ledger, no owned process. Remove the final temporary comparison files after recording hashes.

- [ ] **Step 5: Commit test and summarized evidence references**

```bash
git add Tests/PhysicalHostTests/PhysicalUninstallTests.swift scripts/physical
git commit -m "test: prove zero-residue physical uninstall"
```

### Task 8: Perform final comprehensive review and sign compatibility attestation

**Files:**
- Create: `docs/reviews/stage-9.md`
- Create: `docs/reviews/final.md`
- Create: `Config/compatibility/attestations/apple-container-1.1.0.json`

- [ ] **Step 1: Run all hosted-equivalent and physical gates from a clean commit**

```bash
scripts/check-repository.sh
swift test --parallel
xcodebuild -project MacContainer.xcodeproj -scheme MacContainer CODE_SIGNING_ALLOWED=NO test
scripts/physical/run.sh --all
git diff --check
git status --short
```

Expected: all tests PASS; physical summary says baseline restored/ledger empty; tracked worktree is clean except the newly generated redacted attestation/review evidence intended for commit.

- [ ] **Step 2: Sign and verify the physical attestation**

Run:

```bash
scripts/sign-physical-attestation.sh .artifacts/physical-summary.json Config/compatibility/attestations/apple-container-1.1.0.json
swift scripts/verify-physical-attestation.swift Config/compatibility/attestations/apple-container-1.1.0.json
```

Expected: signature valid; exact source/app/runtime/test-plan identities; every operation true; residue 0; baseline restored true; cleanup ledger empty true. No private key is copied into the repository.

- [ ] **Step 3: Review all current code/docs/evidence against all 21 acceptance criteria**

Inspect specification and current implementation, not only diffs. Reverify every operation/parameter/help/template, direct API audit, package/helper security, lifecycle transition, auto-update/compatibility/rollback, uninstall residue, all languages/docs, HIG/accessibility, concurrency/cancellation, privacy/redaction, CI/supply chain/signing/notary/Sparkle, physical cleanup, and public repository state. Order findings by severity, fix every one, rerun affected full gates, and record exact evidence. `docs/reviews/final.md` must map each criterion to authoritative current files/commands/artifacts and may not infer broad completion from narrow checks.

- [ ] **Step 4: Commit Stage 9 and final PASS reports**

```bash
git add Config/compatibility/attestations docs/reviews/stage-9.md docs/reviews/final.md
git commit -m "docs: complete physical and final product reviews"
git push origin main
```

Expected: both reports say `Gate: PASS`, no unresolved in-scope issue, and the pushed CI run succeeds.

### Task 9: Publish and independently verify the first public release

**Files:**
- Modify: `CHANGELOG.md` with final release entry
- Create: final release artifacts under ignored `dist/` only
- Update: `docs/reviews/final.md` with public URLs/hashes after verification

- [ ] **Step 1: Confirm repository secrets/config without reading secret values**

Run: `gh secret list --repo matrixreligio/macContainer` and verify names `DEVELOPER_ID_CERT_P12`, `DEVELOPER_ID_CERT_PASSWORD`, `KEYCHAIN_PASSWORD`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `SPARKLE_PRIVATE_KEY` are configured. Certificate/ASC values follow macGameMaster; `SPARKLE_PRIVATE_KEY` is the separate MacContainer key.

- [ ] **Step 2: Tag and trigger only the reviewed head**

Update version/build/changelog, rerun release preflight, commit, push, require CI success, then invoke the manual release workflow for `v0.1.0`. The workflow creates the tag only after its own verification; do not create a conflicting local tag first.

```bash
gh workflow run release.yml --repo matrixreligio/macContainer -f version=v0.1.0
```

- [ ] **Step 3: Wait for and inspect the complete release workflow**

Run `gh run list/view/watch` until terminal status. On failure, use systematic debugging, fix source/workflow, rerun all affected gates, and start a new clean release attempt; never publish partial assets.

- [ ] **Step 4: Verify public release and every asset independently**

Run:

```bash
gh release view v0.1.0 --repo matrixreligio/macContainer --json isDraft,isPrerelease,tagName,targetCommitish,url,assets
scripts/verify-release.sh --github-release matrixreligio/macContainer v0.1.0
scripts/verify-sparkle-update.sh --seed dist/MacContainer-0.0.1-seed.dmg --github-candidate matrixreligio/macContainer v0.1.0
```

Expected: public non-draft release; tag targets reviewed head; DMG, `appcast.xml`, checksums, CycloneDX/SPDX SBOM, and release notes exist and verify; signed seed updates to 0.1.0; post-test baseline/cleanup remain clean.

- [ ] **Step 5: Record final public evidence and clean local artifacts**

Add release/workflow URLs, asset names/sizes/SHA-256, app/helper/agent designated requirements, notarization IDs, appcast verification, seed update summary, physical attestation hash, and baseline restoration hash to `docs/reviews/final.md`. Remove `dist`, downloaded assets, temporary keychains/credentials, DerivedData, result bundles, screenshots, loopback registry, server roots, and `.artifacts`; run final read-only residue/baseline check.

```bash
git add docs/reviews/final.md CHANGELOG.md
git commit -m "docs: record verified public release"
git push origin main
git status --short
```

Expected: final status clean, public source/release verifiable, development machine baseline unchanged, and no test artifact remains.
