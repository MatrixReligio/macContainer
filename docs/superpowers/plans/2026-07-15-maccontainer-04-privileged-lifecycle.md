# Privileged Runtime Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Securely install, manually upgrade/downgrade, roll back, recover, completely uninstall, and independently audit the Apple container runtime without leaving product-controlled residue.

**Architecture:** A pure transaction state machine journals intent and cleanup obligations before side effects. A networkless SMAppService launch daemon authenticates the signed caller and accepts only typed allowlisted operations over XPC; the app downloads and verifies packages, while the helper only installs an already-open verified package through `/usr/sbin/installer` or removes exact trusted manifest intersections.

**Tech Stack:** Swift concurrency, XPC/NSSecureCoding, ServiceManagement, Security.framework, PackageKit receipts, `/usr/sbin/installer`, CryptoKit, APFS clone operations, Swift Testing/XCTest failure injection.

---

## File map

- Create: `Sources/MCSystemLifecycle/LifecycleModels.swift`, `LifecycleJournal.swift`, `LifecycleTransaction.swift`
- Create: `Sources/MCSystemLifecycle/Package/RuntimePackageManifest.swift`, `RuntimePackageVerifier.swift`, `PackageReceiptReader.swift`
- Modify: `Package.swift` — add the read-only `mc-verify-package` executable product.
- Create: `Tools/MCVerifyPackage/main.swift` — inspect one package against one committed manifest without installation.
- Create: `Sources/MCSystemLifecycle/Helper/PrivilegedHelperProtocol.swift`, `HelperClient.swift`, `CallerValidator.swift`, `PathPolicy.swift`
- Create: `Sources/MCSystemLifecycle/Install/InstallTransaction.swift`
- Create: `Sources/MCSystemLifecycle/Upgrade/UpgradeTransaction.swift`, `RollbackStore.swift`
- Create: `Sources/MCSystemLifecycle/Uninstall/UninstallTransaction.swift`, `ResidueAuditor.swift`, `ResidueInventory.swift`
- Create: `Sources/MCSystemLifecycle/Recovery/LifecycleRecovery.swift`
- Create/modify: `App/PrivilegedHelper/main.swift`, helper listener/delegate/service files, helper launch daemon plist
- Create: focused unit and integration tests under `Tests/MCSystemLifecycleTests` and `Tests/MacContainerIntegrationTests`
- Create: `docs/reviews/stage-4.md`

### Task 1: Define a durable lifecycle transaction and cleanup journal

**Files:**
- Create: `Sources/MCSystemLifecycle/LifecycleModels.swift`
- Create: `Sources/MCSystemLifecycle/LifecycleJournal.swift`
- Create: `Sources/MCSystemLifecycle/LifecycleTransaction.swift`
- Test: `Tests/MCSystemLifecycleTests/LifecycleJournalTests.swift`

- [x] **Step 1: Write failing durability and redaction tests**

```swift
import Testing
@testable import MCSystemLifecycle

@Suite("Lifecycle journal")
struct LifecycleJournalTests {
    @Test func persistsIntentBeforeSideEffect() async throws {
        let storage = RecordingJournalStorage()
        let journal = LifecycleJournal(storage: storage)
        let id = try await journal.begin(kind: .install, targetVersion: "1.1.0")
        try await journal.recordIntent(.installPackage(digest: Runtime110.digest), transactionID: id)
        #expect(await storage.events.map(\.phase) == [.began, .intent])
    }

    @Test func encodedJournalContainsNoSecretOrPrivateTempPath() async throws {
        let storage = RecordingJournalStorage()
        let journal = LifecycleJournal(storage: storage)
        let id = try await journal.begin(kind: .install, targetVersion: "1.1.0")
        try await journal.recordFailure(.init(code: "package.invalid", redactedDetail: "digest mismatch"), transactionID: id)
        let bytes = try #require(await storage.lastEncoded)
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(text.contains("password") == false)
        #expect(text.contains("/private/var/folders") == false)
    }
}
```

- [x] **Step 2: Run and verify RED**

Run: `swift test --filter LifecycleJournalTests`

Expected: FAIL because journal types are undefined.

- [x] **Step 3: Implement append-only transaction records**

```swift
public enum LifecycleKind: String, Codable, Sendable { case install, upgrade, downgrade, rollback, uninstall }
public enum LifecyclePhase: String, Codable, Sendable { case began, intent, applied, verified, committed, rollingBack, rolledBack, failed }

public struct LifecycleEvent: Codable, Equatable, Sendable {
    public let sequence: UInt64
    public let transactionID: UUID
    public let kind: LifecycleKind
    public let phase: LifecyclePhase
    public let targetVersion: String?
    public let action: LifecycleAction?
    public let failure: RedactedLifecycleFailure?
    public let timestamp: Date
}

public enum LifecycleAction: Codable, Equatable, Sendable {
    case installPackage(digest: String)
    case stopServices(labels: [String])
    case removePayload(manifestID: String)
    case removeReceipt(identifier: String)
    case removeUserArtifact(kind: ResidueKind)
    case restoreRollbackPoint(identifier: UUID)
}
```

The concrete storage appends one canonical JSON line at a time to `~/Library/Application Support/container.matrixreligio.com/Lifecycle/journal.jsonl`, mode `0600`; it calls `synchronize()` before returning. The next sequence number is verified against the last valid line. A truncated final line is quarantined and recovery fails closed rather than guessing which side effect ran.

- [x] **Step 4: Run crash/truncation tests**

Run: `swift test --filter LifecycleJournalTests`

Expected: PASS for normal append, crash after intent, crash after side effect, truncated record, duplicate sequence, and redaction cases.

- [x] **Step 5: Commit**

```bash
git add Sources/MCSystemLifecycle/LifecycleModels.swift Sources/MCSystemLifecycle/LifecycleJournal.swift Sources/MCSystemLifecycle/LifecycleTransaction.swift Tests/MCSystemLifecycleTests/LifecycleJournalTests.swift
git commit -m "feat: journal runtime lifecycle transactions"
```

### Task 2: Verify signed runtime packages and immutable manifests

**Files:**
- Modify: `Package.swift`
- Create: `Tools/MCVerifyPackage/main.swift`
- Create: `Sources/MCSystemLifecycle/Package/RuntimePackageManifest.swift`
- Create: `Sources/MCSystemLifecycle/Package/RuntimePackageVerifier.swift`
- Create: `Sources/MCSystemLifecycle/Package/PackageReceiptReader.swift`
- Create: `Config/compatibility/apple-container-1.1.0-package.json`
- Test: `Tests/MCSystemLifecycleTests/RuntimePackageVerifierTests.swift`

- [x] **Step 1: Write failing trust tests**

```swift
@Test func acceptsOnlyExactReviewed110Package() async throws {
    let verifier = RuntimePackageVerifier(
        signature: FakePackageSignatureVerifier.accepting(teamID: "UPBK2H6LZM", notarized: true),
        inspector: FakePackageInspector.fixture110
    )
    let report = try await verifier.verify(openFile: .fixture110, against: .appleContainer110)
    #expect(report.sha256 == "0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714")
    #expect(report.receiptIdentifier == "com.apple.container-installer")
    #expect(report.installLocation == "/usr/local")
}

@Test(arguments: [
    PackageMutation.unsigned,
    .notarizationRejected,
    .wrongTeamID,
    .wrongDigest,
    .wrongReceipt,
    .wrongInstallLocation,
    .extraPayload,
    .symlinkSubstitution
])
func rejectsAnyTrustMismatch(_ mutation: PackageMutation) async {
    let verifier = RuntimePackageVerifier.fixture(mutation: mutation)
    await #expect(throws: PackageTrustError.self) {
        try await verifier.verify(openFile: .fixture110, against: .appleContainer110)
    }
}
```

- [x] **Step 2: Run and verify RED**

Run: `swift test --filter RuntimePackageVerifierTests`

Expected: FAIL because verifier types are undefined.

- [x] **Step 3: Implement layered verification**

```swift
public struct RuntimePackageManifest: Codable, Equatable, Sendable {
    public let runtimeVersion: String
    public let assetName: String
    public let sha256: String
    public let installerTeamID: String
    public let signerCommonName: String
    public let receiptIdentifier: String
    public let installLocation: String
    public let payload: [PayloadEntry]
}

public struct PayloadEntry: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case file, directory, symlink }
    public let relativePath: String
    public let kind: Kind
    public let sha256: String?
    public let linkTarget: String?
}
```

Verification order is exact: open with `O_RDONLY | O_CLOEXEC | O_NOFOLLOW`; `fstat` regular file, owner/mode/link count and identity; stream SHA-256 from that descriptor; validate installer signature/static code and trust; require notarization; require Team ID and approved common name; inspect package version/receipt/install location/payload using read-only PackageKit APIs; reject absolute/traversing paths, hard links, unexpected entries, and manifest mismatch; `fstat` again and require identical device/inode/size/mtime. Return an already-open descriptor plus immutable report.

The committed 1.1.0 manifest uses the exact digest and identity from the approved specification and the complete payload extracted from the official signed package.

Add this product and target to `Package.swift`:

```swift
.executable(name: "mc-verify-package", targets: ["MCVerifyPackage"])
```

```swift
.executableTarget(
    name: "MCVerifyPackage",
    dependencies: ["MCSystemLifecycle"],
    path: "Tools/MCVerifyPackage"
)
```

The tool accepts exactly `--manifest <repository-relative JSON path> <package path>`, opens the package read-only, runs `RuntimePackageVerifier`, prints only the redacted trust report, and has no install/helper operation.

- [x] **Step 4: Run trust and real-package read-only verification**

Run: `swift test --filter RuntimePackageVerifierTests && swift run mc-verify-package --manifest Config/compatibility/apple-container-1.1.0-package.json /tmp/container-1.1.0-installer-signed.pkg`

Expected: unit suite PASS and the local official fixture reports `Package trust PASS: Apple container 1.1.0`; the command performs no install and deletes no file.

- [x] **Step 5: Commit**

```bash
git add Package.swift Tools/MCVerifyPackage Sources/MCSystemLifecycle/Package Config/compatibility/apple-container-1.1.0-package.json Tests/MCSystemLifecycleTests/RuntimePackageVerifierTests.swift
git commit -m "feat: verify official runtime packages"
```

### Task 3: Authenticate the app/helper XPC boundary and allowlist requests

**Files:**
- Create: `Sources/MCSystemLifecycle/Helper/PrivilegedHelperProtocol.swift`
- Create: `Sources/MCSystemLifecycle/Helper/HelperClient.swift`
- Create: `Sources/MCSystemLifecycle/Helper/CallerValidator.swift`
- Create: `Sources/MCSystemLifecycle/Helper/PathPolicy.swift`
- Test: `Tests/MCSystemLifecycleTests/CallerValidatorTests.swift`
- Test: `Tests/MCSystemLifecycleTests/PathPolicyTests.swift`

- [x] **Step 1: Write failing spoof/path/injection tests**

```swift
@Test(arguments: [
    CallerMutation.wrongBundleID,
    .wrongTeamID,
    .adhocSignature,
    .missingAuditToken,
    .differentDesignatedRequirement
])
func rejectsSpoofedCaller(_ mutation: CallerMutation) throws {
    #expect(throws: HelperAuthorizationError.self) {
        try CallerValidator.fixture(mutation: mutation).validate(.fixtureConnection)
    }
}

@Test(arguments: [
    "../../etc/passwd", "/usr/local/bin/../etc/passwd", "/tmp/link", "/usr/local/bin/shared-unowned"
])
func rejectsUntrustedRemovalPath(_ path: String) {
    #expect(PathPolicy.runtime110.allowsRemoval(path) == false)
}
```

- [x] **Step 2: Run and verify RED**

Run: `swift test --filter 'CallerValidatorTests|PathPolicyTests'`

Expected: FAIL because helper protocol/security types are undefined.

- [x] **Step 3: Define typed requests and mutual verification**

```swift
public enum PrivilegedRequest: Codable, Equatable, Sendable {
    case installVerifiedPackage(PackageInstallToken)
    case removePayload(RemovePayloadRequest)
    case forgetReceipt(identifier: String)
    case writeResolver(ResolverRequest)
    case removeResolver(name: String)
    case applyPacketFilter(PacketFilterRequest)
    case removePacketFilter(anchor: String)
    case removeKnownEmptyDirectories(manifestID: String)
}
```

No request contains an executable path, shell text, environment, arbitrary filesystem root, URL to download, or unbounded byte buffer. `CallerValidator` extracts audit token from the XPC connection, creates `SecCode`, verifies bundle ID `container.matrixreligio.com`, Team ID `4DUQGD879H`, hardened runtime, and the exact designated requirement embedded at build time. `HelperClient` independently verifies the helper bundle ID/team/designated requirement before sending a request.

`PathPolicy` canonicalizes already-open parent/child descriptors without following links and permits only manifest intersections, `/etc/resolver/containerization.${VALIDATED_NAME}` after strict suffix validation, exact PF anchor `com.apple.container`, and known empty directories. Shared `/usr/local/bin` and `/usr/local/libexec` directories can never be removed.

- [x] **Step 4: Run all boundary tests**

Run: `swift test --filter 'CallerValidatorTests|PathPolicyTests'`

Expected: PASS for valid signed identities and all spoof, traversal, symlink, hard-link, TOCTOU, injection, and oversized-message cases.

- [x] **Step 5: Commit**

```bash
git add Sources/MCSystemLifecycle/Helper Tests/MCSystemLifecycleTests/CallerValidatorTests.swift Tests/MCSystemLifecycleTests/PathPolicyTests.swift
git commit -m "feat: secure privileged helper boundary"
```

### Task 4: Implement the networkless privileged launch daemon

**Files:**
- Modify: `App/PrivilegedHelper/main.swift`
- Create: `App/PrivilegedHelper/HelperListenerDelegate.swift`
- Create: `App/PrivilegedHelper/PrivilegedHelperService.swift`
- Modify: `App/PrivilegedHelper/container.matrixreligio.com.helper.plist`
- Modify: `App/PrivilegedHelper/PrivilegedHelper.entitlements`
- Test: `Tests/MacContainerIntegrationTests/PrivilegedHelperIntegrationTests.swift`

- [x] **Step 1: Write failing integration tests against an unprivileged fixture listener**

The tests connect with valid/invalid audit identity fixtures, submit every request case, assert exactly one allowlisted system adapter call, verify oversized/unknown requests are rejected, and prove the helper cannot open a network socket through entitlement/static inspection.

- [x] **Step 2: Run and verify RED**

Run: `xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerIntegrationTests/PrivilegedHelperIntegrationTests CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because listener/service files do not exist.

- [x] **Step 3: Implement the service**

The launch daemon listens on Mach service `container.matrixreligio.com.helper`, authenticates before exporting any object, decodes versioned data through `NSSecureCoding`, applies a 1 MiB message cap, and dispatches only the eight enum cases. It runs `/usr/sbin/installer -pkg /dev/fd/${PACKAGE_FD} -target /` with an exact empty environment and fixed working directory only after re-verifying the inherited descriptor/report. It never runs a shell.

Entitlements contain no App Sandbox and no network client/server entitlement. The plist uses `MachServices`, `ProcessType=Interactive`, `RunAtLoad=false`, `KeepAlive=false`, and a fixed bundle-contained executable path installed by `SMAppService.daemon(plistName:)`.

- [x] **Step 4: Build, inspect, and run integration tests**

Run:

```bash
xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerIntegrationTests/PrivilegedHelperIntegrationTests CODE_SIGNING_ALLOWED=NO test
codesign -d --entitlements :- .artifacts/DerivedData/Build/Products/Debug/MacContainerPrivilegedHelper 2>&1
scripts/check-no-container-cli.sh .
```

Expected: tests PASS, entitlement output has no network entitlement, scanner permits only the exact `/usr/sbin/installer` use.

- [x] **Step 5: Commit**

```bash
git add App/PrivilegedHelper Tests/MacContainerIntegrationTests/PrivilegedHelperIntegrationTests.swift project.yml MacContainer.xcodeproj
git commit -m "feat: implement networkless privileged helper"
```

### Task 5: Implement transactional runtime installation

**Files:**
- Create: `Sources/MCSystemLifecycle/Install/InstallTransaction.swift`
- Test: `Tests/MCSystemLifecycleTests/InstallTransactionTests.swift`

- [x] **Step 1: Write failing ordered-transaction tests**

```swift
@Test func successfulInstallUsesVerifiedDescriptorAndCleansDownload() async throws {
    let fixture = InstallFixture.success
    let report = try await fixture.transaction.install(.appleContainer110)
    #expect(report.runtimeVersion == "1.1.0")
    #expect(await fixture.recorder.actions == [
        "platform.preflight", "metadata.fetch", "download", "package.verify", "consent",
        "journal.intent.install", "helper.install", "receipt.verify", "payload.verify",
        "service.start", "kernel.ensure", "probes.run", "journal.commit", "download.cleanup"
    ])
    #expect(await fixture.fileSystem.temporaryPaths.isEmpty)
}

@Test func probeFailureRemovesPartialInstallAndReportsResidue() async {
    let fixture = InstallFixture.failure(at: "probes.run")
    await #expect(throws: InstallError.postflightFailed.self) { try await fixture.transaction.install(.appleContainer110) }
    #expect(await fixture.recorder.actions.suffix(3) == ["uninstall.partial", "residue.audit", "download.cleanup"])
}
```

- [x] **Step 2: Run and verify RED**

Run: `swift test --filter InstallTransactionTests`

Expected: FAIL because the transaction is undefined.

- [x] **Step 3: Implement all thirteen approved installation stages**

The transaction injects platform checker, GitHub metadata client, private downloader, package verifier, consent provider, helper, receipt/payload verifier, system controller, kernel adapter, probe runner, journal, residue auditor, and file system. It uses a `defer` cleanup ledger from the moment the temporary root is created. The metadata client accepts only `https://api.github.com/repos/apple/container/releases/...`; the selected asset name and digest come from the embedded manifest, never remote checksums.

Installer success is not returned until receipt, payload, service, kernel, and every required probe pass. If there was no prior installation, failure runs the partial-uninstall/residue path; inaccessible residue is surfaced as incomplete recovery.

- [x] **Step 4: Run every failure boundary**

Run: `swift test --filter InstallTransactionTests`

Expected: PASS for injected failure before/after every one of the thirteen stages and no fixture-owned temporary path remains.

- [x] **Step 5: Commit**

```bash
git add Sources/MCSystemLifecycle/Install Tests/MCSystemLifecycleTests/InstallTransactionTests.swift
git commit -m "feat: install verified runtime transactionally"
```

### Task 6: Implement manual upgrade, downgrade, and rollback

**Files:**
- Create: `Sources/MCSystemLifecycle/Upgrade/UpgradeTransaction.swift`
- Create: `Sources/MCSystemLifecycle/Upgrade/RollbackStore.swift`
- Test: `Tests/MCSystemLifecycleTests/UpgradeTransactionTests.swift`
- Test: `Tests/MCSystemLifecycleTests/RollbackStoreTests.swift`

- [ ] **Step 1: Write failing success/idle/rollback tests**

```swift
@Test func refusesUpgradeWhenWorkAppearsAtFinalIdleCheck() async {
    let fixture = UpgradeFixture(workloadSnapshots: [.idle, .runningContainer("web")])
    await #expect(throws: UpgradeError.workBecameActive(["container:web"])) {
        try await fixture.transaction.upgrade(to: .appleContainer110)
    }
    #expect(await fixture.helper.installCount == 0)
}

@Test func postflightFailureRestoresPreviousVerifiedRuntime() async throws {
    let fixture = UpgradeFixture(postflight: .failure("images.decode"))
    await #expect(throws: UpgradeError.rolledBack.self) { try await fixture.transaction.upgrade(to: .nextFixture) }
    #expect(await fixture.receipt.version == fixture.previous.version)
    #expect(await fixture.probes.runs.last == fixture.previous.requiredProbes)
    #expect(await fixture.blockedVersions.contains(.nextFixture.version))
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter 'UpgradeTransactionTests|RollbackStoreTests'`

Expected: FAIL because upgrade/rollback types do not exist.

- [ ] **Step 3: Implement the eleven-stage upgrade and seven-stage rollback**

`RollbackStore` retains the previous verified installer and manifest, clones configuration/metadata with APFS clone-on-write, and clones full data only when the compatibility entry requires it. Every item is recorded in a mode-`0600` manifest before creation. Space preflight accounts for package + rollback + 20% headroom.

`UpgradeTransaction` performs verified download, baseline capture, previous-package verification, rollback point, final idle recheck, graceful service stop, install, receipt/payload/API version agreement, start, required probes, commit, cleanup. Any failure after stop invokes rollback: stop target, reinstall previous package, restore required data, start previous service, run previous probes, persist redacted diagnostic, block target version. Downgrade requires explicit destructive/storage-compatibility consent and uses the same rollback protection.

- [ ] **Step 4: Run failure injection at every stage**

Run: `swift test --filter 'UpgradeTransactionTests|RollbackStoreTests'`

Expected: PASS; target is never reported successful before probes, previous version is restored whenever rollback is possible, and inability to verify rollback becomes a blocking recovery result.

- [ ] **Step 5: Commit**

```bash
git add Sources/MCSystemLifecycle/Upgrade Tests/MCSystemLifecycleTests/UpgradeTransactionTests.swift Tests/MCSystemLifecycleTests/RollbackStoreTests.swift
git commit -m "feat: upgrade and roll back runtime safely"
```

### Task 7: Implement complete uninstallation and independent zero-residue audit

**Files:**
- Create: `Sources/MCSystemLifecycle/Uninstall/ResidueInventory.swift`
- Create: `Sources/MCSystemLifecycle/Uninstall/ResidueAuditor.swift`
- Create: `Sources/MCSystemLifecycle/Uninstall/UninstallTransaction.swift`
- Test: `Tests/MCSystemLifecycleTests/ResidueAuditorTests.swift`
- Test: `Tests/MCSystemLifecycleTests/UninstallTransactionTests.swift`

- [ ] **Step 1: Write failing complete-residue matrix tests**

```swift
@Test(arguments: ResidueFixture.everyOwnedArtifact)
func reportsEveryArtifactKind(_ fixture: ResidueFixture) async throws {
    let report = try await ResidueAuditor(environment: fixture.environment).audit()
    #expect(report.items.map(\.kind).contains(fixture.expectedKind))
    #expect(report.isEmpty == false)
}

@Test func inaccessibleLocationFailsClosed() async throws {
    let report = try await ResidueAuditor(environment: .inaccessibleResolver).audit()
    #expect(report.items.contains { $0.status == .unverifiable })
    #expect(report.isEmpty == false)
}

@Test func completeUninstallEndsWithIndependentEmptyAudit() async throws {
    let fixture = UninstallFixture.fullInstallation
    let result = try await fixture.transaction.completelyUninstall(confirmation: fixture.validConfirmation)
    #expect(result.audit.isEmpty)
    #expect(await fixture.environment.ownedArtifacts.isEmpty)
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter 'ResidueAuditorTests|UninstallTransactionTests'`

Expected: FAIL because uninstall/audit types are undefined.

- [ ] **Step 3: Implement the complete inventory and transaction**

```swift
public enum ResidueKind: String, Codable, CaseIterable, Sendable {
    case launchService, process, receipt, receiptPayload, applicationSupport, configuration,
         defaultsDomain, registryCredential, resolver, packetFilter, downloadedPackage,
         rollbackPoint, testFixture, downloadCache, runtimeOwnedDirectory
}

public enum ResidueStatus: String, Codable, Sendable { case present, absent, unverifiable }
public struct ResidueItem: Codable, Equatable, Sendable {
    public let kind: ResidueKind
    public let redactedLocation: String
    public let status: ResidueStatus
    public let recoveryKey: String
}
public struct ResidueReport: Codable, Equatable, Sendable {
    public let items: [ResidueItem]
    public var isEmpty: Bool { items.allSatisfy { $0.status == .absent } }
}
```

The independent auditor queries launchd service labels, owned process executable/signature, PackageKit receipt and trusted-manifest payload, `~/Library/Application Support/com.apple.container`, `~/.config/container`, `com.apple.container.defaults`, `com.apple.container.registry` Keychain entry, `/etc/resolver/containerization.*`, exact PF anchor/rules, MacContainer download/rollback/test caches, and nonempty runtime-owned directories. It does not share deletion-result booleans with the transaction.

Uninstall refreshes inventory and confirmation, gracefully stops workloads/services, verifies no process, removes Keychain entries in user context, asks the helper to remove resolver/PF/manifest intersection/receipt/known empty directories, removes user artifacts using exact URLs, and invokes the independent audit. It returns success only for `isEmpty == true`. OS-managed historical Unified Logging is documented but never falsely claimed deleted.

- [ ] **Step 4: Run full failure matrix and preservation-mode distinction**

Run: `swift test --filter 'ResidueAuditorTests|UninstallTransactionTests'`

Expected: PASS for success and failure at every artifact; “preserve data” always reports preserved data and never uses the complete-uninstall success label.

- [ ] **Step 5: Commit**

```bash
git add Sources/MCSystemLifecycle/Uninstall Tests/MCSystemLifecycleTests/ResidueAuditorTests.swift Tests/MCSystemLifecycleTests/UninstallTransactionTests.swift
git commit -m "feat: completely uninstall runtime without residue"
```

### Task 8: Recover interrupted lifecycle work safely

**Files:**
- Create: `Sources/MCSystemLifecycle/Recovery/LifecycleRecovery.swift`
- Test: `Tests/MCSystemLifecycleTests/LifecycleRecoveryTests.swift`

- [ ] **Step 1: Write failing recovery decision tests**

Table-test the last durable event for each lifecycle kind/phase. Before side effect: clean staged data and abort. After target install but before probes: inspect actual receipt/payload and roll back. During uninstall: resume only recorded allowlisted artifact removals and rerun independent audit. Ambiguous/corrupt journal: perform read-only inventory and require recovery UI; never guess/delete.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter LifecycleRecoveryTests`

Expected: FAIL because recovery is undefined.

- [ ] **Step 3: Implement evidence-driven recovery**

```swift
public enum RecoveryDecision: Equatable, Sendable {
    case noAction
    case cleanStaging(transactionID: UUID)
    case rollBack(transactionID: UUID, rollbackPoint: UUID)
    case resumeUninstall(transactionID: UUID, remaining: [ResidueKind])
    case requiresUserRecovery(RedactedLifecycleFailure)
}
```

Decision input combines the journal with a fresh read-only receipt/payload/service/residue inventory. Recovery acquires the global lifecycle lock and records new intent before action.

- [ ] **Step 4: Run recovery and lifecycle suites**

Run: `swift test --filter LifecycleRecoveryTests && swift test --filter MCSystemLifecycleTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MCSystemLifecycle/Recovery Tests/MCSystemLifecycleTests/LifecycleRecoveryTests.swift
git commit -m "feat: recover interrupted lifecycle work"
```

### Task 9: Complete Stage 4 security and failure-injection review

**Files:**
- Create: `docs/reviews/stage-4.md`

- [ ] **Step 1: Run all lifecycle and helper tests**

```bash
swift test --filter MCSystemLifecycleTests
xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -only-testing:MacContainerIntegrationTests/PrivilegedHelperIntegrationTests CODE_SIGNING_ALLOWED=NO test
scripts/check-no-container-cli.sh .
git diff --check
```

Expected: PASS.

- [ ] **Step 2: Run security-specific static/dynamic checks**

Inspect helper entitlements, Mach service and launch daemon plist; scan for `Process` (only fixed installer wrapper allowed), `/bin/sh`, shell fragments, arbitrary path/request fields, network API imports, unredacted credentials, unsafe decoder classes, symlink-following opens, and world/group-writable lifecycle files. Test helper peer authentication with a separately signed wrong-identifier fixture.

- [ ] **Step 3: Review every lifecycle transition and residue item**

Trace success, cancellation, crash, verifier failure, helper rejection, installer partial success, service failure, probe failure, rollback failure, uninstall partial failure, inaccessible audit, and recovery ambiguity. Require an exact recovery path and cleanup outcome for each. Resolve findings and rerun affected tests.

- [ ] **Step 4: Commit Stage 4 PASS**

```bash
git add docs/reviews/stage-4.md
git commit -m "docs: close privileged lifecycle review"
git push origin main
```

Expected: `Gate: PASS`, zero unresolved in-scope findings, and a complete failure-injection table.
