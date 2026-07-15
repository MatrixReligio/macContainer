# Stage 2: Models, validation, and templates review

- Review date: 2026-07-16
- Reviewed branch: `feature/maccontainer-implementation`
- Reviewed range: `3f0951a..486648d`
- Gate: PASS
- Unresolved in-scope findings: none

## Verification result

The Stage 2 pure-logic gate and complete repository gate pass:

```text
swift test --filter MCModelTests
PASS: 7 tests in 2 suites

swift test --filter MCContractsTests
PASS: 13 tests in 2 suites

swift test --filter MCTemplatesTests
PASS: 42 tests in 6 suites

swift test --parallel
PASS: 66 tests in 10 suites

scripts/check-repository.sh
PASS: repository policy, contract coverage, generated project, icon pipeline,
workflow policy, open-source baseline, SwiftFormat, SwiftLint, and package tests

git diff --check
PASS
```

The acceptance suite renders each of the eight built-in templates 1,000 times
for one fixed host/image context. All 8,000 persisted encodings are
byte-identical to their template baseline and contain none of the reviewed
password, token-assignment, secret-assignment, private-key, authorization, or
registry-auth markers.

The source scan for the same markers found only:

- explicit rejection fixtures;
- the sensitive-material policy and its marker table;
- redaction/secret-handling branches; and
- assertions that generated output is marker-free.

There are no saved positive fixtures containing credential values. Tests that
create files use UUID-scoped directories under `FileManager`'s temporary
directory, remove them with `defer`, and explicitly verify cleanup where the
test owns the root. No Apple container operation or system runtime path is
used by this stage.

## Specification Sections 6, 8, and 14

### Simple Mode and templates

`BuiltInTemplates.all` contains exactly these stable IDs, in product order:

1. `quick-run`
2. `interactive-shell`
3. `web-service`
4. `development-workspace`
5. `local-database`
6. `restricted-secure`
7. `cross-architecture`
8. `linux-machine-workspace`

Each renderer returns an editable `OperationDraft`; generated fields retain
their provenance as upstream default, scenario rule, host recommendation,
image metadata, or user override. `TemplateRenderer` orders review rows by the
reviewed upstream contract and reports a normalized diff from upstream
defaults. It rejects a missing operation, an unknown field, or an operation-ID
mismatch rather than hiding it.

The resource engine is deterministic and was checked over 24,000 host/workload
combinations: 1–32 logical CPUs, 4–128 GiB, and all six workload kinds. CPU,
memory-half, and host-reserve caps hold for every combination. Malformed or
memory-starved hosts fail closed without integer overflow.

Template-specific safeguards are explicit:

- Web and database host ports are mandatory and require a separate
  availability preflight before execution.
- Database storage is persistent, remove-on-exit is false, and its graceful
  stop policy is 30 seconds.
- The secure template sets a read-only root, drops `ALL` capabilities,
  attaches no network, disables DNS, creates only temporary `/tmp`, and adds no
  writable host mount or volume.
- Cross-architecture sets `linux/amd64` and Rosetta together and fails when the
  observed host capability is absent. The validator independently rejects
  Rosetta with any other platform or without the runtime capability.
- The machine template leaves home sharing at `none` and nested virtualization
  false until consent. Enabling nested virtualization is then gated by the
  contract's Apple-silicon, macOS, runtime, and observed-capability rules.

### Parameter contract and validation

The reviewed Apple container 1.1.0 contract still contains exactly 61
operations and 352 parameter slots. Every parameter has typed value and
cardinality metadata, required/default behavior, accepted-value or boolean
metadata, grammar where applicable, dependencies, conflicts, availability,
risk, and all five localization/help/recovery keys.

`OperationValidator` covers operation identity, unknown fields, required
values, scalar/repeated cardinality, typed secret inputs, nonnegative/range
grammar, whole-string grammar, dependencies (including `field=value`), active
conflicts, runtime/macOS/architecture/capability availability, and the explicit
Rosetta platform rule. Results are deterministic and sorted by severity and
parameter ID, and validation does not mutate the draft.

Section 8.2's SwiftUI information button and its accessibility automation are
assigned to Stage 5. Stage 2 supplies and verifies the complete metadata that
control consumes; no UI-completion claim is made here.

### Persistence and secret exclusion

Custom template schema version 2 has an explicit, stable single-key JSON form
for every `FieldValue` case. Decoding rejects ambiguous multi-key values.
Document IDs match `^[a-z0-9][a-z0-9-]{0,63}$`, so callers cannot select a
path. JSON is deterministically encoded with sorted keys.

The concrete store creates its root with mode `0700`, writes a sibling UUID
temporary file with mode `0600`, synchronizes its contents, replaces the target
atomically, enforces target mode `0600`, synchronizes the parent directory, and
deletes any temporary file. Injected-failure tests prove the previous bytes
survive a failed replacement; a real temporary-directory test proves repeat
replacement, target permissions, and absence of leftover temporary files.

Saving and importing both reject typed secrets plus disguised password/token,
credential-key, authorization-header, registry-auth, and private-key material.
Ordinary words that merely contain `token` or `authorization` remain valid, so
the safeguard is not a broad substring ban.

Version 1 migrates `memoryMiB` through checked multiplication and preserves all
other typed fields exactly. Overflow or a migration conflict returns a disabled
record with the original bytes. Unknown future schema versions also return a
disabled record with their original bytes and a stable localized reason key;
the default listing exposes these records instead of silently hiding them.
Corrupt documents are renamed into a private quarantine directory. Existing
quarantine evidence is never overwritten.

Section 14's Apple runtime configuration editor, last-known-good runtime config,
and controlled restart belong to later bridge/application stages. This stage
completes the custom-template persistence portion and does not write runtime
configuration.

## Findings resolved during review

### F-1: Disguised credentials could bypass typed-secret rejection

The first store implementation rejected `.secret` but accepted the same data
when encoded as a normal string, key/value, or header. Failing tests reproduced
password-field, API-token key, private-key block, authorization-header, and
registry-auth JSON paths. `TemplateSecretPolicy` now rejects them before both
save and imported-data load while retaining a negative false-positive test.

Resolved by `a91a310` (`fix: prevent credential persistence in templates`).

### F-2: Persisted associated-enum JSON depended on compiler synthesis

The initial `FieldValue` representation used Swift's synthesized associated
enum layout, such as a nested `_0` key. A failing schema test fixed the intended
single-key external representation and ambiguous-key rejection. Encoding and
decoding are now exhaustive and explicit for all twelve value cases.

Resolved by `ae8362a` (`fix: stabilize persisted field value encoding`).

### F-3: Default listing silently omitted future-schema templates

Although the migrator produced a disabled record, `TemplateStore.list()`
filtered it out. A failing test required the default API to return both enabled
and disabled records. Filtering is now available only through the explicitly
named `listEnabled()` method.

Resolved by `486648d` (`fix: surface disabled templates by default`).

## Review conclusion

Stage 2 meets its model, validation, recommendation, template, transparency,
secret-exclusion, atomic-persistence, and migration requirements. The gate is
PASS with no unresolved in-scope finding. Stage 3 may begin from this baseline.
