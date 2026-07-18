# Changelog

All notable user-facing changes are recorded here. The format follows Keep a
Changelog, and releases use semantic versioning where compatibility permits.

## Unreleased

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
