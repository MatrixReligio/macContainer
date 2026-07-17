---
source_revision: 2b364a7
language: en
document_id: runtime-updates
---

<a id="runtime-updates"></a>
# Runtime Updates

MacContainer can discover, download, and install Apple container runtime updates, but it never treats a new upstream version as compatible merely because it exists. Compatibility authority is an embedded, reviewed catalog backed by signed physical-test evidence.

<a id="modes"></a>
## Update modes

Choose a mode in **Settings → Runtime Updates**:

- **Check only** reports a compatible update and waits for you to act.
- **Download and notify** downloads and verifies the approved package, then waits for review and administrator approval.
- **Automatic when idle** may install only after explicit versioned consent, prior helper authorization, all compatibility gates, and a fully idle activity snapshot.

Automatic mode is opt-in. Active containers, machines, builds, the builder, lifecycle transactions, or destructive operations postpone installation. The current setting and any pending reason are visible in the app.

<a id="fail-closed"></a>
## Embedded allowlist and unknown versions

The catalog binds a runtime version to the exact package digest, Apple installer team and signer, receipt, supported MacContainer version range, adapter version, allowed source runtime digest, storage migration class, rollback class, required capabilities, probe set, and physical attestation.

Unknown, incomplete, stale, malformed, or incorrectly signed evidence produces a hold. It does not produce a warning that can be clicked through. The upstream monitor may open an `UNVERIFIED` candidate issue, but it cannot edit compatibility authority, merge code, or enable automatic installation.

<a id="preflight"></a>
## Before installation

MacContainer independently refreshes release metadata, verifies the downloaded size and SHA-256, validates the package signature and receipt, checks the current app and macOS versions, confirms Apple silicon and required capabilities, validates the allowed upgrade source, and confirms that a restorable rollback point can be retained. The operation must still be idle immediately before authorization.

Administrator approval appears only after those checks and final review. If the system becomes busy, the update returns to pending rather than racing active work.

<a id="postflight"></a>
## Compatibility probes

After installation, MacContainer verifies health and eleven required domains: containers, images, builder, networks, volumes, registries, machines, disk usage, configuration, capabilities, and overall health. Probe results must match the catalog entry and the lifecycle journal must reach a terminal verified state. A version is never marked compatible on partial results.

The signed physical attestation additionally binds the source commit, app version, runtime version, test-plan version, full operation coverage, zero-residue result, restored baseline, empty lifecycle ledger, nonce, and trusted signer. Replayed or altered attestations are rejected.

<a id="rollback"></a>
## Failure and rollback

Before upgrade, MacContainer retains the rollback class required by the catalog. For the approved 1.0.0-to-1.1.0 path, that includes the previous package plus configuration and metadata. If any target probe fails, the new version is blocked by its attestation ID, the previous runtime is restored, and the previous probe suite runs again.

Success is reported only after the previous runtime is verified. If rollback itself cannot be verified, the app shows **Recovery required**, stops automatic work, preserves redacted evidence, and provides a specific manual recovery path. It never loops automatically between failed versions.

<a id="privacy-bandwidth"></a>
## Privacy and bandwidth

Update checks request signed catalog metadata and approved packages only. Conditional requests and backoff reduce traffic. Credentials, container contents, local paths, and operation history are not uploaded. See [Troubleshooting](TROUBLESHOOTING.md) for hold and recovery codes, or [Installation](INSTALLATION.md) for package identity details.
