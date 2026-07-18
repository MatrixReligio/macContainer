# Changelog

All notable user-facing changes are recorded here. The format follows Keep a
Changelog, and releases use semantic versioning where compatibility permits.

## Unreleased

## 0.1.8 - 2026-07-18

### Added

- A verified built-in Alpine 3.22 machine image with a complete OpenRC init
  system is prepared automatically on first use, so the default virtual-machine
  workflow boots successfully without requiring users to build an image.
- Containers and virtual machines now expose embedded interactive terminals;
  stopped machines are started before their terminal is opened.
- Network creation supports IPv4, IPv6, host-only mode, plugins, and plugin
  options; volume creation supports capacity and driver options. Inspectors show
  these settings and the containers using each network or volume.

### Changed

- The guided workload flow explicitly separates application containers from
  persistent Linux virtual machines, and connects container image, network, and
  named-volume choices in one reviewable setup.
- Overview reports total and running counts separately and directs users to an
  existing stopped machine instead of suggesting an unrelated first container.
- Custom machine images are clearly identified as advanced inputs that must
  provide a working `/sbin/init`; the verified built-in image remains default.

### Fixed

- Network and volume parameters selected in the UI are preserved through the
  typed bridge instead of being silently dropped.
- Network replacement starts from the selected network's safe reusable settings
  while allowing the runtime to allocate non-overlapping subnets.

## 0.1.7 - 2026-07-18

### Fixed

- Linux machine creation now fully initializes Apple container's typed machine
  management flags before using the library API, preventing an image pull from
  ending without a persisted machine.
- Successful machine creation refreshes the Machines inventory immediately.
- Failed operations now retain redacted underlying diagnostics in Activity
  Center and macOS unified logging instead of replacing them with a generic
  error.

## 0.1.6 - 2026-07-18

### Fixed

- Runtime update checks now recognize an exact already-installed target before
  applying upgrade-only physical-attestation gates, while still rejecting a
  mismatched installed package identity.
- The template library keeps its first row below the title area, and closing an
  Activity Center opened from Settings no longer closes the Settings window or
  terminates the application.
- Activity titles and terminal phases now use localized user-facing copy instead
  of exposing internal `activity.*` keys or leaving completed refreshes in a
  stale preparing state.

## 0.1.5 - 2026-07-18

### Added

- The template library now shows built-in details and provides persistent New,
  Duplicate, Edit, Save, Import, Export, and Delete workflows for safe custom
  templates.
- The Registries page now provides a direct reviewed login operation when no
  credentials have been stored.

### Fixed

- Runtime installation recognizes an already installed reviewed runtime and
  disables duplicate installation, while complete uninstall clears its typed
  confirmation after success.
- Runtime update checks now report up to date when the reviewed target version
  and package identity are already installed instead of holding the same version
  as an invalid upgrade source.
- Scenario cards advance directly to configuration, Settings actions perform
  their advertised work, and redundant principal-title capsules no longer appear
  above Settings content.
- Registry and template empty states now explain the available next action
  instead of presenting a refresh-only or selection-only dead end.

## 0.1.4 - 2026-07-18

### Changed

- Settings now use one fixed native sidebar and a shared grouped-form layout,
  giving every pane consistent section typography, alignment, content width,
  and margins without an orphaned sidebar-collapse control.

### Fixed

- Installing or updating the application no longer unregisters an already
  approved privileged helper. The helper retires after its final client
  disconnects so launchd starts the current signed copy on the next request
  without revoking the user's system authorization.
- A helper that still needs macOS approval is reported as an explicit approval
  state with a direct link to Login Items settings instead of a generic
  `lifecycle.install.failed` result.

## 0.1.3 - 2026-07-18

### Changed

- Package tests use controlled four-way compilation, while release publication
  reuses the successful CI result for the exact `main` revision instead of
  rebuilding the already-approved source a second time.
- Settings content now keeps readable horizontal margins, the fixed settings
  sidebar no longer shows an orphan toggle, runtime residue inventory aligns in
  adaptive columns, and machine actions fall back to accessible icon controls
  when the toolbar is narrow.

### Fixed

- Privileged lifecycle operations refresh a helper left running from a replaced
  app bundle, preventing macOS code-signing identity checks from rejecting XPC
  replies after an application update.
- Runtime installation now reconciles an interrupted helper reply only after the
  exact signed package receipt and installed payload independently verify,
  avoiding a false failure and destructive rollback after Installer succeeded.

## 0.1.2 - 2026-07-18

### Added

- The Machines page now exposes direct **New Machine**, **Configure**, **Start**,
  **Stop**, and **Delete** controls. New machines use the safe Linux-machine
  template and start by default; home sharing and nested virtualization remain
  off until explicitly enabled in Configure.
- Machine configuration uses typed CPU, memory, read-only home sharing, and
  nested-virtualization controls with one-time consent for home access.

### Fixed

- Apple container 1.1.0 installation now accepts the official kernel archive's
  harmless `./` root directory marker instead of misclassifying it as path
  traversal after the signed package and kernel download had succeeded.
- Installation failures preserve the exact non-sensitive lifecycle stage so the
  app reports an actionable diagnostic rather than a generic failure.
- Simple Mode and every nested operation sheet have visible Cancel or Close
  controls and Escape-key dismissal, preventing a modal workflow from trapping
  the main window.
- Controlled UI labels, scenario metadata, settings, runtime-update stages,
  resource states, and lifecycle inventory names now resolve through the complete
  five-language catalog instead of displaying internal English values.

## 0.1.1 - 2026-07-18

### Added

- Explicit authorization gates for physical-host lifecycle UI tests so destructive
  installation, upgrade, and uninstall paths cannot run without an intentional test mode.
- Shared window-layout policy for stable, readable app sizing across automated and
  interactive macOS sessions.

### Fixed

- Public release verification now receives the release-notes artifact it independently
  requires after downloading a GitHub Release.
- Daily CI now follows the lean native macOS build, test, and policy model without
  repeatedly validating one-time marketing screenshots or UI capture fixtures.

## 0.1.0 - 2026-07-17

### Added

- Native SwiftUI management for the complete reviewed Apple container 1.1.0
  operation contract, using direct typed APIs instead of CLI automation.
- Simple Mode scenario templates for common workflows, editable generated
  values, and Advanced Mode with validated controls and detailed help for every
  operation-affecting parameter.
- Container, image, build, builder, network, volume, registry, machine,
  configuration, log, statistics, and interactive terminal workflows.
- Guided installation of the official signed runtime and complete uninstall
  with independent residue auditing and interrupted-operation recovery.
- Manual and opt-in automatic runtime upgrades with workload-idle gating,
  package verification, eleven-domain compatibility probes, durable version
  holds, verified rollback, and recovery-required reporting.
- A least-privilege background update agent and Sparkle application updates.
- English, Simplified Chinese, Traditional Chinese, Japanese, and Korean app
  localization, documentation, parameter help, and explicit language choices.
- Keyboard navigation, VoiceOver labels, accessibility audits, adaptable native
  layouts, Activity Center, diagnostics, and English Product Hunt screenshots.
- Deterministic icon, SBOM, license, signing, notarization, appcast, checksum,
  and public release verification pipelines.

### Security

- The networkless privileged helper authenticates callers and accepts only
  bounded, typed, allowlisted package, resolver, packet-filter, receipt, and
  cleanup operations.
- Production-source scanning prohibits invoking the `container` CLI or upstream
  update and uninstall scripts, including shell-shaped payload substitutions.
- Compatibility remains fail-closed unless the app-bundled catalog, signed
  physical attestation, package identity, host requirements, and runtime probes
  all agree.
- Hosted CI verifies source without secrets before ephemeral signing credentials
  can be used by the release job.
