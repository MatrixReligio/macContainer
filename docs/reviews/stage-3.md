# Stage 3: Direct runtime bridge and service controller review

- Review date: 2026-07-16
- Reviewed branch: `feature/maccontainer-implementation`
- Reviewed range: `c6baba9..b1bf1e6`
- Upstream baseline: Apple `container` 1.1.0 at `5973b9cc626a3e7a499bb316a958237ebe14e2ed`
- Gate: PASS
- Unresolved in-scope findings: none

## Verification result

The direct bridge, complete repository, source-policy, and concurrency gates pass:

```text
swift test --filter MCContainerBridgeTests
PASS: 96 tests in 18 suites

swift test --parallel
PASS: 161 tests in 28 suites

swift test --sanitize=thread --filter MCContainerBridgeTests
PASS: 96 tests in 18 suites, no Thread Sanitizer diagnostic

swift scripts/check-bridge-coverage.swift \
  Sources/MCContracts/Resources/apple-container-1.1.0.json \
  Config/contracts/apple-container-1.1.0-bridge-map.json
PASS: 61 operations, 61 direct mappings, 0 CLI backends

scripts/check-no-container-cli.sh .
PASS: three production roots

swiftformat ... --lint
PASS: 0 files require formatting

swiftlint lint --strict
PASS: 0 violations

git diff --check
PASS
```

The resolved package checkout and `Package.resolved` both identify tag 1.1.0 and
commit `5973b9cc626a3e7a499bb316a958237ebe14e2ed`. Every production call compiled
against that exact source. A source scan found no `ContainerCommands` import,
`Foundation.Process`, shell launch, `/usr/bin/container`, or operational use of
the `container` executable.

Tests used fakes, repository-local paths, and one isolated temporary Keychain.
The Keychain test restored the original search list, deleted the Keychain, and
confirmed its file was absent. Kernel, configuration, build, and service tests
removed their UUID-scoped files. The post-test residue scan found no
`.mc-*-test-*`, `.mc-service-test-*`, or `.artifacts` test file.

## API and operation coverage

The versioned bridge map preserves the reviewed contract order and gives each
of the 61 operation IDs exactly one protocol method, production adapter,
upstream action, focused test, cancellation rule, lock key, and approved direct
backend. The independent checker rejects missing or duplicate IDs, unknown
operations, absent adapter/test evidence, and command-line backends.

Production adapters call the exact 1.1.0 APIs:

- containers and interactive processes use `ContainerClient` plus typed
  `ProcessConfiguration` and binary `FileHandle` streams;
- images, builds, and the builder use `ClientImage`, `ContainerBuild.Builder`,
  and the builder container APIs;
- networks, volumes, registries, machines, DNS, kernels, configuration, health,
  disk usage, and service registration use their direct Swift, XPC, Security,
  OSLog, and `ServiceManager` interfaces;
- system start targets the installed
  `/usr/local/bin/container-apiserver`, never an executable resolved relative to
  MacContainer;
- unified logs use `OSLogStore`; no `/usr/bin/log` subprocess is present.

Prefix resolution fails before mutation on zero or multiple matches. Batch
results retain input order and redact backend details. Infrastructure images,
the built-in network, active workloads, unsupported machine capabilities, and
unsafe local/archive paths are rejected before destructive access.

## Concurrency, cancellation, and cleanup

One actor coordinator defines global lifecycle conflicts plus system, builder,
and per-resource locks. Its tests prove FIFO acquisition, cancellation before
ownership, serialization of the same resource, parallelism for different
resources, and lifecycle conflict with every key.

All stream producers tie their worker task to `AsyncThrowingStream` termination.
Container and machine terminal sessions preserve arbitrary bytes, split
stdout/stderr outside a TTY, use one terminal stream for TTY mode, clamp resize,
validate signals, and finish readers exactly once. Batch adapters and backend
prune loops rethrow cancellation and stop before later mutations. Configuration
apply performs awaited, uncancelled restoration and restart before rethrowing
cancellation. Kernel downloads, build workspaces, file descriptors, event-loop
groups, service plists, and partial registrations all have bounded cleanup.

## Security and persistence review

- Registry passwords are verified before storage, saved as device-only,
  non-synchronizing Internet Password items, never added to the user's Keychain
  search list, and never included in summaries or errors.
- Build Dockerfiles are confined beneath the canonical context, build secrets
  are redacted from progress, and security-scoped access closes on every exit.
- Kernel downloads require HTTPS, an exact host allowlist, a pinned or explicit
  SHA-256 digest, a size limit, safe redirects, streamed hashing, and a confined
  archive member. Traversal, hard links, empty/nonregular kernels, and escaping
  symlinks are rejected.
- Runtime TOML covers every 1.1.0 `ContainerSystemConfig` field, rejects unknown
  keys/tables, caps input at 1 MiB, uses `O_NOFOLLOW`, writes mode `0600`
  atomically in the same directory, synchronizes file and directory, and keeps
  one last-known-good copy.
- DNS names and redirects are strictly typed; resolver and packet-filter
  mutations roll back together on partial failure.

## Findings resolved during review

### F-1: Cancellation was converted into ordinary partial failure

Container, image, network, volume, machine, and DNS batch loops caught every
error and could continue mutating later resources after the caller cancelled.
Registry operations also converted cancellation into verification or storage
failure. New pre-cancelled-task tests failed across all affected adapters.
Cancellation now has an explicit preflight, is rethrown from mutation catches,
and is preserved in production prune loops. The focused suite and Thread
Sanitizer pass.

Resolved by `b1bf1e6` (`fix: harden bridge cancellation and cleanup`).

### F-2: Builder connection cleanup did not cover every exit

The initial build path closed the socket with `defer` and shut down the NIO
event-loop group only when `Builder.build` threw. It also opened the connection
before tag/platform/configuration validation, so a validation error could skip
group cleanup. A failing cleanup-scope test now covers success, ordinary error,
and cancellation. Configuration is prepared before connecting, and the
connection is wrapped in awaited uncancelled cleanup that closes the group and
socket on every exit.

Resolved by `b1bf1e6`.

### F-3: A post-registration verification failure could leave a launchd job

`AppleServiceManager.register` removed the plist when its immediate
registration check failed, but it did not remove a job whose registration call
had already succeeded. A fake native-service backend reproduced this without
touching launchd. Registration is now transactional: after a returned register
call, any verification failure deregisters the full domain label and removes
the plist; cleanup failure is surfaced as `partialStartCleanupFailed`.

Resolved by `b1bf1e6`.

### F-4: Unified-log polling could lose valid records

The first implementation applied `tail` on every follow poll and represented
same-timestamp evidence with a set. Bursts larger than the tail or two identical
records at one timestamp could therefore be discarded. Tests fixed the intended
semantics: tail only the initial snapshot, preserve duplicate multiplicity, and
skip only entries already observed at the cursor. The same review also made an
explicitly unhealthy service report stopped rather than running.

Resolved by `b1bf1e6`.

## Review conclusion

Stage 3 meets the direct API, operation coverage, service ownership,
concurrency, cancellation, terminal safety, path confinement, credential
isolation, configuration rollback, and no-CLI requirements. The gate is PASS
with no unresolved in-scope finding. Stage 4 may begin from this baseline.
