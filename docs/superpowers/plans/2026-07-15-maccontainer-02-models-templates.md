# Models and Scenario Templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the validated typed request model, deterministic resource recommendations, eight safe built-in templates, transparent overrides, and versioned custom-template persistence.

**Architecture:** `MCModel` owns generic typed values, validation issues, and provenance; `MCTemplates` converts immutable host/image inputs and a reviewed contract into an editable `OperationDraft`. Recommendation and template generation are pure functions, while persistence is an injected actor using atomic file replacement and lossless schema migrations.

**Tech Stack:** Swift 6.3, Foundation, Swift Testing, Codable, actors, property-oriented table tests.

---

## File map

- Create: `Sources/MCModel/FieldValue.swift`
- Create: `Sources/MCModel/Validation.swift`
- Create: `Sources/MCModel/OperationDraft.swift`
- Create: `Sources/MCModel/HostProfile.swift`
- Create: `Sources/MCModel/ImageProfile.swift`
- Create: `Sources/MCModel/Activity.swift`
- Create: `Sources/MCTemplates/ResourceRecommendation.swift`
- Create: `Sources/MCTemplates/ScenarioTemplate.swift`
- Create: `Sources/MCTemplates/BuiltInTemplates.swift`
- Create: `Sources/MCTemplates/TemplateRenderer.swift`
- Create: `Sources/MCTemplates/TemplateDocument.swift`
- Create: `Sources/MCTemplates/TemplateStore.swift`
- Create: `Sources/MCTemplates/TemplateMigration.swift`
- Create: tests with matching focused names under `Tests/MCModelTests` and `Tests/MCTemplatesTests`
- Create: `docs/reviews/stage-2.md`

### Task 1: Model typed field values, provenance, and validation issues

**Files:**
- Create: `Sources/MCModel/FieldValue.swift`
- Create: `Sources/MCModel/Validation.swift`
- Test: `Tests/MCModelTests/FieldValueTests.swift`

- [x] **Step 1: Write failing value and redaction tests**

```swift
import Testing
@testable import MCModel

@Suite("Typed fields")
struct FieldValueTests {
    @Test func stableDisplayAndRedaction() {
        #expect(FieldValue.bytes(2 * 1_073_741_824).displayValue == "2 GiB")
        #expect(FieldValue.duration(.seconds(10)).displayValue == "10s")
        #expect(FieldValue.secret("token").displayValue == "••••••")
    }

    @Test func errorsSortBeforeWarnings() {
        let issues = [
            ValidationIssue(parameterID: "memory", severity: .warning, messageKey: "warning"),
            ValidationIssue(parameterID: "image", severity: .error, messageKey: "error")
        ].sorted()
        #expect(issues.map(\.severity) == [.error, .warning])
    }
}
```

- [x] **Step 2: Run and verify RED**

Run: `swift test --filter FieldValueTests`

Expected: FAIL because `FieldValue` and `ValidationIssue` are undefined.

- [x] **Step 3: Implement values and issues**

```swift
import Foundation

public enum FieldValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case integer(Int64)
    case bytes(Int64)
    case duration(DurationValue)
    case string(String)
    case strings([String])
    case keyValues([KeyValue])
    case path(String)
    case secret(String)
    case portMappings([PortMapping])
    case mounts([Mount])
    case none

    public var displayValue: String {
        switch self {
        case let .bool(value): String(value)
        case let .integer(value): String(value)
        case let .bytes(value) where value.isMultiple(of: 1_073_741_824): "\(value / 1_073_741_824) GiB"
        case let .bytes(value): "\(value) bytes"
        case let .duration(value): "\(value.seconds)s"
        case let .string(value), let .path(value): value
        case let .strings(values): values.joined(separator: ", ")
        case let .keyValues(values): values.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        case .secret: "••••••"
        case let .portMappings(values): values.map(\.description).joined(separator: ", ")
        case let .mounts(values): values.map(\.description).joined(separator: ", ")
        case .none: ""
        }
    }

    public var containsSecret: Bool {
        if case .secret = self { return true }
        return false
    }
}

public struct DurationValue: Codable, Equatable, Sendable { public let seconds: Int64 }
public struct KeyValue: Codable, Equatable, Sendable { public let key: String; public let value: String }
public struct PortMapping: Codable, Equatable, Sendable, CustomStringConvertible {
    public let hostAddress: String?
    public let hostPort: UInt16
    public let containerPort: UInt16
    public let protocolName: String
    public var description: String { "\(hostAddress.map { "\($0):" } ?? "")\(hostPort):\(containerPort)/\(protocolName)" }
}
public struct Mount: Codable, Equatable, Sendable, CustomStringConvertible {
    public let source: String
    public let destination: String
    public let readOnly: Bool
    public var description: String { "\(source):\(destination)\(readOnly ? ":ro" : "")" }
}
```

```swift
public enum ValidationSeverity: Int, Codable, Comparable, Sendable {
    case error = 0, warning = 1, information = 2
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct ValidationIssue: Codable, Equatable, Comparable, Sendable {
    public let parameterID: String
    public let severity: ValidationSeverity
    public let messageKey: String
    public let recoveryKey: String?

    public init(parameterID: String, severity: ValidationSeverity, messageKey: String, recoveryKey: String? = nil) {
        self.parameterID = parameterID
        self.severity = severity
        self.messageKey = messageKey
        self.recoveryKey = recoveryKey
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.severity, lhs.parameterID, lhs.messageKey) < (rhs.severity, rhs.parameterID, rhs.messageKey)
    }
}
```

- [x] **Step 4: Run focused tests**

Run: `swift test --filter FieldValueTests`

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add Sources/MCModel Tests/MCModelTests/FieldValueTests.swift
git commit -m "feat: model typed operation values"
```

### Task 2: Create an editable operation draft and contract validator

**Files:**
- Create: `Sources/MCModel/OperationDraft.swift`
- Create: `Sources/MCContracts/OperationValidator.swift`
- Test: `Tests/MCContractsTests/OperationValidatorTests.swift`

- [x] **Step 1: Write failing dependency, conflict, required, and range tests**

```swift
import Testing
import MCModel
@testable import MCContracts

@Suite("Operation validation")
struct OperationValidatorTests {
    @Test func reportsMissingRequiredValue() throws {
        let operation = try #require(testContract.operation(id: "core.run"))
        let draft = OperationDraft(operationID: operation.id, fields: [:])
        #expect(OperationValidator().validate(draft, against: operation).contains { $0.severity == .error })
    }

    @Test func reportsRosettaPlatformConflict() throws {
        let operation = try #require(testContract.operation(id: "core.run"))
        let draft = OperationDraft(operationID: operation.id, fields: [
            "platform": .init(value: .string("linux/arm64"), source: .userOverride),
            "rosetta": .init(value: .bool(true), source: .userOverride)
        ])
        #expect(OperationValidator().validate(draft, against: operation).contains { $0.parameterID == "rosetta" && $0.severity == .error })
    }
}
```

- [x] **Step 2: Run and verify RED**

Run: `swift test --filter OperationValidatorTests`

Expected: FAIL because draft and validator types are undefined.

- [x] **Step 3: Add draft/provenance types and validator**

```swift
public struct OperationDraft: Codable, Equatable, Sendable {
    public let operationID: String
    public var fields: [String: DraftField]

    public init(operationID: String, fields: [String: DraftField]) {
        self.operationID = operationID
        self.fields = fields
    }
}

public struct DraftField: Codable, Equatable, Sendable {
    public var value: FieldValue
    public var source: ValueSource
    public init(value: FieldValue, source: ValueSource) { self.value = value; self.source = source }
}

public enum ValueSource: String, Codable, Sendable {
    case upstreamDefault, scenarioRule, hostRecommendation, imageMetadata, userOverride
}
```

`OperationValidator.validate` performs these deterministic passes in order: operation ID match; required presence; value-type match; integer/bytes/duration nonnegative bounds; regex grammar using whole-string matching; dependency presence; pairwise conflicts; availability capability checks. It returns sorted issues and never mutates the draft. The Rosetta rule is encoded in the 1.1.0 contract as dependency `platform=linux/amd64` plus capability `rosetta`.

- [x] **Step 4: Run focused and contract suites**

Run: `swift test --filter OperationValidatorTests && swift test --filter MCContractsTests`

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add Sources/MCModel/OperationDraft.swift Sources/MCContracts/OperationValidator.swift Tests/MCContractsTests/OperationValidatorTests.swift
git commit -m "feat: validate typed operation drafts"
```

### Task 3: Implement the deterministic host resource recommendation algorithm

**Files:**
- Create: `Sources/MCModel/HostProfile.swift`
- Create: `Sources/MCTemplates/ResourceRecommendation.swift`
- Test: `Tests/MCTemplatesTests/ResourceRecommendationTests.swift`

- [x] **Step 1: Write the complete recommendation table tests**

```swift
import Testing
import MCModel
@testable import MCTemplates

@Suite("Resource recommendations")
struct ResourceRecommendationTests {
    @Test(arguments: [
        (HostProfile(logicalCPUs: 2, physicalMemoryBytes: 8.gib, chip: .appleSilicon, macOSMajor: 26, capabilities: []), WorkloadKind.quick, 2, 2.gib),
        (HostProfile(logicalCPUs: 8, physicalMemoryBytes: 16.gib, chip: .appleSilicon, macOSMajor: 26, capabilities: []), .development, 4, 4.gib),
        (HostProfile(logicalCPUs: 4, physicalMemoryBytes: 8.gib, chip: .appleSilicon, macOSMajor: 26, capabilities: []), .database, 2, 2.gib),
        (HostProfile(logicalCPUs: 12, physicalMemoryBytes: 32.gib, chip: .appleSilicon, macOSMajor: 26, capabilities: []), .builder, 2, 2.gib)
    ])
    func exactCaps(input: (HostProfile, WorkloadKind, Int, Int64)) {
        let result = ResourceRecommendationEngine.recommend(for: input.1, host: input.0)
        #expect(result.cpuCount == input.2)
        #expect(result.memoryBytes == input.3)
        #expect(result.cpuCount <= max(1, input.0.logicalCPUs - (input.0.logicalCPUs > 2 ? 1 : 0)))
        #expect(result.memoryBytes <= input.0.physicalMemoryBytes / 2)
        #expect(input.0.physicalMemoryBytes - result.memoryBytes >= max(4.gib, input.0.physicalMemoryBytes / 4))
    }
}

private extension Int {
    var gib: Int64 { Int64(self) * 1_073_741_824 }
}
```

- [x] **Step 2: Run and verify RED**

Run: `swift test --filter ResourceRecommendationTests`

Expected: FAIL because host and recommendation types do not exist.

- [x] **Step 3: Implement the pure algorithm**

```swift
public enum HostChip: String, Codable, Sendable { case appleSilicon }

public struct HostProfile: Codable, Equatable, Sendable {
    public let logicalCPUs: Int
    public let physicalMemoryBytes: Int64
    public let chip: HostChip
    public let macOSMajor: Int
    public let capabilities: Set<String>
}
```

```swift
import MCModel

public enum WorkloadKind: String, Codable, Sendable { case quick, development, database, builder, secure, machine }
public struct ResourceRecommendation: Codable, Equatable, Sendable {
    public let cpuCount: Int
    public let memoryBytes: Int64
    public let reservedMemoryBytes: Int64
    public var isRunnable: Bool { memoryBytes >= 512 * 1_048_576 }
}

public enum ResourceRecommendationEngine {
    public static func recommend(for workload: WorkloadKind, host: HostProfile) -> ResourceRecommendation {
        let desired: (cpu: Int, memory: Int64) = switch workload {
        case .quick, .database, .builder, .secure: (2, 2 * 1_073_741_824)
        case .development: (4, 4 * 1_073_741_824)
        case .machine: (4, 4 * 1_073_741_824)
        }
        let cpuReserve = host.logicalCPUs > 2 ? 1 : 0
        let cpu = min(desired.cpu, max(1, host.logicalCPUs - cpuReserve))
        let reserve = max(4 * 1_073_741_824, host.physicalMemoryBytes / 4)
        let available = max(0, host.physicalMemoryBytes - reserve)
        let memory = min(desired.memory, host.physicalMemoryBytes / 2, available)
        return ResourceRecommendation(cpuCount: cpu, memoryBytes: memory, reservedMemoryBytes: reserve)
    }
}
```

- [x] **Step 4: Run table tests and randomized invariants**

Add a deterministic seeded loop covering CPUs 1...32 and memory 4...128 GiB, asserting CPU reserve, nonnegative allocation, the full memory reserve, and the half-memory cap. Profiles that cannot supply at least 512 MiB return `isRunnable == false`; all profiles with enough allocatable memory return `isRunnable == true`.

Run: `swift test --filter ResourceRecommendationTests`

Expected: PASS for the table and all generated profiles.

- [x] **Step 5: Commit**

```bash
git add Sources/MCModel/HostProfile.swift Sources/MCTemplates/ResourceRecommendation.swift Tests/MCTemplatesTests/ResourceRecommendationTests.swift
git commit -m "feat: recommend safe host resources"
```

### Task 4: Define image context and the eight built-in templates

**Files:**
- Create: `Sources/MCModel/ImageProfile.swift`
- Create: `Sources/MCTemplates/ScenarioTemplate.swift`
- Create: `Sources/MCTemplates/BuiltInTemplates.swift`
- Test: `Tests/MCTemplatesTests/BuiltInTemplatesTests.swift`

- [x] **Step 1: Write failing built-in identity and security tests**

```swift
import Testing
import MCModel
@testable import MCTemplates

@Suite("Built-in templates")
struct BuiltInTemplatesTests {
    @Test func hasExactlyEightStableTemplates() {
        #expect(BuiltInTemplates.all.map(\.id) == [
            "quick-run", "interactive-shell", "web-service", "development-workspace",
            "local-database", "restricted-secure", "cross-architecture", "linux-machine-workspace"
        ])
    }

    @Test func restrictedTemplateIsSecureByDefault() throws {
        let result = try BuiltInTemplates.restrictedSecure.render(context: .fixture)
        #expect(result.fields["readOnlyRootFilesystem"]?.value == .bool(true))
        #expect(result.fields["capabilitiesToDrop"]?.value == .strings(["ALL"]))
        #expect(result.fields["networks"]?.value == .strings(["none"]))
        #expect(result.fields["temporaryFilesystems"]?.value == .strings(["/tmp"]))
        #expect(result.fields["mounts"] == nil)
        #expect(result.fields["volumes"] == nil)
    }

    @Test func localDatabaseNeverRemovesOnExit() throws {
        let result = try BuiltInTemplates.localDatabase.render(context: .fixture)
        #expect(result.fields["removeAfterStop"]?.value == .bool(false))
        #expect(result.fields["volumes"] != nil)
        #expect(result.fields["publishedPorts"] != nil)
    }
}
```

- [x] **Step 2: Run and verify RED**

Run: `swift test --filter BuiltInTemplatesTests`

Expected: FAIL because template types are undefined.

- [x] **Step 3: Implement stable template definitions**

```swift
public struct ImageProfile: Codable, Equatable, Sendable {
    public let reference: String
    public let defaultCommand: [String]
    public let shells: [String]
    public let platform: String
    public let exposedPorts: [UInt16]
}
```

```swift
public struct TemplateContext: Sendable {
    public let host: HostProfile
    public let image: ImageProfile
    public let selectedDirectory: String?
    public let selectedVolume: String?
    public let hostPort: UInt16?
}

public struct ScenarioTemplate: Identifiable, Sendable {
    public let id: String
    public let titleKey: String
    public let summaryKey: String
    public let operationID: String
    public let render: @Sendable (TemplateContext) throws -> OperationDraft
}

public enum TemplateError: Error, Equatable {
    case missingImage, missingHostPort, missingDirectory, missingVolume
    case unsupportedRosettaHost
}
```

Implement each built-in as a static constant. Required concrete defaults are:

| ID | Operation | Required default fields |
| --- | --- | --- |
| `quick-run` | `core.run` | generated readable name, image, recommended CPUs/memory, foreground unless user selects background |
| `interactive-shell` | `core.run` | TTY true, interactive true, shell from image then `/bin/sh`, remove-on-exit true |
| `web-service` | `core.run` | detached true, explicit publish mapping, optional named volume, preflight port check capability |
| `development-workspace` | `core.run` | explicit directory mount, workdir equal selected container path, recommended development resources, SSH forwarding false |
| `local-database` | `core.run` | explicit `volumes` and `publishedPorts`, lifecycle stop policy 30 seconds, `removeAfterStop` false |
| `restricted-secure` | `core.run` | `readOnlyRootFilesystem`, `capabilitiesToDrop=ALL`, `temporaryFilesystems=/tmp`, `networks=none`, no `mounts` or `volumes` |
| `cross-architecture` | `core.run` | platform `linux/amd64`, Rosetta true only when `host.capabilities` contains `rosetta` |
| `linux-machine-workspace` | `machines.create` | persistent true, `homeMount=none` until consent, nested virtualization false until capability and consent |

All generated fields use `.scenarioRule` except CPU/memory fields, which use `.hostRecommendation`, and image-derived shell/ports, which use `.imageMetadata`.

- [x] **Step 4: Run built-in and full template suites**

Run: `swift test --filter BuiltInTemplatesTests`

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add Sources/MCModel/ImageProfile.swift Sources/MCTemplates Tests/MCTemplatesTests/BuiltInTemplatesTests.swift
git commit -m "feat: add safe scenario templates"
```

### Task 5: Render transparent sources and upstream-default diffs

**Files:**
- Create: `Sources/MCTemplates/TemplateRenderer.swift`
- Test: `Tests/MCTemplatesTests/TemplateRendererTests.swift`

- [x] **Step 1: Write failing provenance/diff tests**

```swift
@Test func reviewRowsExplainEveryValue() throws {
    let rendered = try TemplateRenderer(contract: testContract).render(template: BuiltInTemplates.quickRun, context: .fixture)
    #expect(rendered.rows.isEmpty == false)
    #expect(rendered.rows.allSatisfy { $0.sourceDescriptionKey.isEmpty == false })
    #expect(rendered.rows.contains { $0.parameterID == "memory" && $0.source == .hostRecommendation })
    #expect(rendered.diffFromUpstream.contains { $0.parameterID == "memory" })
}
```

- [x] **Step 2: Run and verify RED**

Run: `swift test --filter TemplateRendererTests`

Expected: FAIL because `TemplateRenderer` does not exist.

- [x] **Step 3: Implement renderer**

```swift
public struct TemplateReview: Equatable, Sendable {
    public let draft: OperationDraft
    public let rows: [TemplateReviewRow]
    public let diffFromUpstream: [TemplateReviewRow]
}

public struct TemplateReviewRow: Identifiable, Equatable, Sendable {
    public var id: String { parameterID }
    public let parameterID: String
    public let value: FieldValue
    public let source: ValueSource
    public let sourceDescriptionKey: String
    public let upstreamDefault: ParameterValue?
}
```

The renderer locates the operation by exact ID, rejects draft fields absent from the contract, emits rows in contract parameter order, and compares normalized values with upstream defaults. Source keys are `value.source.upstream`, `.scenario`, `.host`, `.image`, and `.user`.

- [x] **Step 4: Run renderer and validator suites**

Run: `swift test --filter TemplateRendererTests && swift test --filter OperationValidatorTests`

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add Sources/MCTemplates/TemplateRenderer.swift Tests/MCTemplatesTests/TemplateRendererTests.swift
git commit -m "feat: explain generated template values"
```

### Task 6: Persist secret-free custom templates atomically

**Files:**
- Create: `Sources/MCTemplates/TemplateDocument.swift`
- Create: `Sources/MCTemplates/TemplateStore.swift`
- Test: `Tests/MCTemplatesTests/TemplateStoreTests.swift`

- [ ] **Step 1: Write failing round-trip, secret rejection, and atomicity tests**

```swift
@Test func roundTripsWithoutSecrets() async throws {
    let fs = InMemoryTemplateFileSystem()
    let store = TemplateStore(root: URL(fileURLWithPath: "/templates"), fileSystem: fs)
    let document = TemplateDocument.fixture
    try await store.save(document)
    #expect(try await store.load(id: document.id) == document)
}

@Test func rejectsSecretFieldsBeforeWrite() async throws {
    let fs = InMemoryTemplateFileSystem()
    let store = TemplateStore(root: URL(fileURLWithPath: "/templates"), fileSystem: fs)
    let document = TemplateDocument.fixture.setting("registryPassword", to: .secret("value"))
    await #expect(throws: TemplateStoreError.secretField("registryPassword")) { try await store.save(document) }
    #expect(fs.files.isEmpty)
}

@Test func failedReplacementPreservesPreviousDocument() async throws {
    let fs = InMemoryTemplateFileSystem(failReplace: true, initial: ["/templates/id.json": Data("old".utf8)])
    let store = TemplateStore(root: URL(fileURLWithPath: "/templates"), fileSystem: fs)
    await #expect(throws: (any Error).self) { try await store.save(.fixture) }
    #expect(fs.files["/templates/id.json"] == Data("old".utf8))
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter TemplateStoreTests`

Expected: FAIL because store types do not exist.

- [ ] **Step 3: Implement document and injected atomic file system**

```swift
public struct TemplateDocument: Codable, Identifiable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public var name: String
    public var operationID: String
    public var fields: [String: DraftField]
}

public protocol TemplateFileSystem: Sendable {
    func read(_ url: URL) async throws -> Data
    func writeAtomically(_ data: Data, to url: URL) async throws
    func list(_ root: URL) async throws -> [URL]
    func remove(_ url: URL) async throws
}

public actor TemplateStore {
    private let root: URL
    private let fileSystem: any TemplateFileSystem

    public init(root: URL, fileSystem: any TemplateFileSystem) {
        self.root = root
        self.fileSystem = fileSystem
    }

    public func save(_ document: TemplateDocument) async throws {
        for (id, field) in document.fields where field.value.containsSecret {
            throw TemplateStoreError.secretField(id)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        try await fileSystem.writeAtomically(data, to: root.appending(path: "\(document.id).json"))
    }
}
```

The concrete file system writes a sibling UUID temporary file with mode `0600`, calls `FileHandle.synchronize()`, uses `FileManager.replaceItemAt`, synchronizes the parent directory, and deletes the temporary file with `defer`. Document IDs must match `^[a-z0-9][a-z0-9-]{0,63}$`, so no caller controls paths.

- [ ] **Step 4: Run store tests with a real temporary-directory fixture**

Run: `swift test --filter TemplateStoreTests`

Expected: PASS and the test's `defer` removes its unique temporary directory.

- [ ] **Step 5: Commit**

```bash
git add Sources/MCTemplates Tests/MCTemplatesTests/TemplateStoreTests.swift
git commit -m "feat: persist custom templates safely"
```

### Task 7: Add tested, lossless schema migration and safe disabling

**Files:**
- Create: `Sources/MCTemplates/TemplateMigration.swift`
- Test: `Tests/MCTemplatesTests/TemplateMigrationTests.swift`

- [ ] **Step 1: Write failing migration tests**

```swift
@Test func migratesVersionOneMemoryMiBWithoutLoss() throws {
    let old = Data(#"{"schemaVersion":1,"id":"dev","name":"Dev","operationID":"core.run","fields":{"memoryMiB":4096}}"#.utf8)
    let migrated = try TemplateMigrator.current.decodeAndMigrate(old)
    #expect(migrated.schemaVersion == 2)
    #expect(migrated.fields["memory"]?.value == .bytes(4_294_967_296))
}

@Test func disablesUnknownFutureSchema() {
    let future = Data(#"{"schemaVersion":99,"id":"future"}"#.utf8)
    #expect(throws: TemplateMigrationError.unsupportedFutureVersion(99)) {
        try TemplateMigrator.current.decodeAndMigrate(future)
    }
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter TemplateMigrationTests`

Expected: FAIL because the migrator is undefined.

- [ ] **Step 3: Implement explicit migrations**

`TemplateMigrator.currentVersion` is `2`. Version 1 decodes through a private `TemplateDocumentV1`, converts `memoryMiB` using checked multiplication by 1,048,576, maps all other known fields exactly, and returns version 2. Unknown future versions return a disabled record containing original bytes and a localized reason key; corrupt documents are quarantined by rename, never overwritten.

- [ ] **Step 4: Run migration and store suites**

Run: `swift test --filter TemplateMigrationTests && swift test --filter TemplateStoreTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MCTemplates/TemplateMigration.swift Tests/MCTemplatesTests/TemplateMigrationTests.swift
git commit -m "feat: migrate template documents losslessly"
```

### Task 8: Complete Stage 2 product behavior review

**Files:**
- Create: `docs/reviews/stage-2.md`

- [ ] **Step 1: Run the full pure-logic gate**

Run:

```bash
swift test --filter MCModelTests
swift test --filter MCContractsTests
swift test --filter MCTemplatesTests
swift test --parallel
git diff --check
```

Expected: PASS.

- [ ] **Step 2: Run deterministic repeatability and secret scans**

Render every built-in template 1,000 times for a fixed context and assert byte-identical encoded output. Search saved fixtures for `password`, `token`, `secret`, private-key headers, and registry authorization values; the test must fail unless the occurrence is an explicit rejection test.

- [ ] **Step 3: Review against specification Sections 6, 8, and 14**

Verify all eight templates, provenance, upstream diff, host resource caps, Rosetta gating, nested virtualization gating, no implicit writable mount in the secure template, editable draft behavior, secret exclusion, atomic replacement, and future-schema safe disable behavior. Fix each finding and rerun its focused test.

- [ ] **Step 4: Commit the green review**

```bash
git add docs/reviews/stage-2.md
git commit -m "docs: close models and templates review"
git push origin main
```

Expected: report says `Gate: PASS` with no unresolved in-scope finding.
