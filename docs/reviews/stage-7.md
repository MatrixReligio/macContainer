# Stage 7: Automatic compatibility and rollback review

- Review completed: 2026-07-16
- Scope: embedded compatibility authority, release discovery, signed physical
  attestations, idle-only automatic upgrade, postflight rollback, and UI state
- Gate: PASS
- Unresolved findings: none

## Fail-closed review

- Unknown runtime versions, malformed catalogs, app-version/host mismatches,
  package identity changes, missing attestations, previous rollback blocks, and
  unapproved destructive migrations all stop before package or service mutation.
- Physical proof requires the exact source commit, app bundle/version/build and
  designated-requirement hash, runtime version/package digest, test-plan version,
  complete successful operations, zero residue, restored baseline, empty cleanup
  ledger, a trusted P-256 signature, a fresh issue time, and a nonce accepted once
  by a private durable replay store.
- Automatic installation requires the current explicit consent version, current
  helper authorization, no active container/machine/build/builder/lifecycle or
  destructive operation, sufficient rollback space, a complete preflight, and a
  second idle check immediately before the upgrade transaction.
- Target failure after service stop restores the verified previous package,
  configuration/data classification, service, and probes before recording the
  target block. Failure at any rollback stage produces recovery-required state
  and retains diagnostic/block evidence rather than claiming success.
- Offline discovery, GitHub rate limits, consent/helper revocation, workload
  races, catalog corruption, and signer changes have explicit non-install states.
  A blocked target clears only when a different embedded attestation explicitly
  supersedes the prior block.

## Eleven-domain compatibility evidence

The stable baseline contains exactly one bounded direct read probe for each
required domain: `health`, `containers`, `images`, `builder`, `networks`,
`volumes`, `registries`, `machines`, `diskUsage`, `configuration`, and
`capabilities`. Timeout, missing capability, malformed response, stopped
postflight runtime, and multiple simultaneous failures remain incompatible.

## Upstream authority boundary

- The scheduled agent and GitHub monitor may discover release metadata and
  independently hash an installer, but neither may edit or remotely override the
  app-bundled catalog.
- Monitoring creates only an issue titled `Compatibility candidate: Apple
  container VERSION` with `Status: UNVERIFIED`; it has no content-write,
  auto-merge, catalog-edit, or compatibility-label path.
- A compatibility promotion PR must change catalog, implementation/package
  review material, and a signed physical attestation together, pass the complete
  repository gate, and have an approving review.

## Verification evidence

- `swift test --filter MCCompatibilityTests`: 22 tests in 4 suites passed.
- `swift test --filter MCSystemLifecycleTests`: 109 tests in 19 suites passed.
- Signed macOS automation passed `UpdateAgentTests` and
  `AutomaticUpdateUITests`; status remained typed through checking, available,
  downloading, pending, installing, held, rolled back, recovery required, and up
  to date.
- Compatibility catalog check: 1 exact reviewed runtime, 61 capability IDs, 11
  baseline probes.
- Signed fixture verification: 16 required operations, zero residue, durable
  replay rejection, and immutable embedded signer configuration passed.
- Upstream workflow policy and metadata-only dry run passed; independent fixture
  hashing matched the locally calculated SHA-256 without modifying the worktree.
- Strict SwiftLint, SwiftFormat lint, generated-project equality, and
  `git diff --check` passed.

## Review verdict

Remote availability is never compatibility authority. The automatic path can
advance only through exact embedded review, signed physical proof, package trust,
idle/authorization policy, all-domain preflight, rollback readiness, transaction
postflight, and durable success. Every reviewed uncertainty ends in a truthful
hold, pending, rollback, or recovery state. No Stage 7 finding remains open.
