# Stage 4: Privileged lifecycle and zero-residue review

- Review date: 2026-07-16
- Reviewed branch: `feature/maccontainer-implementation`
- Reviewed range: `b1bf1e6..650eabe`
- Runtime baseline: Apple `container` 1.1.0
- Application identifier: `container.matrixreligio.com`
- Helper identifier and Mach service: `container.matrixreligio.com.helper`
- Gate: PASS
- Unresolved in-scope findings: none

## Verification result

The complete privileged lifecycle suite and integration gates pass:

```text
MACCONTAINER_SECURITY_SIGNING_IDENTITY="Developer ID Application: MatrixReligio LLC (4DUQGD879H)" \
  swift test --filter MCSystemLifecycleTests
PASS: 90 tests in 15 suites

xcodebuild -project MacContainer.xcodeproj -scheme MacContainer \
  -only-testing:MacContainerIntegrationTests/PrivilegedHelperIntegrationTests \
  CODE_SIGNING_ALLOWED=NO test
PASS: 3 tests, 0 failures

swiftlint lint --strict
PASS: 0 violations in 144 Swift files

swiftformat Sources Tests App scripts --lint
PASS: 0 files require formatting

scripts/check-no-container-cli.sh .
PASS: three production roots

plutil -lint helper entitlements, launchd plist, and app Info.plist
PASS

git diff --check
PASS
```

All tests used UUID-scoped directories. The independently signed peer test copied
`/bin/sleep` into a private temporary directory, signed it with hardened runtime
and the deliberately wrong identifier `example.attacker.maccontainer`, proved
that `CallerValidator` rejected it, terminated it, and removed the directory.
The post-test scan found no signed-peer fixture or process.

## Privileged boundary

The app and helper require distinct exact designated requirements, the reviewed
team identifier `4DUQGD879H`, hardened runtime, and non-ad-hoc signing. Both ends
bind the XPC connection to the peer requirement before accepting requests. The
helper has an empty entitlement dictionary: no network entitlement and no app
sandbox exception. Its launch daemon is neither `RunAtLoad` nor `KeepAlive`.

The versioned, 1 MiB-bounded XPC schema has exactly nine operations. It contains
typed package identity, receipt identifier, manifest identity, resolver name and
IP addresses, or the exact packet-filter anchor; it exposes no caller-supplied
filesystem path, executable, environment, command, or shell field. A package is
transferred only as an inherited read-only file descriptor. The root-side
adapter independently verifies ownership, regular-file type, link count,
permissions, stable identity, SHA-256, Apple installer signature, notarization,
receipt, install location, and the complete reviewed payload before invoking the
installer.

Production scans found no `Foundation.Process`, `/bin/sh`, `/bin/bash`,
`/usr/bin/env`, `system`, or `popen`. The only process launchers are reviewed
`posix_spawn` wrappers with empty environments and fixed absolute executables:
`installer`, `pkgutil`, `pfctl`, and `killall` for `mDNSResponder`. Package
inspection separately uses fixed `/usr/sbin/pkgutil` actions. No helper or
lifecycle source imports `Network`/`CFNetwork` or uses sockets or `URLSession`.

All privileged deletion is the intersection of the immutable 1.1.0 manifest and
the path policy. Directory traversal uses no-follow descriptors; files are
identity-checked again immediately before mutation. Resolver and packet-filter
operations accept only normalized names and the exact `com.apple.container`
anchor. Errors crossing XPC are generic and lifecycle journal failures redact
credentials, authorization material, secrets, and private temporary paths.

Lifecycle journal, staging, and rollback state is user-owned and private. Files
are `0600`; directories are `0700`; symlink-redirected journal and rollback roots
fail before writing. The journal is append-only, synchronized with its parent,
sequence checked, transition checked, and quarantined on truncation or duplicate
sequence. Rollback manifests are bounded, no-follow reads. Reopening revalidates
the point identity, complete item set, file sizes, previous package, and exact
restore-target policy; a modified absolute path cannot redirect a restore.

## Lifecycle and failure-injection matrix

| Condition | Durable evidence and action | Completion rule |
|---|---|---|
| Install success | begin; install intent/applied; receipt, payload, service, kernel, probes; verified/committed | Return only after all 13 stages and staging cleanup |
| Install verifier or consent failure | terminal failure before helper mutation; private staging removed | Never report installed |
| Helper rejection or partial installer success | install was attempted; run trusted partial uninstall, then independent residue audit | Inaccessible or remaining residue becomes `incompleteRecovery` |
| Install service, kernel, or probe failure | same partial-uninstall and independent-audit path | No postflight failure can become success |
| Crash before an install side effect | active journal plus fresh target evidence | Record cleanup intent, remove only the transaction staging directory |
| Upgrade or downgrade success | verified previous package and durable rollback point precede final idle check; target intent/applied; four-way version agreement and probes | Commit only after all 11 stages; explicit downgrade consent required |
| Work appears at final idle check | no target install; discard rollback point and staging | Refuse upgrade without stopping runtime |
| Service stop, target install, verification, start, or probe failure | durable rollback point; record `rollingBack`; reinstall previous package, restore classified data, start and probe previous runtime, persist diagnostic, block target | Return `rolledBack`, never target success |
| Any of seven rollback-stage failures | diagnostic and target-block attempts continue; point is retained and journal remains `rollingBack` | Recovery reopens and revalidates the exact recorded point before idempotent retry |
| Crash during rollback | fresh target/package evidence plus exact point identifier | Resume only a securely reopened, verified recorded point; otherwise require recovery UI |
| Stale or incomplete uninstall confirmation | refreshed inventory fingerprint mismatch or missing irreversible acknowledgement | Reject before journal or mutation |
| Uninstall success | intent/applied around each mutation; all 15 independent residue checks absent; verified/committed | Only complete mode may return `complete` |
| Preserve-data uninstall | retained data is explicit and complete inventory is still required | Return `dataPreserved`, never `complete` |
| Uninstall stage failure or cancellation | journal stage failure and incomplete result | UI must refresh inventory and rerun; no complete claim |
| Crash during uninstall | use only allowlisted residue kinds already represented by durable actions; replay an outstanding intent idempotently | Fresh independent audit must be empty before commit |
| Unrecorded or unverifiable uninstall residue | read-only evidence only | Require recovery UI; never guess a deletion |
| Inaccessible final audit | status is `unverifiable` | Fail closed as uninstall incomplete |
| Corrupt, truncated, ambiguous, or multiple-active journal | quarantine where possible and run fresh read-only evidence | No mutation; require recovery UI |
| Staging or rollback cleanup failure | explicit cleanup error; retained point remains identity-bound | Never hide cleanup failure behind success |

Cancellation before a privileged side effect follows the same private-staging
cleanup path as an ordinary stage failure. Cancellation or process death after a
durable intent cannot create a success result: a running transaction reports the
stage failure, while a process restart enters evidence-driven recovery.

## Zero-residue matrix

The independent auditor requires exactly one result for each of the 15 residue
kinds; duplicate absent entries no longer satisfy the completion gate.

| Residue | Removal authority | Independent evidence |
|---|---|---|
| launch service | stop exact `com.apple.container.*` labels | direct service-manager prefix query |
| owned process | stop workloads and services | stable full PID snapshot, exact executable path, valid Apple team signature |
| receipt | fixed `pkgutil --forget` | exact `.plist` and `.bom` receipt files |
| receipt payload | trusted manifest and no-follow unlink | every non-shared reviewed payload entry |
| application support | exact user artifact location | no-follow existence check |
| configuration | exact `~/.config/container` location | no-follow existence check |
| defaults domain | exact `com.apple.container.defaults` | persistent-domain lookup |
| registry credential | registry credential store | Keychain enumeration |
| resolver | normalized `containerization.*` names | exact resolver-directory prefix inventory |
| packet filter | exact helper anchor | fixed `pfctl -a com.apple.container -sr` audit |
| downloaded package | MacContainer RuntimePackages directory | exact location check |
| rollback point | private rollback directory | exact location check |
| physical-test fixture | MacContainer PhysicalTests directory | exact location check |
| download cache | MacContainer runtime cache | exact location check |
| runtime-owned directory | remove known empty manifest directories only | nonempty `/usr/local/libexec/container` check |

Shared `/usr/local`, `/usr/local/bin`, and `/usr/local/libexec` are never removal
targets. Symlinks are removed as links rather than followed, hard-linked payload
files are refused, mounted directory trees are rejected, and unrelated files are
preserved. Unified system logs are not application-owned filesystem residue and
are not deleted.

## Findings resolved during review

### F-1: Duplicate audit kinds could satisfy the empty-count gate

The completion predicate counted 15 absent entries without proving the 15 kinds
were unique. It now requires the exact `ResidueKind.allCases` set. Complete and
preserve-data results both require that full inventory.

### F-2: A persisted rollback destination could be changed to another absolute path

Reopen previously checked only that `sourcePath` started with `/`. Creation,
reopen, and immediate restore now enforce an exact source policy: previous
packages must be inside MacContainer RuntimePackages, configuration is exactly
`~/.config/container`, and full data is exactly Apple Container application
support. Tampered destinations are rejected before mutation.

### F-3: A growing process table could be truncated and reported absent

The process audit previously allocated from one count estimate and accepted a
potentially full buffer. It now doubles and retries saturated snapshots five
times, and returns an unverifiable audit error rather than false absence if the
kernel list never stabilizes.

### F-4: Failed rollback was incorrectly made terminal

A rollback-stage failure used to append terminal `failed`, hiding it from restart
recovery. It now retains the durable `rollingBack` state and point while still
persisting diagnostics and blocking the target version, so restart recovery can
revalidate and retry it.

### F-5: A symlinked lifecycle directory could redirect journal writes

Journal parent and quarantine directories are now lstat-validated, user-owned,
mode `0700`, and synchronized through `O_NOFOLLOW` directory descriptors. The
redirect test proves no file is written through the link.

### F-6: A symlinked rollback root could redirect private snapshots

The local rollback store now validates and privatizes the real parent before
creating a point. A redirected root is rejected before a UUID directory or
manifest is written.

### F-7: Peer-authentication evidence used only simulated identities

The review added a local test using a separately signed hardened executable with
the correct signer but wrong identifier. Real Security.framework inspection and
the production validator reject it, and the fixture is removed afterward.
