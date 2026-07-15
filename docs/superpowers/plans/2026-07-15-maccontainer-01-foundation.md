# Repository and Contract Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a reproducible public repository, modular Swift/Xcode build, complete reviewed Apple container 1.1.0 contract, open-source baseline, and hosted CI.

**Architecture:** Pure/testable code lives in focused Swift Package targets while XcodeGen composes app-process targets. A committed, versioned JSON contract is decoded by `MCContracts`, checked against a 61-operation acceptance matrix, and used as the single source of truth for later forms, localization, and bridge coverage.

**Tech Stack:** Swift Package Manager, Swift 6.3, Swift Testing, XcodeGen 2.45.4, GitHub CLI, GitHub Actions `macos-26`, JSON, shell verification scripts.

---

## File map

- Create: `.gitignore` — project-local build/test/tool artifacts and secrets exclusions.
- Create: `.swift-version` — requested Swift toolchain contract.
- Create: `.swiftformat`, `.swiftlint.yml` — formatting and lint policy.
- Create: `Package.swift` — core package products, tests, and exact upstream dependency.
- Create: `project.yml` — app, helper, update agent, integration test, and UI test targets.
- Create: `Sources/MCModel/ProjectIdentity.swift` — immutable identifiers and support contact.
- Create: `Sources/MCContracts/ContractModels.swift` — contract decoding types.
- Create: `Sources/MCContracts/ContractRepository.swift` — exact-version contract loading.
- Create: `Sources/MCContracts/Resources/apple-container-1.1.0.json` — complete reviewed operation/parameter contract.
- Create: `Tests/MCModelTests/ProjectIdentityTests.swift` — identifier contract.
- Create: `Tests/MCContractsTests/ContractRepositoryTests.swift` — schema, operation, parameter, localization-key coverage.
- Create: `Config/contracts/apple-container-1.1.0-acceptance.json` — independent expected operation matrix.
- Create: `scripts/check-contract-coverage.swift` — contract/matrix verifier.
- Create: `scripts/bootstrap-tools.sh` — checksum-pinned local XcodeGen/SwiftLint/SwiftFormat installation.
- Create: `scripts/check-generated-project.sh` — XcodeGen drift verifier.
- Create: `scripts/check-no-container-cli.sh` — forbidden production subprocess scanner.
- Create: `scripts/check-repository.sh` — aggregate secret-free checks.
- Create: `.github/workflows/ci.yml` — hosted CI.
- Create: `.github/workflows/upstream-monitor.yml` — metadata-only release detection draft workflow.
- Create: `.github/dependabot.yml`, `.github/CODEOWNERS`, issue/PR templates.
- Create: initial governance and support documents listed in Task 8.
- Create: `docs/reviews/stage-0.md`, `docs/reviews/stage-1.md` — evidence gates.

### Task 1: Lock project identity and repository hygiene

**Files:**
- Create: `.gitignore`
- Create: `.swift-version`
- Create: `Package.swift`
- Create: `Sources/MCModel/ProjectIdentity.swift`
- Test: `Tests/MCModelTests/ProjectIdentityTests.swift`

- [x] **Step 1: Write the failing identity test**

```swift
import Testing
@testable import MCModel

@Suite("Project identity")
struct ProjectIdentityTests {
    @Test func immutableReleaseIdentity() {
        #expect(ProjectIdentity.appBundleIdentifier == "container.matrixreligio.com")
        #expect(ProjectIdentity.helperBundleIdentifier == "container.matrixreligio.com.helper")
        #expect(ProjectIdentity.updateAgentBundleIdentifier == "container.matrixreligio.com.update-agent")
        #expect(ProjectIdentity.teamIdentifier == "4DUQGD879H")
        #expect(ProjectIdentity.contactEmail == "contact@matrixreligio.com")
    }
}
```

- [x] **Step 2: Run the test and verify RED**

Run: `swift test --filter ProjectIdentityTests`

Expected: FAIL because `Package.swift` and `ProjectIdentity` do not exist.

- [x] **Step 3: Add the minimum identity implementation**

```swift
public enum ProjectIdentity: Sendable {
    public static let appBundleIdentifier = "container.matrixreligio.com"
    public static let helperBundleIdentifier = "container.matrixreligio.com.helper"
    public static let updateAgentBundleIdentifier = "container.matrixreligio.com.update-agent"
    public static let uiTestBundleIdentifier = "container.matrixreligio.com.ui-tests"
    public static let teamIdentifier = "4DUQGD879H"
    public static let contactEmail = "contact@matrixreligio.com"
    public static let installerReceiptIdentifier = "com.apple.container-installer"
}
```

Create `.swift-version` with exactly:

```text
6.3
```

Create `.gitignore` with exactly:

```gitignore
.DS_Store
/.artifacts/
/.build/
/.swiftpm/
/.tools/
/.venv/
/DerivedData/
/build/
/dist/
/*.xcodeproj/xcuserdata/
*.xcresult
*.p12
*.p8
*.pem
*.key
*.mobileprovision
.env
secrets/
```

Create the minimum first-task manifest:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacContainerCore",
    platforms: [.macOS("26.0")],
    products: [.library(name: "MCModel", targets: ["MCModel"])],
    targets: [
        .target(name: "MCModel"),
        .testTarget(name: "MCModelTests", dependencies: ["MCModel"]),
    ]
)
```

- [x] **Step 4: Run the focused test and hygiene checks**

Run: `swift test --filter ProjectIdentityTests && git check-ignore .build/example .tools/example secrets/example.p12`

Expected: PASS and all three sample paths are printed as ignored.

- [x] **Step 5: Commit**

```bash
git add .gitignore .swift-version Package.swift Sources/MCModel Tests/MCModelTests
git commit -m "build: establish MacContainer project identity"
```

### Task 2: Create the modular Swift package

**Files:**
- Modify: `Package.swift`
- Create: empty source anchors under `Sources/MCContracts`, `Sources/MCTemplates`, `Sources/MCContainerBridge`, `Sources/MCCompatibility`, `Sources/MCSystemLifecycle`, `Sources/MCAppCore`
- Create: corresponding test anchors under `Tests/` and `Tests/TestSupport/TestSupport.swift`

- [x] **Step 1: Define the failing package-graph assertion**

Run this assertion against the Task 1 manifest:

```bash
swift package describe --type json | rg '"name"\s*:\s*"MCContracts"'
```

- [x] **Step 2: Run package inspection and verify RED**

Run: `swift package describe --type json | rg '"name"\s*:\s*"MCContracts"'`

Expected: FAIL because the minimum manifest does not yet define `MCContracts`.

- [x] **Step 3: Add the package manifest**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacContainerCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "MCModel", targets: ["MCModel"]),
        .library(name: "MCContracts", targets: ["MCContracts"]),
        .library(name: "MCTemplates", targets: ["MCTemplates"]),
        .library(name: "MCContainerBridge", targets: ["MCContainerBridge"]),
        .library(name: "MCCompatibility", targets: ["MCCompatibility"]),
        .library(name: "MCSystemLifecycle", targets: ["MCSystemLifecycle"]),
        .library(name: "MCAppCore", targets: ["MCAppCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/container.git", exact: "1.1.0"),
    ],
    targets: [
        .target(name: "MCModel"),
        .target(
            name: "MCContracts",
            dependencies: ["MCModel"],
            resources: [.process("Resources")]
        ),
        .target(name: "MCTemplates", dependencies: ["MCModel", "MCContracts"]),
        .target(
            name: "MCContainerBridge",
            dependencies: [
                "MCModel", "MCContracts",
                .product(name: "ContainerAPIClient", package: "container"),
                .product(name: "ContainerBuild", package: "container"),
                .product(name: "ContainerNetworkClient", package: "container"),
                .product(name: "ContainerPersistence", package: "container"),
                .product(name: "ContainerPlugin", package: "container"),
                .product(name: "ContainerResource", package: "container"),
                .product(name: "ContainerXPC", package: "container"),
                .product(name: "MachineAPIClient", package: "container"),
            ]
        ),
        .target(name: "MCCompatibility", dependencies: ["MCModel", "MCContracts", "MCContainerBridge"]),
        .target(name: "MCSystemLifecycle", dependencies: ["MCModel", "MCContracts", "MCContainerBridge", "MCCompatibility"]),
        .target(
            name: "MCAppCore",
            dependencies: ["MCModel", "MCContracts", "MCTemplates", "MCContainerBridge", "MCCompatibility", "MCSystemLifecycle"]
        ),
        .target(name: "TestSupport", dependencies: ["MCModel", "MCContracts", "MCContainerBridge", "MCCompatibility", "MCSystemLifecycle"], path: "Tests/TestSupport"),
        .testTarget(name: "MCModelTests", dependencies: ["MCModel", "TestSupport"]),
        .testTarget(name: "MCContractsTests", dependencies: ["MCContracts", "TestSupport"]),
        .testTarget(name: "MCTemplatesTests", dependencies: ["MCTemplates", "TestSupport"]),
        .testTarget(name: "MCContainerBridgeTests", dependencies: ["MCContainerBridge", "MCModel", "TestSupport"]),
        .testTarget(name: "MCCompatibilityTests", dependencies: ["MCCompatibility", "TestSupport"]),
        .testTarget(name: "MCSystemLifecycleTests", dependencies: ["MCSystemLifecycle", "TestSupport"]),
        .testTarget(name: "MCAppCoreTests", dependencies: ["MCAppCore", "TestSupport"]),
    ]
)
```

Each anchor source contains a public, package-specific namespace such as:

```swift
public enum MCContractsModule: Sendable {}
```

`Tests/TestSupport/TestSupport.swift` contains:

```swift
public enum TestSupportModule: Sendable {}
```

- [x] **Step 4: Resolve and test the exact graph**

Run: `swift package resolve && swift package describe --type json | rg '"name"\s*:\s*"MCContracts"' && swift package show-dependencies --format text && swift test --parallel`

Expected: PASS; output identifies `container<https://github.com/apple/container.git@1.1.0>` and no floating branch dependency.

- [x] **Step 5: Commit**

```bash
git add Package.swift Package.resolved Sources Tests
git commit -m "build: define modular core package"
```

### Task 3: Define the versioned upstream contract model

**Files:**
- Create: `Sources/MCContracts/ContractModels.swift`
- Create: `Sources/MCContracts/ContractRepository.swift`
- Test: `Tests/MCContractsTests/ContractRepositoryTests.swift`

- [x] **Step 1: Write failing decode and stable-encoding tests**

```swift
import Foundation
import Testing
@testable import MCContracts

@Suite("Upstream contract schema")
struct ContractRepositoryTests {
    @Test func semanticRuntimeVersionOrdersNumerically() {
        let older = RuntimeVersion(major: 1, minor: 0, patch: 9)
        let newer = RuntimeVersion(major: 1, minor: 1, patch: 0)
        #expect(older < newer)
        #expect(newer.description == "1.1.0")
    }

    @Test func decodesMinimalReviewedContract() throws {
        let data = Data(#"{"schemaVersion":1,"runtimeVersion":{"major":1,"minor":1,"patch":0},"sourceCommit":"608902412d61761ebd1efc285a9d0a1727e6e2c1","operations":[]}"#.utf8)
        let contract = try ContractRepository.decode(data)
        #expect(contract.runtimeVersion.description == "1.1.0")
        #expect(contract.operations.isEmpty)
    }

    @Test func parameterValueUsesStableSingleKeyJSON() throws {
        let data = Data(#"{"integer":10}"#.utf8)
        let value = try JSONDecoder().decode(ParameterValue.self, from: data)
        #expect(value == .integer(10))
    }
}
```

- [x] **Step 2: Run and verify RED**

Run: `swift test --filter ContractRepositoryTests`

Expected: FAIL because the contract types and repository are undefined.

- [x] **Step 3: Add the complete contract types**

```swift
import Foundation
import MCModel

public struct RuntimeVersion: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

public struct UpstreamContract: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let runtimeVersion: RuntimeVersion
    public let sourceCommit: String
    public let operations: [OperationContract]
}

public struct OperationContract: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let domain: OperationDomain
    public let nativeAction: String
    public let risk: RiskLevel
    public let parameters: [ParameterContract]
}

public enum OperationDomain: String, Codable, CaseIterable, Sendable {
    case core, containers, images, builder, networks, volumes, registries, machines, system, dns, kernel, configuration
}

public enum RiskLevel: String, Codable, Sendable { case readOnly, mutating, destructive, privileged }

public struct ParameterContract: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let cliNames: [String]
    public let valueType: ParameterValueType
    public let cardinality: Cardinality
    public let required: Bool
    public let upstreamDefault: ParameterValue?
    public let acceptedValues: [String]
    public let grammar: String?
    public let dependencies: [String]
    public let conflicts: [String]
    public let availability: AvailabilityContract
    public let securityImpact: RiskLevel
    public let labelKey: String
    public let conciseHelpKey: String
    public let detailedHelpKey: String
    public let validationErrorKey: String
    public let recoveryKey: String
}

public enum ParameterValueType: String, Codable, Sendable {
    case boolean, integer, bytes, duration, string, path, url, enumeration, keyValue, portMapping, mount, platform, signal
}

public enum Cardinality: String, Codable, Sendable { case one, optional, repeated }

public enum ParameterValue: Codable, Equatable, Sendable {
    case boolean(Bool), integer(Int64), string(String), strings([String])
}

public struct AvailabilityContract: Codable, Equatable, Sendable {
    public let minimumRuntime: RuntimeVersion
    public let minimumMacOSMajor: Int
    public let requiresAppleSilicon: Bool
    public let requiredCapabilities: [String]
}
```

`ParameterValue` implements custom `Codable` so its stable external representation is exactly one key such as `{"integer":10}` rather than Swift's synthesized associated-value shape. `ContractRepository.decode(_:)` supports in-memory schema tests; `bundled(version:)` adds the resource lookup used by Task 4.

Add the repository:

```swift
import Foundation

public enum ContractRepositoryError: Error, Equatable {
    case unsupportedVersion(RuntimeVersion)
    case missingBundledResource(String)
}

public enum ContractRepository {
    public static func bundled(version: RuntimeVersion) throws -> UpstreamContract {
        guard version == RuntimeVersion(major: 1, minor: 1, patch: 0) else {
            throw ContractRepositoryError.unsupportedVersion(version)
        }
        let name = "apple-container-\(version.description)"
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw ContractRepositoryError.missingBundledResource("\(name).json")
        }
        return try JSONDecoder().decode(UpstreamContract.self, from: Data(contentsOf: url))
    }
}
```

- [x] **Step 4: Run tests and verify type behavior**

Run: `swift test --filter ContractRepositoryTests`

Expected: PASS for semantic version ordering, minimal in-memory contract decoding, and stable single-key `ParameterValue` JSON. Bundled snapshot coverage remains the next task's RED.

- [x] **Step 5: Commit**

```bash
git add Sources/MCContracts Tests/MCContractsTests
git commit -m "feat: define versioned upstream contract schema"
```

### Task 4: Commit the complete Apple container 1.1.0 acceptance matrix and snapshot

**Files:**
- Create: `Config/contracts/apple-container-1.1.0-acceptance.json`
- Create: `Sources/MCContracts/Resources/apple-container-1.1.0.json`
- Create: `scripts/check-contract-coverage.swift`
- Modify: `Tests/MCContractsTests/ContractRepositoryTests.swift`

- [x] **Step 1: Add a failing independent operation coverage test**

Add to `ContractRepositoryTests`:

```swift
@Test func includesEveryBuiltinOperation() throws {
    let contract = try ContractRepository.bundled(version: .init(major: 1, minor: 1, patch: 0))
    let expected = Set([
        "core.run", "core.build",
        "containers.create", "containers.start", "containers.stop", "containers.kill", "containers.delete", "containers.list", "containers.exec", "containers.export", "containers.logs", "containers.inspect", "containers.stats", "containers.copy", "containers.prune",
        "images.list", "images.pull", "images.push", "images.save", "images.load", "images.tag", "images.delete", "images.prune", "images.inspect",
        "builder.start", "builder.status", "builder.stop", "builder.delete",
        "networks.create", "networks.delete", "networks.prune", "networks.list", "networks.inspect",
        "volumes.create", "volumes.delete", "volumes.prune", "volumes.list", "volumes.inspect",
        "registries.login", "registries.logout", "registries.list",
        "machines.create", "machines.run", "machines.list", "machines.inspect", "machines.set", "machines.set-default", "machines.logs", "machines.stop", "machines.delete",
        "system.start", "system.stop", "system.status", "system.version", "system.logs", "system.disk-usage",
        "dns.create", "dns.delete", "dns.list",
        "kernel.set", "configuration.manage"
    ])
    #expect(Set(contract.operations.map(\.id)) == expected)
}
```

- [x] **Step 2: Run and verify RED**

Run: `swift test --filter ContractRepositoryTests.includesEveryBuiltinOperation`

Expected: FAIL because the bundled snapshot is absent.

- [x] **Step 3: Build the reviewed fixture deterministically**

Create the acceptance JSON with `schemaVersion`, runtime/source identity, and the exact 61 IDs above. Create the bundled contract JSON with one entry per ID and every parameter transcribed from the exact `1.1.0` command definitions under the reviewed upstream paths `Sources/ContainerCommands`, `Sources/Services`, and `docs/command-reference.md`. Every entry uses this concrete JSON shape:

```json
{
  "id": "containers.stop",
  "domain": "containers",
  "nativeAction": "ContainerClient.stop",
  "risk": "mutating",
  "parameters": [
    {
      "id": "containerIDs",
      "cliNames": ["CONTAINER"],
      "valueType": "string",
      "cardinality": "repeated",
      "required": true,
      "upstreamDefault": null,
      "acceptedValues": ["existing container identifier or unambiguous prefix"],
      "grammar": "^[A-Za-z0-9][A-Za-z0-9_.-]*$",
      "dependencies": [],
      "conflicts": [],
      "availability": {
        "minimumRuntime": {"major": 1, "minor": 1, "patch": 0},
        "minimumMacOSMajor": 26,
        "requiresAppleSilicon": true,
        "requiredCapabilities": ["containers.stop"]
      },
      "securityImpact": "mutating",
      "labelKey": "parameter.containers.stop.containerIDs.label",
      "conciseHelpKey": "parameter.containers.stop.containerIDs.concise",
      "detailedHelpKey": "parameter.containers.stop.containerIDs.detail",
      "validationErrorKey": "parameter.containers.stop.containerIDs.validation",
      "recoveryKey": "parameter.containers.stop.containerIDs.recovery"
    },
    {
      "id": "timeoutSeconds",
      "cliNames": ["--time", "-t"],
      "valueType": "duration",
      "cardinality": "optional",
      "required": false,
      "upstreamDefault": {"integer": 10},
      "acceptedValues": ["integer seconds greater than or equal to 0"],
      "grammar": "^[0-9]+$",
      "dependencies": [],
      "conflicts": [],
      "availability": {
        "minimumRuntime": {"major": 1, "minor": 1, "patch": 0},
        "minimumMacOSMajor": 26,
        "requiresAppleSilicon": true,
        "requiredCapabilities": ["containers.stop"]
      },
      "securityImpact": "mutating",
      "labelKey": "parameter.containers.stop.timeoutSeconds.label",
      "conciseHelpKey": "parameter.containers.stop.timeoutSeconds.concise",
      "detailedHelpKey": "parameter.containers.stop.timeoutSeconds.detail",
      "validationErrorKey": "parameter.containers.stop.timeoutSeconds.validation",
      "recoveryKey": "parameter.containers.stop.timeoutSeconds.recovery"
    }
  ]
}
```

`scripts/check-contract-coverage.swift` decodes both files, rejects duplicate operation or parameter IDs, rejects empty help keys, compares exact operation sets, and exits nonzero with a sorted list of missing/extra IDs. Its terminal success line is exactly:

```text
Contract coverage PASS: apple/container 1.1.0, 61 operations, 0 missing, 0 extra
```

- [x] **Step 4: Verify the snapshot and schema**

Run: `swift test --filter ContractRepositoryTests && swift scripts/check-contract-coverage.swift Config/contracts/apple-container-1.1.0-acceptance.json Sources/MCContracts/Resources/apple-container-1.1.0.json`

Expected: PASS with the exact terminal success line above.

- [x] **Step 5: Commit**

```bash
git add Config/contracts Sources/MCContracts/Resources Tests/MCContractsTests scripts/check-contract-coverage.swift
git commit -m "feat: inventory Apple container 1.1.0 contract"
```

### Task 5: Define the XcodeGen application graph

**Files:**
- Create: `project.yml`
- Create: `App/MacContainer/MacContainerApp.swift`
- Create: `App/MacContainer/MacContainer.entitlements`
- Create: `App/PrivilegedHelper/main.swift`
- Create: `App/PrivilegedHelper/PrivilegedHelper.entitlements`
- Create: `App/PrivilegedHelper/container.matrixreligio.com.helper.plist`
- Create: `App/UpdateAgent/main.swift`
- Create: `App/UpdateAgent/UpdateAgent.entitlements`
- Create: `App/UpdateAgent/container.matrixreligio.com.update-agent.plist`
- Create: `Tests/MacContainerIntegrationTests/BuildSmokeTests.swift`
- Create: `Tests/MacContainerUITests/LaunchTests.swift`

- [x] **Step 1: Write failing target smoke tests**

```swift
import XCTest

final class BuildSmokeTests: XCTestCase {
    func testReleaseIdentityIsEmbedded() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "container.matrixreligio.com")
    }
}
```

```swift
import XCTest

final class LaunchTests: XCTestCase {
    func testApplicationLaunchesInFakeRuntimeMode() {
        let app = XCUIApplication()
        app.launchArguments = ["--fake-runtime", "--reset-test-state"]
        app.launch()
        XCTAssertTrue(app.windows["main-window"].waitForExistence(timeout: 10))
    }
}
```

- [x] **Step 2: Run and verify RED**

Run: `xcodegen generate --spec project.yml`

Expected: FAIL because `project.yml` does not exist.

- [x] **Step 3: Create the project graph and minimal launch surface**

`project.yml` must set:

```yaml
name: MacContainer
options:
  deploymentTarget:
    macOS: "26.0"
  createIntermediateGroups: true
  developmentLanguage: en
settings:
  base:
    DEVELOPMENT_TEAM: 4DUQGD879H
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    ENABLE_HARDENED_RUNTIME: YES
    CODE_SIGN_STYLE: Manual
    CODE_SIGN_IDENTITY: "Developer ID Application"
packages:
  MacContainerCore:
    path: .
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    exactVersion: "2.9.4"
  SwiftTerm:
    url: https://github.com/migueldeicaza/SwiftTerm
    exactVersion: "1.13.0"
targets:
  MacContainer:
    type: application
    platform: macOS
    sources: [App/MacContainer]
    dependencies:
      - package: MacContainerCore
        product: MCModel
      - package: MacContainerCore
        product: MCContracts
      - package: MacContainerCore
        product: MCContainerBridge
      - package: MacContainerCore
        product: MCCompatibility
      - package: MacContainerCore
        product: MCSystemLifecycle
      - package: MacContainerCore
        product: MCAppCore
      - package: Sparkle
        product: Sparkle
      - package: SwiftTerm
        product: SwiftTerm
      - target: MacContainerPrivilegedHelper
        embed: false
      - target: MacContainerUpdateAgent
        embed: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: container.matrixreligio.com
        PRODUCT_NAME: MacContainer
        ENABLE_APP_SANDBOX: NO
        CODE_SIGN_ENTITLEMENTS: App/MacContainer/MacContainer.entitlements
        INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.developer-tools
        INFOPLIST_KEY_NSHumanReadableCopyright: Copyright 2026 MatrixReligio LLC. Licensed under Apache-2.0.
    info:
      path: App/MacContainer/Info.plist
      properties:
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        LSMinimumSystemVersion: "26.0"
        CFBundleLocalizations: [en, zh-Hans, zh-Hant, ja, ko]
        SUFeedURL: https://github.com/matrixreligio/macContainer/releases/latest/download/appcast.xml
        SUEnableAutomaticChecks: true
        SUScheduledCheckInterval: 86400
        SMPrivilegedExecutables:
          container.matrixreligio.com.helper: anchor apple generic and identifier "container.matrixreligio.com.helper" and certificate leaf[subject.OU] = "4DUQGD879H"
    postCompileScripts:
      - name: Embed helper and update agent
        inputFiles:
          - $(BUILT_PRODUCTS_DIR)/MacContainerPrivilegedHelper
          - $(BUILT_PRODUCTS_DIR)/MacContainerUpdateAgent
          - $(SRCROOT)/App/PrivilegedHelper/container.matrixreligio.com.helper.plist
          - $(SRCROOT)/App/UpdateAgent/container.matrixreligio.com.update-agent.plist
        outputFiles:
          - $(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Library/PrivilegedHelperTools/container.matrixreligio.com.helper
          - $(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Library/LoginItems/container.matrixreligio.com.update-agent
          - $(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Library/LaunchDaemons/container.matrixreligio.com.helper.plist
          - $(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Library/LaunchAgents/container.matrixreligio.com.update-agent.plist
        script: |
          set -euo pipefail
          helper_dir="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Library/PrivilegedHelperTools"
          agent_dir="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Library/LoginItems"
          daemon_dir="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Library/LaunchDaemons"
          launch_agent_dir="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Library/LaunchAgents"
          mkdir -p "$helper_dir" "$agent_dir" "$daemon_dir" "$launch_agent_dir"
          ditto "$BUILT_PRODUCTS_DIR/MacContainerPrivilegedHelper" "$helper_dir/container.matrixreligio.com.helper"
          ditto "$BUILT_PRODUCTS_DIR/MacContainerUpdateAgent" "$agent_dir/container.matrixreligio.com.update-agent"
          ditto "$SRCROOT/App/PrivilegedHelper/container.matrixreligio.com.helper.plist" "$daemon_dir/container.matrixreligio.com.helper.plist"
          ditto "$SRCROOT/App/UpdateAgent/container.matrixreligio.com.update-agent.plist" "$launch_agent_dir/container.matrixreligio.com.update-agent.plist"
  MacContainerPrivilegedHelper:
    type: tool
    platform: macOS
    sources: [App/PrivilegedHelper]
    dependencies:
      - package: MacContainerCore
        product: MCModel
      - package: MacContainerCore
        product: MCSystemLifecycle
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: container.matrixreligio.com.helper
        CODE_SIGN_ENTITLEMENTS: App/PrivilegedHelper/PrivilegedHelper.entitlements
  MacContainerUpdateAgent:
    type: tool
    platform: macOS
    sources: [App/UpdateAgent]
    dependencies:
      - package: MacContainerCore
        product: MCModel
      - package: MacContainerCore
        product: MCSystemLifecycle
      - package: MacContainerCore
        product: MCCompatibility
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: container.matrixreligio.com.update-agent
        CODE_SIGN_ENTITLEMENTS: App/UpdateAgent/UpdateAgent.entitlements
  MacContainerIntegrationTests:
    type: bundle.unit-test
    platform: macOS
    sources: [Tests/MacContainerIntegrationTests]
    dependencies: [{target: MacContainer}]
  MacContainerUITests:
    type: bundle.ui-testing
    platform: macOS
    sources: [Tests/MacContainerUITests]
    dependencies: [{target: MacContainer}]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: container.matrixreligio.com.ui-tests
schemes:
  MacContainer:
    build:
      targets:
        MacContainer: all
        MacContainerPrivilegedHelper: all
        MacContainerUpdateAgent: all
    test:
      targets: [MacContainerIntegrationTests, MacContainerUITests]
```

The app entry creates a `WindowGroup("MacContainer", id: "main-window")` with an accessibility identifier `main-window`. Helper and agent entry points exit successfully only in `--build-smoke-test` mode at this stage; all other invocations log an unimplemented-service error and exit `EX_UNAVAILABLE`, preventing accidental privilege behavior.

The helper plist uses `Label` and `MachServices` equal to `container.matrixreligio.com.helper`, plus `BundleProgram` equal to `Contents/Library/PrivilegedHelperTools/container.matrixreligio.com.helper`, with `RunAtLoad=false` and `KeepAlive=false`. The update-agent plist uses label `container.matrixreligio.com.update-agent`, `BundleProgram` equal to `Contents/Library/LoginItems/container.matrixreligio.com.update-agent`, and `StartInterval=86400`; neither plist contains a caller-controlled path or environment.

- [x] **Step 4: Generate and build without signing**

Run: `xcodegen generate --spec project.yml && xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -configuration Debug CODE_SIGNING_ALLOWED=NO build`

Expected: BUILD SUCCEEDED.

- [x] **Step 5: Commit generated project and sources**

```bash
git add project.yml MacContainer.xcodeproj App Tests/MacContainerIntegrationTests Tests/MacContainerUITests
git commit -m "build: compose app helper and agent targets"
```

### Task 6: Add pinned developer tooling and deterministic checks

**Files:**
- Create: `.swiftformat`
- Create: `.swiftlint.yml`
- Create: `Config/release-tools.json`
- Create: `scripts/bootstrap-tools.sh`
- Create: `scripts/check-generated-project.sh`
- Create: `scripts/check-no-container-cli.sh`
- Create: `scripts/check-repository.sh`
- Test: `Tests/ToolingTests/check-no-container-cli.bats`

- [x] **Step 1: Write the failing forbidden-backend test**

```bash
#!/bin/zsh
set -euo pipefail
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/Sources"
print -r -- 'Process.run(URL(fileURLWithPath: "/usr/local/bin/container"))' > "$fixture/Sources/Bad.swift"
if scripts/check-no-container-cli.sh "$fixture"; then
  print -u2 -- "expected forbidden CLI scanner to fail"
  exit 1
fi
rm "$fixture/Sources/Bad.swift"
print -r -- 'let name = "container"' > "$fixture/Sources/Good.swift"
scripts/check-no-container-cli.sh "$fixture"
```

- [x] **Step 2: Run and verify RED**

Run: `zsh Tests/ToolingTests/check-no-container-cli.bats`

Expected: FAIL because the scanner does not exist.

- [x] **Step 3: Add deterministic tooling**

`Config/release-tools.json` pins:

```json
{
  "xcodegen": {"version": "2.45.4", "sha256": "090ec29491aad50aec10631bf6e62253fed733c50f3aab0f5ffc86bc170bdbef"},
  "swiftFormat": {"version": "0.62.1", "sha256": "7cb1cb1fae04932047c7015441c543848e8e60e1572d808d080e0a1f1661114a"},
  "swiftLint": {"version": "0.65.0", "sha256": "d6cb0aa7a2f5f1ef306fc9e37bcb54dc9a26facc8f7784ac0c3dd3eccf5c6ba6"},
  "sparkle": {"version": "2.9.4", "sha256": "ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9"},
  "swiftTerm": {"version": "1.13.0"}
}
```

The scanner only inspects production Swift/shell files and rejects invocations of `/usr/local/bin/container`, `update-container.sh`, or `uninstall-container.sh`; it permits literals in contracts, tests, docs, and the exact helper invocation of `/usr/sbin/installer`. `check-generated-project.sh` generates into a temporary project-local directory, diffs it against committed `MacContainer.xcodeproj`, and cleans via `trap`. `bootstrap-tools.sh` downloads into `.tools/downloads`, verifies SHA-256 before extraction, and never calls Homebrew.

- [x] **Step 4: Run the tooling suite**

Run: `zsh Tests/ToolingTests/check-no-container-cli.bats && scripts/check-generated-project.sh && scripts/check-repository.sh`

Expected: PASS; no global package manager is invoked and temporary fixture paths are removed.

- [x] **Step 5: Commit**

```bash
git add .swiftformat .swiftlint.yml Config/release-tools.json scripts Tests/ToolingTests
git commit -m "ci: add pinned deterministic verification"
```

### Task 6A: Establish the application icon asset pipeline

**Files:**
- Create: `Design/AppIcon/MacContainer-master.png`
- Create: `Design/AppIcon/README.md`
- Create: `App/MacContainer/Resources/Assets.xcassets/Contents.json`
- Create: `App/MacContainer/Resources/Assets.xcassets/AppIcon.appiconset/*`
- Create: `scripts/generate-app-icon.swift`
- Create: `scripts/check-app-icon.swift`
- Test: `Tests/ToolingTests/check-app-icon.bats`
- Test: `Tests/MacContainerIntegrationTests/BuildSmokeTests.swift`

- [x] **Step 1: Add failing asset-pipeline and bundle-wiring tests**

The tool test requires ten macOS icon slots, exact pixel sizes, sRGB PNG data, transparent corners, an opaque center, deterministic regeneration, and cleanup of its temporary output. The integration test requires the built bundle to name `AppIcon`.

- [x] **Step 2: Run and verify RED**

Run the tool test before generator/checker scripts exist and the integration test before the asset catalog is wired. Both must fail for the intended missing behavior.

- [x] **Step 3: Add the reviewed master and deterministic asset generator**

Preserve the generated master and prompt provenance under `Design/AppIcon`. Render a macOS squircle alpha mask and all ten canonical icon files from the master using project-local Swift/CoreGraphics code; do not require Python, a global image utility, or network access.

- [x] **Step 4: Verify assets and signed application wiring**

Run the negative/positive tool tests twice, compare rebuild hashes, regenerate the Xcode project, build the signed Debug application, run integration/UI tests, and inspect the compiled asset catalog and final bundle metadata.

- [x] **Step 5: Commit**

```bash
git add Design App/MacContainer/Resources project.yml MacContainer.xcodeproj scripts/generate-app-icon.swift scripts/check-app-icon.swift Tests/ToolingTests/check-app-icon.bats Tests/MacContainerIntegrationTests docs/superpowers/plans/2026-07-15-maccontainer-01-foundation.md
git commit -m "design: add deterministic MacContainer app icon"
```

### Task 7: Create the public GitHub repository and hosted CI

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/upstream-monitor.yml`
- Create: `.github/dependabot.yml`
- Create: `.github/CODEOWNERS`

- [x] **Step 1: Verify repository absence and authentication**

Run: `gh auth status && ! gh repo view matrixreligio/macContainer --json nameWithOwner,isPrivate`

Expected: authenticated GitHub access and exit status proving the repository is not yet present. If it now exists, verify it is public and owned by `matrixreligio`; never replace an unrelated repository.

- [x] **Step 2: Add failing workflow policy checks**

Add `scripts/check-workflow-policy.sh` to reject unpinned third-party actions, non-`macos-26` test runners, secret-bearing PR jobs, and workflows that omit `scripts/check-repository.sh`. Run it before workflows exist.

Run: `scripts/check-workflow-policy.sh`

Expected: FAIL with `missing workflow: .github/workflows/ci.yml`.

- [x] **Step 3: Add workflows and repository policy**

`ci.yml` uses least-privilege `contents: read`, cancels stale branch runs, installs checksum-pinned tools, runs package tests with coverage, generates the Xcode project, builds Debug and Release unsigned, runs integration/UI fake-runtime tests, runs formatting/lint/localization/license/security checks, uploads test summaries only, and checks a clean worktree. Every `uses:` entry is pinned to a full commit SHA.

`upstream-monitor.yml` runs weekly and manually with `issues: write` only at the job that creates or updates a draft compatibility issue. It records new Apple release metadata but cannot modify the embedded allowlist, push code, or mark compatibility.

`.github/CODEOWNERS` contains:

```text
* @hejundev
/.github/ @hejundev
/App/PrivilegedHelper/ @hejundev
/Sources/MCSystemLifecycle/ @hejundev
/Config/compatibility/ @hejundev
/scripts/release* @hejundev
```

- [x] **Step 4: Verify policy, create repository, and push**

Run:

```bash
scripts/check-workflow-policy.sh
gh repo create matrixreligio/macContainer --public --source=. --remote=origin --description "Native SwiftUI management for Apple container on macOS" --push
gh repo edit matrixreligio/macContainer --enable-issues --enable-wiki=false --enable-projects=false --delete-branch-on-merge
gh repo view matrixreligio/macContainer --json nameWithOwner,isPrivate,defaultBranchRef,url
```

Expected: JSON reports `matrixreligio/macContainer`, `isPrivate: false`, and default branch `main`.

- [x] **Step 5: Commit workflow policy before or immediately after initial push**

```bash
git add .github scripts/check-workflow-policy.sh
git commit -m "ci: establish hosted verification and repository policy"
git push -u origin main
```

### Task 8: Add the open-source governance baseline

**Files:**
- Create: `LICENSE`, `NOTICE`, `THIRD_PARTY_NOTICES`
- Create: `README.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `SUPPORT.md`, `GOVERNANCE.md`, `CHANGELOG.md`, `ARCHITECTURE.md`, `DEVELOPMENT.md`, `CODE_STYLE.md`, `RELEASE.md`, `PRIVACY.md`, `docs/en/THREAT_MODEL.md`
- Create: `.github/ISSUE_TEMPLATE/bug.yml`, `.github/ISSUE_TEMPLATE/feature.yml`, `.github/pull_request_template.md`
- Create: `scripts/check-open-source-baseline.sh`

- [x] **Step 1: Add a failing document-presence test**

The checker requires every file above, verifies the Apache-2.0 SPDX identifier, rejects broken local Markdown links, verifies every support/security contact is `contact@matrixreligio.com`, and checks that SECURITY documents supported branches and a private reporting path.

Run: `scripts/check-open-source-baseline.sh`

Expected: FAIL listing all absent required files in sorted order.

- [x] **Step 2: Add the Apache-2.0 and governance corpus**

Use the unmodified Apache License 2.0 text. `NOTICE` identifies `MacContainer`, copyright year 2026, MatrixReligio LLC, and contact email. `THIRD_PARTY_NOTICES` initially records Apple container 1.1.0 (Apache-2.0), Sparkle 2.9.4 (MIT), SwiftTerm 1.13.0 (MIT), plus a machine-generated transitive section that plan 07 verifies from resolved dependencies.

`SECURITY.md` states supported versions, `contact@matrixreligio.com`, a 2-business-day acknowledgement target, coordinated disclosure, no public security issue details, and the absence of telemetry. `PRIVACY.md` states local processing, direct user-requested GitHub/registry traffic, Keychain credential storage, diagnostic redaction, and no default telemetry.

- [x] **Step 3: Verify the corpus**

Run: `scripts/check-open-source-baseline.sh`

Expected: PASS with `Open-source baseline PASS: 16 policy documents, 0 broken links`.

- [x] **Step 4: Commit**

```bash
git add LICENSE NOTICE THIRD_PARTY_NOTICES README.md CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md SUPPORT.md GOVERNANCE.md CHANGELOG.md ARCHITECTURE.md DEVELOPMENT.md CODE_STYLE.md RELEASE.md PRIVACY.md docs/en .github/ISSUE_TEMPLATE .github/pull_request_template.md scripts/check-open-source-baseline.sh
git commit -m "docs: establish open-source governance baseline"
```

### Task 9: Complete Stage 0 and Stage 1 reviews

**Files:**
- Create: `docs/reviews/stage-0.md`
- Create: `docs/reviews/stage-1.md`

- [x] **Step 1: Run Stage 0 contract verification**

Run:

```bash
swift test --filter ContractRepositoryTests
swift scripts/check-contract-coverage.swift Config/contracts/apple-container-1.1.0-acceptance.json Sources/MCContracts/Resources/apple-container-1.1.0.json
rg -n 'TODO|TBD|implement later|similar to' Config/contracts Sources/MCContracts Tests/MCContractsTests
```

Expected: tests PASS, exact 61-operation coverage, and `rg` exits 1 with no matches.

- [x] **Step 2: Review contract evidence against upstream 1.1.0**

Inspect every operation source path recorded in the acceptance JSON against the exact `1.1.0` checkout. Record the upstream file SHA-256 values, parameter counts per domain, and any native rendering flags intentionally represented as UI table/export choices. Fix and rerun on every mismatch.

- [x] **Step 3: Commit Stage 0 PASS report**

```bash
git add docs/reviews/stage-0.md
git commit -m "docs: close upstream contract review"
```

- [ ] **Step 4: Run Stage 1 architecture and supply-chain verification**

Run:

```bash
swift test --parallel
scripts/check-repository.sh
xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -configuration Release CODE_SIGNING_ALLOWED=NO build
git diff --check
git status --short
```

Expected: all commands PASS and final status is empty.

- [ ] **Step 5: Review and close Stage 1**

Review module dependency direction, bundle identities, absence of App Sandbox, helper/update-agent containment, exact pins, action SHAs, secret permissions, generated-project drift, OSS policy links, and public repository settings. Resolve all findings, write `Gate: PASS`, commit, push, and verify the current GitHub Actions run succeeds.

```bash
git add docs/reviews/stage-1.md
git commit -m "docs: close foundation review"
git push origin main
gh run list --workflow ci.yml --branch main --limit 1 --json databaseId,status,conclusion,headSha,url
```

Expected: the run for the pushed head SHA has `conclusion: success`.
