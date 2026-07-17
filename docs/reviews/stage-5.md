# Stage 5: Native application review

- Review completed: 2026-07-16
- Reviewed branch: `main`
- Gate: PASS
- Unresolved findings: none

## Functional coverage

- The native SwiftUI application exposes all 61 reviewed Apple container 1.1.0
  operations through typed direct-runtime mappings; the coverage gate reports
  61 mappings and zero command-line backends.
- Resource tables and inspectors, contract-driven forms, Simple Mode templates,
  Activity Center, settings, lifecycle actions, terminal sessions, and
  actionable redacted errors all have deterministic fake-runtime UI fixtures.
- Install, upgrade, rollback, preserve-data removal, and complete removal remain
  visibly distinct. Complete removal requires exact typed confirmation and
  reports independently audited residue instead of claiming success early.
- Automatic updates show compatibility, attestation, postflight, rollback, and
  hold state in text; availability alone is never presented as compatibility.
- Six English-only Product Hunt screenshots are captured as app-window XCTest
  attachments and exported by an isolated, cleanup-safe driver.

## Verification evidence

- `scripts/check-repository.sh`: PASS, including generated project equality,
  SwiftFormat, strict SwiftLint, workflow and open-source policy checks.
- Swift package suite: 267 tests in 47 suites passed with zero failures.
- Bridge coverage: 61 operations, 61 direct mappings, zero CLI backends.
- Signed macOS UI automation exercised navigation, forms, lifecycle safety,
  terminal containment, keyboard navigation, compact/wide layouts, dark mode,
  increased contrast, reduced motion, and every accessibility fixture.
- The final lifecycle native accessibility audit passed in 87.631 seconds after
  the compact layout regression was fixed.
- `git diff --check`: PASS.

## Review verdict

The application is usable by a first-time user through scenario templates and
safe defaults while preserving complete advanced operation coverage. Errors,
destructive actions, terminal capabilities, and lifecycle state remain explicit
and truthful. No Stage 5 product or backend finding remains open.
