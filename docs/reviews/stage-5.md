# Stage 5: Native application review

- Review date opened: 2026-07-16
- Reviewed branch: `feature/maccontainer-implementation`
- Gate: PENDING UI
- Backend readiness section: PASS
- Unresolved backend findings: none

## Backend readiness

Stage 3 supplies the native application's complete direct-runtime boundary:

- all 61 Apple container 1.1.0 operation IDs have exactly one audited direct
  mapping and no command-line backend;
- typed request, resource, activity, error, progress, process-session, and
  configuration values do not expose upstream protobuf objects to SwiftUI;
- interactive sessions preserve binary data and provide direct send, resize,
  wait, signal, detach, and cancellation behavior for the SwiftTerm view;
- lifecycle and per-resource mutations have shared lock-key semantics for the
  later `OperationExecutor` composition;
- partial failures remain ordered and redacted, while caller cancellation is
  never converted into a normal item failure;
- Keychain, archive, local-path, DNS, configuration, service-start, and
  last-known-good safeguards have focused tests;
- 96 bridge tests pass normally and under Thread Sanitizer.

Authoritative evidence is recorded in `docs/reviews/stage-3.md` and enforced by
`Config/contracts/apple-container-1.1.0-bridge-map.json`,
`BridgeCoverageTests`, `check-bridge-coverage.swift`, and
`check-no-container-cli.sh`.

## Work still required before this gate can pass

The SwiftUI shell, resource tables and inspectors, contract-driven 352-slot
parameter forms and information buttons, `OperationExecutor`, Simple Mode,
terminal/activity views, settings, keyboard access, accessibility audits, and
UI automation belong to the Stage 5 implementation plan and are not claimed
complete here. This pending list is planned UI scope, not an unresolved Stage 3
backend finding.

The gate must remain `PENDING UI` until every Stage 5 task, focused UI test, full
application test, accessibility audit, and Stage 5 review has passed.
