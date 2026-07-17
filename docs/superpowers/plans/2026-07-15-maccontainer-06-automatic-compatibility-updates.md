# Automatic Compatibility Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically discover runtime releases but install only embedded, physically attested compatible versions when idle, run complete postflight probes, and roll back/hold safely on any uncertainty.

**Architecture:** `MCCompatibility` decodes an app-bundled catalog and makes pure allow/hold decisions. A probe registry spans every bridge domain, while a LaunchAgent-style update process coordinates with the app through typed XPC and delegates installation to the existing lifecycle transaction; remote GitHub metadata can signal availability but cannot grant compatibility.

**Tech Stack:** Swift concurrency, Codable, CryptoKit/CMS identity verification, XPC, ServiceManagement, BG scheduling through launchd, GitHub Actions, signed JSON attestations, Swift Testing/XCTest.

---

## File map

- Create: `Sources/MCCompatibility/CompatibilityCatalog.swift`, `CompatibilityEntry.swift`, `CompatibilityDecision.swift`
- Create: `Sources/MCCompatibility/Probes/CompatibilityProbe.swift`, `ProbeRegistry.swift`, domain probe files
- Create: `Sources/MCCompatibility/Attestation/PhysicalTestAttestation.swift`, `AttestationVerifier.swift`
- Create: `Sources/MCSystemLifecycle/Updates/RuntimeUpdatePolicy.swift`, `RuntimeUpdateCoordinator.swift`, `BlockedVersionStore.swift`
- Create: `App/UpdateAgent/UpdateAgentService.swift`, `UpdateSchedule.swift`, XPC protocol files and launch agent plist
- Create: `Config/compatibility/catalog-v1.json`, `catalog-v1.schema.json`, `trusted-attestation-signers.json`
- Create: `.github/workflows/upstream-monitor.yml`, `.github/workflows/verify-compatibility-pr.yml`
- Create: `scripts/sign-physical-attestation.sh`, `scripts/verify-physical-attestation.swift`, `scripts/check-compatibility-catalog.swift`
- Create: focused tests under `Tests/MCCompatibilityTests`, `Tests/MCSystemLifecycleTests`, `Tests/MacContainerIntegrationTests`
- Create: `docs/reviews/stage-7.md`

### Task 1: Define and load the embedded compatibility catalog

**Files:**
- Create: `Sources/MCCompatibility/CompatibilityEntry.swift`
- Create: `Sources/MCCompatibility/CompatibilityCatalog.swift`
- Create: `Config/compatibility/catalog-v1.schema.json`
- Create: `Config/compatibility/catalog-v1.json`
- Test: `Tests/MCCompatibilityTests/CompatibilityCatalogTests.swift`

- [x] **Step 1: Write failing catalog invariants tests**

```swift
import Testing
@testable import MCCompatibility

@Suite("Compatibility catalog")
struct CompatibilityCatalogTests {
    @Test func bundledCatalogContainsExactReviewed110() throws {
        let catalog = try CompatibilityCatalog.bundled()
        let entry = try #require(catalog.entry(runtimeVersion: "1.1.0"))
        #expect(entry.package.sha256 == "0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714")
        #expect(entry.package.installerTeamID == "UPBK2H6LZM")
        #expect(entry.package.receiptIdentifier == "com.apple.container-installer")
        #expect(entry.adapterPackageVersion == "1.1.0")
        #expect(entry.allowedUpgradeSources == [
            .init(runtimeVersion: "1.0.0", packageSHA256: "13f45f26da94c354adcbefe1e8f7631e7f126e93c5d4dd6a5a538aa66b4f479d")
        ])
        #expect(Set(entry.requiredProbeIDs) == Set(ProbeID.baselineAllCases.map(\.rawValue)))
    }

    @Test func catalogHasNoRemoteSignatureOrCompatibilityAuthority() throws {
        let catalog = try CompatibilityCatalog.bundled()
        #expect(catalog.updateURL == nil)
        #expect(catalog.entries.allSatisfy { $0.attestation.source == .embeddedPhysicalGate })
    }
}
```

- [x] **Step 2: Run and verify RED**

Run: `swift test --filter CompatibilityCatalogTests`

Expected: FAIL because catalog types are undefined.

- [x] **Step 3: Implement immutable catalog types**

```swift
public struct CompatibilityCatalog: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let entries: [CompatibilityEntry]
    public let updateURL: URL?

    public func entry(runtimeVersion: String) -> CompatibilityEntry? {
        entries.first { $0.runtimeVersion == runtimeVersion }
    }
}

public struct CompatibilityEntry: Codable, Equatable, Sendable {
    public let runtimeVersion: String
    public let package: RuntimePackageIdentity
    public let minimumAppVersion: String
    public let maximumAppVersion: String
    public let adapterPackageVersion: String
    public let capabilityIDs: Set<String>
    public let minimumMacOSMajor: Int
    public let requiredHardwareCapabilities: Set<String>
    public let storageMigration: StorageMigrationClassification
    public let rollback: RollbackClassification
    public let allowedUpgradeSources: [UpgradeSourceIdentity]
    public let requiredProbeIDs: [String]
    public let attestation: AttestationReference
}

public struct UpgradeSourceIdentity: Codable, Equatable, Sendable {
    public let runtimeVersion: String
    public let packageSHA256: String
}

public enum StorageMigrationClassification: String, Codable, Sendable { case none, metadataOnly, destructive }
public enum RollbackClassification: String, Codable, Sendable { case packageOnly, configurationAndMetadata, fullDataClone }
```

The loader reads only a resource bundled into the signed app/module, rejects duplicate/unsorted semantic versions, missing capability/operation IDs, unknown probe IDs, invalid version intervals, package-manifest mismatch, attestation mismatch, and an unexpected non-nil `updateURL`.

- [x] **Step 4: Run schema and catalog checks**

Run: `swift test --filter CompatibilityCatalogTests && swift scripts/check-compatibility-catalog.swift Config/compatibility/catalog-v1.json`

Expected: `Compatibility catalog PASS: 1 reviewed runtime, 61 capabilities, 11 baseline probes`.

- [x] **Step 5: Commit**

```bash
git add Sources/MCCompatibility Config/compatibility Tests/MCCompatibilityTests/CompatibilityCatalogTests.swift scripts/check-compatibility-catalog.swift
git commit -m "feat: embed reviewed runtime compatibility catalog"
```

### Task 2: Implement a fail-closed compatibility decision engine

**Files:**
- Create: `Sources/MCCompatibility/CompatibilityDecision.swift`
- Test: `Tests/MCCompatibilityTests/CompatibilityDecisionTests.swift`

- [x] **Step 1: Write the full decision table tests**

```swift
@Test(arguments: [
    DecisionFixture.compatible(.allow),
    .unknownRuntime(.hold(.unknownRuntime)),
    .appTooOld(.hold(.appVersionOutsideRange)),
    .appTooNew(.hold(.appVersionOutsideRange)),
    .oldMacOS(.hold(.unsupportedHost)),
    .missingHardwareCapability(.hold(.unsupportedHost)),
    .digestMismatch(.hold(.packageIdentityMismatch)),
    .blockedVersion(.hold(.previousRollback)),
    .destructiveMigrationWithoutConsent(.hold(.explicitConsentRequired)),
    .missingAttestation(.hold(.missingPhysicalAttestation))
])
func exactDecision(_ fixture: DecisionFixture) {
    #expect(CompatibilityDecisionEngine().decide(fixture.input) == fixture.expected)
}
```

- [x] **Step 2: Run and verify RED**

Run: `swift test --filter CompatibilityDecisionTests`

Expected: FAIL because the engine is undefined.

- [x] **Step 3: Implement explicit outcomes**

```swift
public enum CompatibilityDecision: Equatable, Sendable {
    case allow(CompatibilityEntry)
    case hold(HoldReason)
}

public enum HoldReason: String, Codable, Sendable {
    case unknownRuntime, appVersionOutsideRange, unsupportedHost, packageIdentityMismatch,
         previousRollback, explicitConsentRequired, missingPhysicalAttestation, catalogInvalid
}
```

Decision order is fixed to prevent misleading output: catalog validity → exact runtime entry → app range → host → package identity → verified attestation → blocked store → migration consent. The engine has no network dependency and never infers compatibility from semantic-version proximity.

- [x] **Step 4: Run decision and randomized unknown-version tests**

Run: `swift test --filter CompatibilityDecisionTests`

Expected: PASS; 10,000 generated versions absent from the catalog all produce `.unknownRuntime`.

- [x] **Step 5: Commit**

```bash
git add Sources/MCCompatibility/CompatibilityDecision.swift Tests/MCCompatibilityTests/CompatibilityDecisionTests.swift
git commit -m "feat: hold unverified runtime versions"
```

### Task 3: Implement baseline probes for every API domain

**Files:**
- Create: `Sources/MCCompatibility/Probes/CompatibilityProbe.swift`
- Create: `Sources/MCCompatibility/Probes/ProbeRegistry.swift`
- Create: one focused probe file for Health, Containers, Images, Builder, Networks, Volumes, Registries, Machines, DiskUsage, Configuration, Capabilities
- Test: `Tests/MCCompatibilityTests/ProbeRegistryTests.swift`

- [x] **Step 1: Write failing probe parity/aggregation tests**

```swift
@Test func baselineContainsEveryRequiredDomainExactlyOnce() {
    #expect(ProbeRegistry.baseline.map(\.id) == ProbeID.baselineAllCases)
}

@Test func runnerExecutesAllProbesAndPreservesFailures() async {
    let registry = ProbeRegistry(probes: ProbeID.baselineAllCases.map { FakeProbe(id: $0, outcome: $0 == .images ? .failed("decode") : .passed) })
    let report = await registry.runAll(context: .fixture)
    #expect(report.results.count == ProbeID.baselineAllCases.count)
    #expect(report.isCompatible == false)
    #expect(report.results.first { $0.id == .images }?.outcome == .failed("decode"))
}
```

- [x] **Step 2: Run and verify RED**

Run: `swift test --filter ProbeRegistryTests`

Expected: FAIL because probe types are undefined.

- [x] **Step 3: Implement the eleven-probe registry**

```swift
public enum ProbeID: String, Codable, CaseIterable, Sendable {
    case health, containers, images, builder, networks, volumes, registries, machines, diskUsage, configuration, capabilities
    public static let baselineAllCases = allCases
}

public protocol CompatibilityProbe: Sendable {
    var id: ProbeID { get }
    func run(context: ProbeContext) async -> ProbeResult
}
```

Each production probe uses only its direct bridge protocol and performs a bounded read/decode/invariant check. Registries enumerate metadata without secret material. Capabilities compares the embedded contract/capability set with enabled UI operation IDs. The registry runs independent read probes concurrently with a 20-second global timeout, returns every result in stable enum order, cancels remaining tasks at timeout, and treats skipped/unverifiable as incompatible.

- [x] **Step 4: Run probe tests including malformed upstream fixtures**

Run: `swift test --filter ProbeRegistryTests`

Expected: PASS for success, one/multiple failures, timeout, cancellation, malformed data, missing capability, and secret-redaction cases.

- [x] **Step 5: Commit**

```bash
git add Sources/MCCompatibility/Probes Tests/MCCompatibilityTests/ProbeRegistryTests.swift
git commit -m "feat: probe every runtime API domain"
```

### Task 4: Implement update policy, pending state, and blocked-version persistence

**Files:**
- Create: `Sources/MCSystemLifecycle/Updates/RuntimeUpdatePolicy.swift`
- Create: `Sources/MCSystemLifecycle/Updates/BlockedVersionStore.swift`
- Test: `Tests/MCSystemLifecycleTests/RuntimeUpdatePolicyTests.swift`
- Test: `Tests/MCSystemLifecycleTests/BlockedVersionStoreTests.swift`

- [x] **Step 1: Write failing mode/idle/block tests**

```swift
@Test(arguments: [
    PolicyFixture.checkOnly(.notify),
    .downloadAndNotify(.downloadThenNotify),
    .automaticIdle(.install),
    .automaticBusy(.pending(.workActive)),
    .automaticNoConsent(.pending(.authorizationRequired)),
    .unknown(.held(.unknownRuntime)),
    .blocked(.held(.previousRollback))
])
func policyOutcome(_ fixture: PolicyFixture) {
    #expect(RuntimeUpdatePolicy().action(for: fixture.input) == fixture.expected)
}
```

- [x] **Step 2: Run and verify RED**

Run: `swift test --filter 'RuntimeUpdatePolicyTests|BlockedVersionStoreTests'`

Expected: FAIL because update policy/store are absent.

- [x] **Step 3: Implement three modes and durable block supersession**

```swift
public enum RuntimeUpdateMode: String, Codable, Sendable { case checkOnly, downloadAndNotify, automaticWhenIdle }
public enum RuntimeUpdateAction: Equatable, Sendable {
    case notify, downloadThenNotify, install, pending(PendingReason), held(HoldReason)
}
```

Automatic mode requires explicit stored consent version + currently valid helper authorization. Idle requires no containers, machines, builds, builder, lifecycle transaction, or destructive operation; policy rechecks immediately before stop through `UpgradeTransaction`. `BlockedVersionStore` persists runtime version, app/catalog revision, probe failure, and timestamp; a target remains blocked until a newer signed app catalog entry has a different attestation ID and explicitly supersedes the block.

- [x] **Step 4: Run policy/store tests**

Run: `swift test --filter 'RuntimeUpdatePolicyTests|BlockedVersionStoreTests'`

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add Sources/MCSystemLifecycle/Updates Tests/MCSystemLifecycleTests/RuntimeUpdatePolicyTests.swift Tests/MCSystemLifecycleTests/BlockedVersionStoreTests.swift
git commit -m "feat: coordinate safe runtime update policy"
```

### Task 5: Implement the scheduled update agent and app coordination

**Files:**
- Create: `App/UpdateAgent/UpdateAgentService.swift`
- Create: `App/UpdateAgent/UpdateAgentXPC.swift`
- Create: `App/UpdateAgent/UpdateSchedule.swift`
- Modify: `App/UpdateAgent/container.matrixreligio.com.update-agent.plist`
- Modify: `App/UpdateAgent/main.swift`, `UpdateAgent.entitlements`
- Create: `Sources/MCSystemLifecycle/Updates/RuntimeUpdateCoordinator.swift`
- Test: `Tests/MacContainerIntegrationTests/UpdateAgentTests.swift`

- [x] **Step 1: Write failing scheduling and coordination tests**

Test 24-hour minimum interval, deterministic injected jitter range 0...60 minutes, manual check bypass of interval, offline backoff, GitHub rate-limit response, app-running handoff, app-not-running notification, workload-busy pending state, helper unauthorized, and cancellation. Verify the agent never calls helper install directly without coordinator/decision/preflight.

- [x] **Step 2: Run and verify RED**

Run: `xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerIntegrationTests/UpdateAgentTests CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because update agent service is absent.

- [x] **Step 3: Implement a least-privilege scheduled agent**

The agent has outgoing network access only for GitHub release metadata/package download, no privilege, no shell, and app-group-like shared state located in the app-owned Application Support directory with `0600` files. It checks daily plus injected jitter, observes ETag/Last-Modified/rate limits, asks `CompatibilityDecisionEngine`, downloads only approved identity, then asks the update coordinator to install only when policy/idle/helper/preflight allow. If app UI is running, it publishes typed status over XPC; otherwise it uses a local notification with no secret/path detail.

- [x] **Step 4: Run agent integration and no-CLI checks**

Run: `xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerIntegrationTests/UpdateAgentTests CODE_SIGNING_ALLOWED=NO test && scripts/check-no-container-cli.sh .`

Expected: PASS and no temp package remains in failure/cancellation cases.

- [x] **Step 5: Commit**

```bash
git add App/UpdateAgent Sources/MCSystemLifecycle/Updates Tests/MacContainerIntegrationTests/UpdateAgentTests.swift project.yml MacContainer.xcodeproj
git commit -m "feat: check and stage compatible runtime updates"
```

### Task 6: Integrate preflight, upgrade, postflight, rollback, and UI state

**Files:**
- Modify: `Sources/MCSystemLifecycle/Updates/RuntimeUpdateCoordinator.swift`
- Modify: `Sources/MCSystemLifecycle/Upgrade/UpgradeTransaction.swift`
- Modify: `Sources/MCAppCore/AppState.swift`
- Test: `Tests/MCSystemLifecycleTests/AutomaticUpgradeTests.swift`
- Test: `Tests/MacContainerUITests/AutomaticUpdateUITests.swift`

- [ ] **Step 1: Write failing end-to-end fake transaction tests**

Scenarios: compatible idle success, busy pending then idle, unknown hold, incompatible host hold, bad package rejection, preflight failure, work appears at final check, install failure rollback, postflight domain failure rollback, rollback-probe failure recovery-required, user cancellation before stop, and no cancellation after irreversible installer stage.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter AutomaticUpgradeTests`

Expected: FAIL because the coordinator does not yet compose all components.

- [ ] **Step 3: Implement the guarded composition**

Order is immutable: metadata → catalog decision → package verification → policy → rollback availability → baseline → all preflight probes → final idle check → upgrade transaction → all postflight probes → success. A failed target is persisted blocked before notifying. UI state exposes `checking`, `available`, `downloading`, `pending(reason)`, `installing(phase)`, `held(reason)`, `rolledBack(report)`, `recoveryRequired(report)`, and `upToDate`; it never reduces these to a misleading boolean.

- [ ] **Step 4: Run automatic update unit/UI tests**

Run:

```bash
swift test --filter AutomaticUpgradeTests
xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerUITests/AutomaticUpdateUITests CODE_SIGNING_ALLOWED=NO test
```

Expected: PASS for every state/transition and accessible localized status.

- [ ] **Step 5: Commit**

```bash
git add Sources/MCSystemLifecycle/Updates Sources/MCSystemLifecycle/Upgrade Sources/MCAppCore Tests/MCSystemLifecycleTests/AutomaticUpgradeTests.swift Tests/MacContainerUITests/AutomaticUpdateUITests.swift
git commit -m "feat: automatically upgrade only proven runtimes"
```

### Task 7: Verify signed physical-test attestations

**Files:**
- Create: `Sources/MCCompatibility/Attestation/PhysicalTestAttestation.swift`
- Create: `Sources/MCCompatibility/Attestation/AttestationVerifier.swift`
- Create: `Config/compatibility/trusted-attestation-signers.json`
- Create: `scripts/sign-physical-attestation.sh`
- Create: `scripts/verify-physical-attestation.swift`
- Test: `Tests/MCCompatibilityTests/AttestationVerifierTests.swift`

- [ ] **Step 1: Write failing identity/content/replay tests**

Test a valid local physical attestation and reject wrong signer, altered source commit, altered app build identity, runtime digest mismatch, test-plan mismatch, cleanup false, residue count nonzero, failed operation, expired timestamp, and replayed nonce.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter AttestationVerifierTests`

Expected: FAIL because attestation types are undefined.

- [ ] **Step 3: Implement canonical signed attestations**

```swift
public struct PhysicalTestAttestation: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let nonce: UUID
    public let issuedAt: Date
    public let sourceCommit: String
    public let appBundleIdentifier: String
    public let appVersion: String
    public let appBuild: String
    public let appDesignatedRequirementHash: String
    public let runtimeVersion: String
    public let runtimePackageSHA256: String
    public let testPlanVersion: String
    public let hostModel: String
    public let macOSBuild: String
    public let operationResults: [String: Bool]
    public let residueCount: Int
    public let baselineRestored: Bool
    public let cleanupLedgerEmpty: Bool
    public let signerKeyID: String
    public let signature: String
}
```

Signing serializes canonical sorted-key JSON with empty signature, hashes SHA-256, and signs using a dedicated local code-signing identity/key kept outside the repository. The trusted public key hash is embedded. Verification requires all operation results true, residue zero, baseline/ledger true, exact commit/build/package/test plan, trusted signer, nonce not previously accepted, and issue time within the configured promotion window.

- [ ] **Step 4: Run verifier tests and fixture CLI**

Run: `swift test --filter AttestationVerifierTests && swift scripts/verify-physical-attestation.swift Tests/Fixtures/attestations/valid-1.1.0.json`

Expected: PASS for valid fixture and deterministic reason for every invalid fixture.

- [ ] **Step 5: Commit**

```bash
git add Sources/MCCompatibility/Attestation Config/compatibility/trusted-attestation-signers.json scripts Tests/MCCompatibilityTests/AttestationVerifierTests.swift Tests/Fixtures/attestations
git commit -m "feat: verify physical compatibility attestations"
```

### Task 8: Make upstream monitoring open drafts, never compatibility

**Files:**
- Modify: `.github/workflows/upstream-monitor.yml`
- Create: `.github/workflows/verify-compatibility-pr.yml`
- Create: `scripts/inspect-upstream-release.swift`
- Test: `Tests/ToolingTests/upstream-monitor-policy.bats`

- [ ] **Step 1: Write failing workflow authority tests**

The checker rejects workflow tokens with `contents: write`, direct catalog commits, auto-merge, compatibility labels, unsigned artifact acceptance, mutable action tags, and any path where monitor output changes `Config/compatibility/catalog-v1.json`.

- [ ] **Step 2: Run and verify RED**

Run: `zsh Tests/ToolingTests/upstream-monitor-policy.bats`

Expected: FAIL until workflows and inspector exist.

- [ ] **Step 3: Implement metadata-only monitoring and PR verification**

Monitor fetches official GitHub API release metadata, records asset name/size/digest independently, and creates/updates an issue titled `Compatibility candidate: Apple container ${RUNTIME_VERSION}` containing `Status: UNVERIFIED`; it cannot edit code. A human/Codex-created compatibility PR must include contract/package changes plus a signed attestation. Verification workflow checks schema, exact package identity, source diff, attestation signature/content, operation coverage, cleanup, and a reviewer approval requirement; it cannot synthesize the attestation.

- [ ] **Step 4: Run workflow policy and dry-run fixture**

Run: `zsh Tests/ToolingTests/upstream-monitor-policy.bats && swift scripts/inspect-upstream-release.swift --fixture Tests/Fixtures/github/apple-container-release-1.1.0.json`

Expected: PASS and output includes `Status: UNVERIFIED` without modifying the worktree.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows scripts/inspect-upstream-release.swift Tests/ToolingTests Tests/Fixtures/github
git commit -m "ci: monitor upstream without granting compatibility"
```

### Task 9: Complete Stage 7 compatibility and rollback review

**Files:**
- Create: `docs/reviews/stage-7.md`

- [ ] **Step 1: Run the complete automatic-update gate**

```bash
swift test --filter MCCompatibilityTests
swift test --filter MCSystemLifecycleTests
xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerIntegrationTests/UpdateAgentTests -only-testing:MacContainerUITests/AutomaticUpdateUITests CODE_SIGNING_ALLOWED=NO test
scripts/check-compatibility-catalog.swift Config/compatibility/catalog-v1.json
zsh Tests/ToolingTests/upstream-monitor-policy.bats
git diff --check
```

Expected: PASS.

- [ ] **Step 2: Review fail-closed behavior**

Verify unknown versions, catalog corruption, signer changes, replay, app-range mismatch, host mismatch, workload races, insufficient rollback space, preflight failure, every postflight domain failure, rollback failure, agent offline/rate-limit, consent revocation, helper revocation, and block supersession. Fix every finding and rerun affected tests.

- [ ] **Step 3: Commit Stage 7 PASS**

```bash
git add docs/reviews/stage-7.md
git commit -m "docs: close compatibility update review"
git push origin main
```

Expected: `Gate: PASS` with zero unresolved issue and exact evidence for all eleven baseline probes.
