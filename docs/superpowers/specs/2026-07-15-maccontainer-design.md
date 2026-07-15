# MacContainer Product and Technical Design Specification

**Date:** 2026-07-15  
**Product:** MacContainer  
**Repository:** `matrixreligio/macContainer`  
**Bundle identifier:** `com.matrixreligio.MacContainer`  
**Document status:** The product direction was approved on 2026-07-15. This written specification is ready for user review before implementation planning.

## 1. Executive summary

MacContainer is a native SwiftUI application for Apple silicon Macs running macOS 26 or later. It exposes every official built-in operation in Apple `container` 1.1.0 through typed native controls and direct Swift/XPC APIs. The application does not use the `container` command-line executable as its operational backend.

The product is designed for two audiences:

- People new to containers, who start from safe scenario templates and only see the fields required for their goal.
- Experienced users, who can inspect and change every supported option, open interactive terminal sessions, and manage all resource types.

MacContainer also owns the complete lifecycle of the Apple `container` runtime:

- Install only an Apple-signed and notarized package.
- Automatically upgrade only to a version already proven compatible with the installed MacContainer version.
- Run post-upgrade API compatibility probes and roll back on failure.
- Completely uninstall all product-controlled runtime artifacts and refuse to report success while any residue remains.

MacContainer itself is distributed as a signed and notarized Developer ID application, updates through an EdDSA-signed Sparkle appcast, and is built and released from a public GitHub repository with pinned, auditable CI inputs.

## 2. Authoritative upstream baseline

The initial implementation targets the following verified baseline:

- Apple `container` stable release: `1.1.0`, published 2026-07-06.
- Apple `container` source snapshot also reviewed: `main` commit `608902412d61761ebd1efc285a9d0a1727e6e2c1` from 2026-07-13.
- Supported host: Apple silicon running macOS 26 or later.
- Direct upstream Swift products include `ContainerAPIClient`, `ContainerBuild`, `ContainerPersistence`, `ContainerResource`, `ContainerXPC`, and `MachineAPIClient`.
- Official installer receipt: `com.apple.container-installer`.
- Official installer location: `/usr/local`.
- Current 1.1.0 installer signer: `Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)`.
- Current 1.1.0 installer is trusted by Apple notarization.
- Current 1.1.0 signed installer SHA-256: `0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714`.

Primary sources:

- https://github.com/apple/container
- https://github.com/apple/container/releases/tag/1.1.0
- https://github.com/apple/container/blob/1.1.0/Package.swift
- https://github.com/apple/container/blob/1.1.0/docs/command-reference.md
- https://github.com/apple/container/blob/1.1.0/docs/container-system-config.md
- https://github.com/apple/container/blob/1.1.0/scripts/update-container.sh
- https://github.com/apple/container/blob/1.1.0/scripts/uninstall-container.sh

Upstream `main` is monitored but never consumed automatically. Product code and its compatibility contract pin exact reviewed versions.

## 3. Goals

1. Provide a polished, HIG-aligned SwiftUI interface for every official built-in Apple `container` 1.1.0 operation.
2. Perform runtime operations through direct Swift/XPC APIs, not by launching the `container` CLI.
3. Make common workflows approachable through safe, explainable scenario templates.
4. Expose every supported parameter in Advanced mode.
5. Put an information button beside every parameter that explains purpose, default, format, valid range, dependencies, conflicts, security impact, and platform limitations.
6. Support installation, manual upgrade, compatible automatic upgrade, downgrade for recovery, rollback, and verified complete uninstallation of the Apple runtime.
7. Prevent runtime upgrades from making MacContainer unusable.
8. Follow the operating system language by default and support in-app selection of English, Simplified Chinese, Traditional Chinese, Japanese, and Korean.
9. Provide complete open-source governance, security, contribution, release, license, and support documentation.
10. Build, test, sign, notarize, release, and publish Sparkle updates through GitHub Actions using the MatrixReligio Apple Developer configuration.
11. Validate the completed application with local macOS UI automation and real-runtime end-to-end tests without leaving the development machine altered.
12. Use test-driven development, a visible task checklist, a review after every stage, and a final comprehensive review.

## 4. Explicit non-goals and boundaries

- Intel Macs and macOS versions older than 26 are not supported.
- Mac App Store distribution is not supported because privileged runtime management and Authorization Services are incompatible with the required sandbox model.
- MacContainer does not implement Docker Engine, Kubernetes, Compose, or APIs Apple `container` does not provide.
- Arbitrary third-party CLI plugin commands are not claimed as supported. Every official built-in operation documented for Apple `container` 1.1.0 is supported. A future plugin UI requires a typed plugin schema and a separately reviewed design.
- Automatic upgrades never terminate active containers or machines merely to meet an update deadline.
- Unknown or unverified runtime releases are never installed automatically.
- Historical entries already committed to macOS Unified Logging are managed by macOS and cannot be selectively deleted. They are not considered writable product residue; all product-controlled files, services, processes, credentials, rules, receipts, and caches are included in the zero-residue contract.

## 5. Product information architecture

### 5.1 Main window

The root view is a three-column `NavigationSplitView`:

1. **Sidebar:** top-level domains and global health.
2. **Content table:** searchable and sortable resource collection.
3. **Detail/inspector:** state, configuration, activity, logs, metrics, and actions for the current selection.

The sidebar contains:

- Overview
- Containers
- Images
- Builds
- Machines
- Networks
- Volumes
- Registries
- System

The standard macOS sidebar toggle, menu command, keyboard navigation, toolbar placement, selection persistence, and thin split-view dividers are retained.

### 5.2 Settings

The Settings scene contains:

- **General:** language, appearance-following behavior, default landing section, confirmation policy.
- **Runtime:** installation status, service health, installed version, install, start, stop, complete uninstall.
- **Runtime Updates:** update channel, automatic-update consent, compatible-update state, maintenance behavior, rollback history.
- **Compatibility:** app/runtime versions, compatibility catalog entry, latest probe report, supported capabilities.
- **Defaults and Templates:** default scenario, resource recommendations, custom templates, import and export.
- **Advanced:** app root, log root, configuration source, diagnostic export, helper authorization status.
- **About:** app version, update check, licenses, privacy, support, and source code.

### 5.3 Common interaction patterns

- Tables support search, sort, multi-selection, contextual menus, drag and drop where meaningful, and keyboard shortcuts.
- Destructive actions show the affected resources, consequences, and recovery options before confirmation.
- Long-running work appears in an Activity Center rather than blocking the whole window.
- Activities report stage, progress, elapsed time, cancellation capability, and structured failure recovery.
- Empty states teach the next useful action.
- The app never exposes terminal-form command strings as the primary way to complete a task.

## 6. Simple Mode and scenario templates

Simple Mode is the default. Users choose a goal, image, and required local resources; MacContainer generates a typed request. The generated settings are always reviewable before execution.

### 6.1 Built-in templates

| Template | Generated behavior |
| --- | --- |
| Quick Run | Starts from compatible upstream defaults, applies the host resource recommendation caps, generates a readable name, and asks only for image and foreground/background behavior. |
| Interactive Shell | Enables TTY and interactive input, discovers a shell from image metadata with documented fallbacks, and removes the temporary container after exit by default. |
| Web Service | Runs detached, requires an explicit port mapping, offers a persistent volume, and validates port conflicts before creation. |
| Development Workspace | Mounts a user-selected directory, sets the work directory, recommends development resources, and offers SSH forwarding only after explicit consent. |
| Local Database | Creates or selects a named volume, requires an explicit host port, uses a graceful stop timeout, and never enables remove-on-exit. |
| Restricted/Secure Container | Uses a read-only root, drops all capabilities, supplies a temporary `/tmp` filesystem, disables networking by default, and permits only explicit read-only host mounts until the user changes the security profile. |
| Cross-Architecture | Selects `linux/amd64` and Rosetta only when supported, explains the performance and compatibility trade-off, and rejects unsupported hosts. |
| Linux Machine Workspace | Creates a persistent machine, explains home-directory sharing, defaults sharing to read/write only after user confirmation, and gates nested virtualization on supported hardware and kernel capability. |

### 6.2 Resource recommendation algorithm

The recommendation engine is deterministic and pure:

- It reads host logical CPU count, physical memory, Apple silicon generation, macOS version, and upstream capabilities.
- It leaves at least one logical CPU for macOS when the host has more than two logical CPUs.
- It reserves the greater of 4 GiB or 25 percent of physical memory for macOS and other applications.
- A generated workload never receives more than half of total host memory without an explicit user override.
- Quick workloads target up to 2 CPUs and 2 GiB.
- Development workloads target up to 4 CPUs and 4 GiB.
- Database workloads target 2 CPUs and 2 GiB before image-specific customization.
- Builder defaults begin with the upstream 2 CPU and 2048 MB defaults.
- Values are reduced on smaller hosts rather than violating the reserve.
- Overrides outside the recommendation remain possible in Advanced mode and display a resource-pressure warning.

### 6.3 Template transparency and persistence

- The review screen shows every generated value and its source: upstream default, scenario rule, hardware recommendation, image metadata, or user override.
- The review screen shows a concise diff from upstream defaults.
- Users can save, duplicate, rename, export, and import custom templates.
- Template files contain no passwords, access tokens, SSH keys, or registry credentials.
- Template schemas include a version and migrate only through tested, lossless migrations.
- A template that cannot be represented safely after an upstream change is disabled with an explanation instead of being silently rewritten.

## 7. Complete operation coverage

The initial compatibility contract covers these official built-in operations:

| Domain | Operations |
| --- | --- |
| Core | run, build |
| Containers | create, start, stop, kill, delete, list, exec, export, logs, inspect, stats, copy, prune |
| Images | list, pull, push, save, load, tag, delete, prune, inspect |
| Builder | start, status, stop, delete |
| Networks | create, delete, prune, list, inspect |
| Volumes | create, delete, prune, list, inspect |
| Registries | login, logout, list |
| Machines | create, run, list, inspect, set, set-default, logs, stop, delete |
| System | start, stop, status, version, logs, disk usage |
| System DNS | create, delete, list |
| System Kernel | set from recommended release, local binary, local archive, or verified remote archive |
| System configuration | view and edit every documented TOML key, validate, preview, save, and apply after controlled service restart |

The official `system property list` behavior is represented by the typed configuration view and its native export action. List-format and quiet flags that only control CLI rendering are represented as native table/export choices rather than copied literally. Every operation-affecting option is represented.

## 8. Parameter contract and information help

### 8.1 Versioned contract

`MCContracts` owns a versioned `UpstreamContract` for each supported runtime. Every parameter record contains:

- Stable operation and parameter identifiers.
- CLI name and aliases for traceability only.
- Native value type and cardinality.
- Required or optional status.
- Upstream default.
- Valid range or grammar.
- Repeatability and ordering behavior.
- Dependencies and conflicting options.
- macOS, hardware, kernel, image, and runtime-version availability.
- Security and data-loss impact.
- Localization keys for label, concise help, detailed help, validation error, and recovery.

The contract is generated from a reviewed snapshot, committed, and treated as source-controlled product data. Runtime discovery can narrow availability but cannot invent undocumented behavior.

### 8.2 Information button

Every editable parameter row includes a consistent `ParameterHelpButton` using the SF Symbol `info.circle`:

- Click opens a keyboard-accessible popover with purpose, default, accepted values, examples, limitations, conflicts, and risk.
- Hover provides a concise native Help tooltip.
- VoiceOver reads a meaningful label such as “Memory option information.”
- The button is reachable in Full Keyboard Access order.
- Destructive or security-sensitive options add a visible warning in the form, not only inside the popover.

Automated contract tests fail if any supported parameter lacks the button or any of the five localizations.

## 9. Technical architecture

### 9.1 Module boundaries

| Module or target | Responsibility | Dependencies |
| --- | --- | --- |
| `MCModel` | App-owned value types, validation results, errors, activities, resource summaries | Foundation only where practical |
| `MCContracts` | Versioned upstream operations, parameters, capabilities, compatibility entries | MCModel |
| `MCTemplates` | Pure scenario-template and resource-recommendation engine | MCModel, MCContracts |
| `MCContainerBridge` | Direct adapters for Apple container Swift/XPC APIs | Pinned Apple container products |
| `MCSystemLifecycle` | Install, upgrade, rollback, uninstall transactions and residue audits | MCModel, MCContracts, MCCompatibility |
| `MCCompatibility` | Compatibility catalog, preflight decisions, post-install probes | MCModel, MCContracts, MCContainerBridge |
| `MCAppCore` | Observable app state, orchestration, activity center, persistence | All non-UI modules |
| `MacContainer` | SwiftUI scenes, views, commands, forms, localization | MCAppCore, Sparkle, SwiftTerm adapter |
| `MacContainerPrivilegedHelper` | Narrow privileged operations over authenticated XPC | MCSystemLifecycle protocol types |
| `MacContainerUpdateAgent` | Scheduled runtime update checks and idle-state coordination | MCSystemLifecycle, MCCompatibility |

Files remain focused on one resource, form, transaction, or reusable control. The implementation plan will assign exact file paths and avoid monolithic managers or views.

### 9.2 Direct upstream bridge

- `ContainerClient` handles container create/list/get/bootstrap/stop/kill/delete/process/log/stats/copy/export operations.
- `ClientImage` handles image list/get/pull/push/save/load/tag/delete/unpack operations.
- `NetworkClient` handles networks.
- `ClientVolume` handles volumes.
- `MachineClient` handles machine lifecycle.
- `ContainerBuild` handles builds.
- `ContainerPersistence` parses and validates system configuration.
- Direct keychain APIs and the upstream credential model handle registry credentials.

MacContainer implements its own typed `SystemServiceController` based on the upstream service protocol. It uses the installed `/usr/local/bin/container-apiserver`, `LaunchPlist`, `ServiceManager`, `ConfigurationLoader`, and `ClientHealthCheck` directly. Calling `Application.SystemStart` is not acceptable because it resolves helpers relative to `CommandLine.executablePath` and would point at MacContainer rather than the installed Apple runtime.

No production operation launches `/usr/local/bin/container`, `update-container.sh`, or `uninstall-container.sh`. The only allowed external system executable in lifecycle code is the Apple `/usr/sbin/installer` process invoked by the privileged helper for a preverified package; it is system installation plumbing, not the container CLI.

### 9.3 Interactive processes

Interactive container and machine sessions connect the upstream process file handles to a pinned SwiftTerm terminal engine hosted through `NSViewRepresentable`:

- TTY resize events call the upstream resize API.
- Input is sent directly to the process.
- Output streams directly into the terminal.
- Window close offers detach or terminate according to process capability.
- Noninteractive execution uses a native output view with stdout/stderr separation and export.

The surrounding application remains SwiftUI-native; AppKit interoperation is isolated to the terminal control.

### 9.4 State and concurrency

An `OperationCoordinator` actor serializes conflicting work using typed keys:

- A global lifecycle lock for install, upgrade, rollback, and uninstall.
- A system-service lock for start, stop, and configuration apply.
- Per-resource locks for mutating a container, image reference, network, volume, builder, or machine.
- Read operations may run concurrently when the upstream service permits.

App state uses Swift Observation on the main actor. Upstream calls run in structured tasks, cancellation is propagated, and no detached task owns lifecycle state.

### 9.5 Errors and recovery

Every failure becomes a structured `UserFacingError` with:

- Domain and operation.
- Safe localized title and explanation.
- Underlying diagnostic detail suitable for an export, with secrets redacted.
- Whether retry is safe.
- One or more concrete recovery actions.
- Activity identifier and timestamp.

Partial success is represented explicitly. Destructive batch operations report each affected resource rather than collapsing multiple failures into one generic message.

## 10. Privileged helper and trust boundary

### 10.1 Service model

The app bundles a signed launch daemon registered through `SMAppService`. Registration requires one-time administrator approval. The helper:

- Has no network entitlement and performs no downloads.
- Accepts only allowlisted typed XPC requests.
- Never accepts a caller-supplied executable path, shell fragment, arbitrary deletion path, or environment.
- Validates the caller audit token, bundle identifier, Team ID `4DUQGD879H`, and designated requirement.
- Revalidates all package, path, and manifest inputs after crossing the XPC boundary.
- Opens files with no-follow semantics and verifies identity after opening to resist symlink and time-of-check/time-of-use attacks.
- Records an append-only transaction log without secrets.

### 10.2 Allowed privileged operations

- Install a verified package through `/usr/sbin/installer`.
- Remove payload paths that appear in both the verified package receipt and the compatibility manifest.
- Forget `com.apple.container-installer` after payload removal.
- Create and delete explicitly namespaced `/etc/resolver/containerization.*` entries.
- Apply and remove the exact `com.apple.container` packet-filter rules owned by the runtime.
- Remove known empty runtime directories.

Every other action is rejected.

## 11. Runtime installation

1. Confirm Apple silicon and macOS 26 or later.
2. Fetch release metadata from `api.github.com/repos/apple/container` over TLS.
3. Select only a signed installer asset named by the embedded compatibility entry.
4. Download into a private, randomly named temporary directory.
5. Verify the expected SHA-256 from the embedded compatibility entry.
6. Verify Developer ID Installer trust, Apple notarization, Team ID, allowed signer identity, package version, receipt ID, install location, and payload manifest.
7. Display version, source, signer, disk impact, and administrator-approval explanation.
8. Pass an already-open file descriptor and immutable manifest to the helper.
9. Install the package.
10. Verify receipt version and every expected payload.
11. Start the system service directly and install the recommended kernel/init image through direct APIs.
12. Run compatibility probes.
13. Delete the package and temporary directory.

Unsigned assets are always rejected. A signer rotation requires a reviewed MacContainer release with an updated compatibility entry; the updater does not learn a new signer from mutable remote metadata.

## 12. MacContainer and runtime updates

### 12.1 MacContainer application updates

- Sparkle is pinned to an exact reviewed version.
- The appcast and archive are signed with a MacContainer-specific EdDSA key.
- The Developer ID application certificate, Team ID `4DUQGD879H`, App Store Connect notarization credentials, and GitHub secret names follow the current `../macGameMaster` configuration.
- The MacContainer Sparkle key is separate from GameMaster’s key.
- A release must be signed, notarized, stapled, Gatekeeper-verified, and represented by a matching signed appcast before publication.

### 12.2 Runtime automatic-upgrade modes

The Runtime Updates setting offers:

- Check only.
- Download compatible updates and notify.
- Automatically install compatible updates when idle.

The third mode is recommended during onboarding but becomes active only after explicit user consent and helper authorization.

The update agent checks once per day and when the user requests a check. It applies randomized delay to avoid synchronized GitHub traffic. Automatic installation proceeds only when:

- The target runtime appears in the embedded compatibility catalog.
- The installed MacContainer version satisfies the entry.
- The package passes all trust checks.
- No containers, builds, builder, or machines are running.
- No lifecycle or destructive resource operation is active.
- A rollback package is available and verified.
- The preflight probe passes.

If work is active, the update remains pending and installs at the next idle opportunity. It never force-stops workloads.

### 12.3 Compatibility catalog

The compatibility catalog is embedded in the signed app. It is not a remotely editable allowlist. Each entry contains:

- Runtime version and release asset identity.
- Package SHA-256.
- Allowed installer signer identity and Team ID.
- Receipt and payload manifest.
- Minimum and maximum MacContainer version.
- Upstream Swift package version used to build the adapter.
- Supported operation and capability set.
- Required macOS and hardware features.
- Storage migration and rollback-safety classification.
- Required preflight and postflight probes.

A scheduled GitHub workflow detects upstream releases and opens a draft compatibility update. It cannot mark the version compatible. Compatibility is promoted only after contract tests and a signed test attestation from the local physical-host suite or an identically configured physical Apple silicon self-hosted runner.

### 12.4 Upgrade transaction

1. Download and verify the target signed package.
2. Capture service, version, resource, receipt, and residue baselines.
3. Keep the previous verified installer package.
4. Create a rollback point required by the compatibility entry. Configuration and metadata are always captured. A full data rollback uses APFS clone-on-write copies when the entry requires it.
5. Recheck idle state immediately before stopping services.
6. Stop services gracefully.
7. Install the target version.
8. Verify receipt, payload, binary version, and API server version agree.
9. Start services.
10. Execute every probe named in the compatibility entry.
11. Commit the transaction and clean rollback data no longer needed.

### 12.5 Compatibility probes

The baseline post-upgrade probe verifies:

- API server health and version.
- Container list and status decoding.
- Image list and metadata decoding.
- Builder status.
- Network list and built-in network decoding.
- Volume list.
- Registry credential enumeration without exposing secrets.
- Machine list and default machine decoding.
- Disk usage.
- System configuration load and validation.
- Capability contract matches the app’s enabled UI.

The physical compatibility suite additionally exercises representative create/run/exec/log/stats/copy/export/delete, build, pull/push, network, volume, machine, DNS, and cleanup flows.

### 12.6 Rollback

Any installation or probe failure triggers rollback:

1. Stop partially started target services.
2. Reinstall the previous verified package.
3. Restore the rollback point when required.
4. Start the previous services.
5. Rerun the previous version’s probes.
6. Preserve a redacted diagnostic report.
7. Mark the target version blocked until a newer MacContainer compatibility catalog supersedes the decision.

MacContainer never reports an upgrade as successful before postflight probes pass.

## 13. Complete runtime uninstallation

### 13.1 User experience

“Completely Uninstall Apple Container” is distinct from stopping services or removing MacContainer itself. The confirmation screen shows:

- Running workloads that must stop.
- Containers, images, machines, volumes, configurations, credentials, and estimated disk space that will be deleted.
- System payload and receipt paths.
- The irreversible nature of full data deletion.
- The expected final residue audit.

The only complete-uninstall path deletes runtime data. A separate advanced “Remove runtime but preserve data for reinstall” action may be offered, but it is explicitly labeled as preservation and never described as complete removal.

### 13.2 Transaction

1. Acquire the global lifecycle lock.
2. Refresh the inventory and request final confirmation.
3. Stop containers and machines gracefully, then stop all `com.apple.container.*` services.
4. Verify no owned process remains.
5. Delete registry credentials in the user session, honoring Keychain authorization prompts.
6. Remove runtime DNS resolver files and packet-filter rules through the helper.
7. Remove receipt payload paths through the helper using intersection of receipt and trusted manifest.
8. Remove the receipt.
9. Remove user application data, `~/.config/container`, defaults, logs outside unified logging, update packages, rollback points, and MacContainer runtime-download caches.
10. Remove empty runtime-owned directories without touching shared `/usr/local/bin` or `/usr/local/libexec` directories.
11. Run an independent residue audit.

### 13.3 Zero-residue audit

The audit must confirm:

- No `com.apple.container.*` launchd service.
- No owned runtime process.
- No `com.apple.container-installer` receipt.
- No payload listed by the receipt or trusted manifest.
- No `~/Library/Application Support/com.apple.container`.
- No `~/.config/container`.
- No `com.apple.container.defaults` domain.
- No `com.apple.container.registry` credential.
- No `/etc/resolver/containerization.*`.
- No owned `com.apple.container` packet-filter anchor or rule.
- No runtime package, rollback point, test fixture, or download cache.
- No runtime-owned nonempty directory.

An inaccessible or unverified location is a failed audit, not an assumed pass. The UI shows “Uninstall incomplete” with exact recovery until all checks pass.

## 14. Configuration and persistence

- Apple runtime configuration is edited in `~/.config/container/config.toml` using typed controls backed by `ContainerPersistence`.
- Before saving, MacContainer renders a preview, validates all fields, writes atomically, and preserves a last-known-good copy.
- Applying configuration performs a controlled restart only after active-workload checks and confirmation.
- MacContainer preferences, templates, compatibility reports, and activity summaries live under its own Application Support directory.
- Registry credentials and app-update secrets never live in preferences or template files.
- Diagnostic exports redact credentials, authorization headers, environment variables marked secret, local usernames where unnecessary, and private host paths where possible.

## 15. Localization

### 15.1 Application

- English is the development and fallback language.
- Required localizations are `en`, `zh-Hans`, `zh-Hant`, `ja`, and `ko`.
- The app follows the operating system language by default.
- Settings can override the language with the same five choices and a System Default option.
- A language change displays a relaunch action and preserves current work safely.
- Every UI string, error, recovery action, parameter help entry, template, accessibility label, menu item, and notification is localized.
- Release CI fails on missing or stale localization entries.

### 15.2 Key multilingual documents

English is authoritative. Each of these documents ships in all five languages:

- README
- User Guide
- Installation Guide
- Runtime Updates and Compatibility
- Complete Uninstallation
- Troubleshooting

Translated documents link back to English and display the source revision they translate. CI verifies parity of headings, internal links, and source revision.

## 16. Accessibility and HIG quality

- Standard SwiftUI controls, Form, Table, NavigationSplitView, toolbar roles, alerts, sheets, and menus are used before custom controls.
- Full Keyboard Access reaches every operation.
- VoiceOver labels and values are explicit where automatic inference is insufficient.
- Status is never communicated by color alone.
- Progress includes a textual phase.
- Reduced Motion and Increase Contrast are respected.
- Window layouts remain usable at the documented minimum width and with large text.
- Every major screen runs `performAccessibilityAudit()` in XCUITest.
- Accessibility Inspector and VoiceOver manual checks supplement automation before release.

## 17. Security and privacy

The threat model includes:

- Malicious or substituted GitHub release assets.
- Unsigned or incorrectly signed packages.
- Signer rotation and certificate expiry.
- Downgrade, replay, and compatibility-catalog substitution.
- XPC caller spoofing.
- Arbitrary privileged path deletion.
- Symlink, hard-link, archive traversal, and time-of-check/time-of-use attacks.
- Helper argument or environment injection.
- Credential and environment-variable leakage.
- Destructive action races with running workloads.
- Partial upgrade, rollback, and uninstall failures.
- Malformed upstream data and terminal escape sequences.

Security requirements:

- Fail closed on trust, compatibility, or cleanup uncertainty.
- Pin every executable dependency used in secret-bearing release jobs.
- Keep the privileged helper networkless and narrowly allowlisted.
- Verify helper and app designated requirements in both directions.
- Redact logs and diagnostics.
- Store registry credentials only in Keychain.
- Use atomic writes and explicit permissions.
- Treat all image, archive, registry, and terminal content as untrusted.
- Publish a coordinated vulnerability disclosure policy and supported-version policy.

No telemetry is collected by default. If crash reporting is ever proposed, it requires a separate design and explicit opt-in.

## 18. Open-source repository standard

The public repository includes:

- `LICENSE` using Apache License 2.0.
- `NOTICE` and `THIRD_PARTY_NOTICES`.
- Dependency license texts for Apple container, Sparkle, SwiftTerm, and transitive shipped code.
- `README.md` and localized key documents.
- `CONTRIBUTING.md`.
- `CODE_OF_CONDUCT.md`.
- `SECURITY.md`.
- `SUPPORT.md`.
- `GOVERNANCE.md`.
- `CHANGELOG.md`.
- `ARCHITECTURE.md`.
- `DEVELOPMENT.md`.
- `CODE_STYLE.md`.
- `RELEASE.md`.
- `PRIVACY.md`.
- Threat model.
- Issue and pull-request templates.
- Dependabot configuration.
- Code owners and review policy.
- Reproducible build, localization, supply-chain, and release instructions.

Generated project files that are intentionally committed must be checked against `project.yml` in CI.

## 19. CI, signing, release, and updates

### 19.1 Hosted CI

GitHub-hosted `macos-26` jobs run:

- Swift build and Swift Testing with code coverage.
- XcodeGen generation and generated-file drift checks.
- Unsigned Debug and Release application builds.
- Privileged helper and update-agent build checks.
- XCTest integration tests with fake services.
- XCUITest in isolated fake-runtime mode.
- SwiftLint strict mode.
- SwiftFormat lint mode.
- Localization coverage and document parity checks.
- Dependency pin and checksum tests.
- License and notice validation.
- Secret scanning and static security checks.
- `git diff --check` and clean generated state.

GitHub-hosted ARM macOS runners do not support nested virtualization, so they cannot claim real Apple `container` compatibility.

### 19.2 Physical compatibility gate

For this delivery, the local development Mac is the authoritative physical compatibility host. The same test plan can also run on an explicitly configured physical Apple silicon self-hosted runner, but project completion does not assume that an always-on runner already exists.

The physical gate performs:

- Signed Apple runtime install.
- Direct API end-to-end suite.
- Upgrade and rollback suite.
- Complete uninstall and residue audit.
- Test-environment baseline restoration.

Changing a compatibility entry or promoting support for a runtime version requires a signed, versioned attestation from this test plan. GitHub automation verifies the attestation, source commit, app build identity, runtime package digest, test-plan version, and cleanup result before accepting the compatibility entry.

### 19.3 Release

Release jobs mirror the proven `../macGameMaster` pattern:

- Run all secret-free verification first.
- Check out pinned action commits.
- Fetch checksum-pinned XcodeGen and Sparkle tooling without floating Homebrew in the secret-bearing job.
- Import `DEVELOPER_ID_CERT_P12` with `DEVELOPER_ID_CERT_PASSWORD` into an ephemeral keychain.
- Store App Store Connect credentials from `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_P8`.
- Build Release, sign nested Sparkle components, helper, agent, and app inside-out.
- Verify Team ID `4DUQGD879H` and designated requirements.
- Notarize, staple, and Gatekeeper-assess the app inside the DMG.
- Generate an EdDSA-signed appcast with `SPARKLE_PRIVATE_KEY`.
- Publish DMG, appcast, checksums, SBOM, and release notes.
- Verify the final non-draft GitHub release and every asset before reporting success.

## 20. Test-driven development and stage reviews

Every behavior change follows:

1. Write one focused failing test.
2. Run it and confirm failure for the intended missing behavior.
3. Implement the minimum production behavior.
4. Run the focused test and relevant suite.
5. Refactor only while green.
6. Commit a coherent change.

The implementation plan maintains checkbox tasks and records RED and GREEN commands.

### 20.1 Stage gates

| Stage | Deliverable | Review gate |
| --- | --- | --- |
| 0 | Upstream contract inventory and acceptance matrix | Contract coverage review |
| 1 | Repository, modules, open-source baseline, hosted CI | Architecture and supply-chain review |
| 2 | Models, validation, templates, recommendations | Product behavior and unit-test review |
| 3 | Direct API bridge and service controller | API correctness and concurrency review |
| 4 | Helper, install, upgrade, rollback, uninstall | Security and failure-injection review |
| 5 | All resource operations and terminal sessions | Functional coverage and error review |
| 6 | SwiftUI interface, parameter help, accessibility | HIG, usability, and accessibility review |
| 7 | Automatic upgrades and compatibility automation | Compatibility and rollback review |
| 8 | Five languages, documentation, release pipeline, Sparkle | Localization and release review |
| 9 | Local real-runtime automation and final audit | Comprehensive product, code, security, performance, and cleanup review |

Every in-scope review finding is fixed and reverified before the next stage. An intentionally accepted limitation requires explicit user approval and documentation; silence does not waive a finding. Stage reports are committed under `docs/reviews/`.

## 21. Local macOS automation and environment isolation

### 21.1 Test pyramid

- Swift Testing covers pure logic and state machines.
- XCTest integration tests cover adapters, fake XPC endpoints, fake package verification, failure injection, persistence, and transaction recovery.
- XCUITest covers user workflows, localization, keyboard behavior, and accessibility.
- A real-runtime end-to-end plan covers actual Apple container functionality on the development Mac.

### 21.2 Real-runtime coverage

The local physical-host suite verifies:

- Onboarding and runtime installation.
- Service start, status, logs, configuration, disk usage, and stop.
- Every Simple Mode template and representative Advanced overrides.
- Container create/run/start/stop/kill/exec/logs/stats/copy/export/delete/prune.
- Image pull/push/save/load/tag/inspect/delete/prune using an ephemeral local registry fixture.
- Build and builder lifecycle using a small local context.
- Network and volume lifecycle.
- Registry login/list/logout using temporary credentials.
- Machine create/run/set/default/logs/stop/delete.
- DNS create/list/delete and cleanup.
- Kernel handling through the reviewed test case.
- Automatic upgrade from a supported previous version.
- Unknown-version hold.
- Post-upgrade probes.
- Injected failure and rollback.
- Complete uninstall and zero residue.
- All five language selections.
- Accessibility audits for every major screen.

### 21.3 No-pollution contract

Before destructive testing, a preflight captures:

- Package receipts.
- Installed payloads under `/usr/local`.
- `com.apple.container.*` launchd services and processes.
- Runtime data and configuration paths.
- Defaults.
- Registry Keychain entries.
- Resolver and packet-filter state.
- MacContainer test caches and temporary roots.

If an existing Apple container installation or user data is detected, the destructive suite stops without modifying it. It does not “temporarily move” unrecognized user data.

Test isolation rules:

- Runtime app, config, and log roots use unique test paths where upstream permits.
- DerivedData is `.artifacts/DerivedData`.
- SwiftPM state is project-local `.build`.
- Downloaded tools live in project-local `.tools`.
- Temporary runtime files live under a `mkdtemp` directory named for `com.matrixreligio.MacContainerTests` and a UUID.
- No local Homebrew or global Python package installation is performed. If a Python helper becomes necessary, it uses a project-local `.venv`.
- A cleanup ledger records every test-owned artifact before creation.
- Swift cleanup uses `defer`; the outer runner uses exit and signal traps.
- A guarded recovery command removes only paths present in the ledger and allowed by an immutable prefix/type policy.
- A test crash leaves enough ledger state for the next invocation to recover safely.

After the suite:

1. Invoke the production complete-uninstall transaction.
2. Run an independent residue audit.
3. Compare the post-test machine state with the preflight baseline.
4. Remove downloaded packages, rollback copies, containers, images, volumes, networks, machines, registry fixtures, temporary credentials, DerivedData, recordings, screenshots, and result bundles.
5. Extract a compact test summary before removing large `.xcresult` data.

The suite passes only if functional assertions pass, the residue audit is empty, and the baseline comparison matches.

## 22. Completion acceptance criteria

The product is complete only when current evidence proves all items:

1. Every official built-in 1.1.0 operation in Section 7 is executable from the UI.
2. A source and runtime audit proves production operation code never launches the `container` CLI or its update/uninstall scripts.
3. Every operation-affecting parameter appears in Advanced mode with validated native input.
4. Every parameter has complete five-language information help.
5. All built-in scenario templates produce valid, conflict-free typed requests and remain editable.
6. A user can install an official signed runtime without Terminal.
7. Compatible automatic runtime upgrade works only when idle and authorized.
8. Unknown or incompatible runtime versions are held safely.
9. Post-upgrade compatibility probes cover every API domain.
10. A failed upgrade restores the prior verified runtime and passes prior-version probes.
11. Complete uninstall removes every product-controlled artifact and produces an empty residue audit.
12. The app follows OS language and supports explicit selection of all five languages.
13. Localization and translated-document parity checks pass.
14. HIG review, keyboard navigation, VoiceOver checks, and automated accessibility audits pass.
15. Hosted CI, the local physical compatibility gate, signing, notarization, appcast generation, and release asset verification pass. A self-hosted physical runner must also pass when one is configured.
16. For the first public release, Sparkle updates a locally signed seed build to the release candidate. For every later release, Sparkle updates the previous public version to the release candidate.
17. Open-source documents, notices, dependency licenses, templates, and policies are complete.
18. Local real-runtime automation passes and restores the development machine to its baseline without temporary residue.
19. Stage review reports show every finding resolved or explicitly accepted by the user.
20. The final comprehensive review finds no unresolved in-scope issue.
21. The public `matrixreligio/macContainer` repository exists, uses `main`, and the verified source, tags, workflows, release, DMG, appcast, checksums, and SBOM are publicly available.

Passing a subset, a simulated-only test suite, or a build without real-runtime validation is not sufficient evidence of completion.

## 23. Design decisions that must remain visible during implementation

- Direct API integration is a product invariant, not an optimization.
- Runtime compatibility is allowlisted by the signed app and proven on physical hardware.
- Automatic upgrade favors workload safety over update immediacy.
- Complete uninstall is defined by independent residue evidence.
- Simple Mode never hides what it is going to do.
- Advanced mode preserves full official operation coverage.
- Privileged code remains small, networkless, allowlisted, and independently tested.
- The development machine must finish local automation in its original state.
- Documentation, localization, accessibility, security, CI, release, and updates are product functionality, not post-release polish.

## 24. Implementation decomposition

This document is the authoritative program-level specification. The work is too large for a single implementation plan, so planning and execution are decomposed into bounded subprojects that each produce working, testable software:

1. **Repository and contract foundation:** public repository, build system, open-source baseline, upstream operation/parameter contract, hosted CI.
2. **Models and templates:** validation, resource recommendations, built-in and custom templates, persistence migrations.
3. **Direct runtime bridge:** service controller and typed adapters for containers, images, builds, networks, volumes, registries, machines, configuration, logs, and terminal I/O.
4. **Privileged lifecycle:** helper security, installation, manual update, complete uninstall, residue audit, and transaction recovery.
5. **Native application experience:** navigation, tables, details, operation forms, parameter help, Activity Center, settings, terminal presentation, HIG, and accessibility.
6. **Automatic compatibility updates:** update agent, signed catalog, compatibility probes, automatic upgrade, rollback, upstream release monitoring, and attestations.
7. **Localization, documentation, and release:** five-language application and key documents, license inventory, signing, notarization, Sparkle, SBOM, GitHub release.
8. **Physical end-to-end validation:** local XCUITest and real-runtime suite, cleanup recovery, final review, and release verification.

Each subproject receives its own detailed implementation plan with RED/GREEN commands and exact file paths. A subproject begins only after the preceding stage review is green. Cross-cutting acceptance criteria in Section 22 remain binding for every subproject; decomposition cannot be used to narrow the original scope.
