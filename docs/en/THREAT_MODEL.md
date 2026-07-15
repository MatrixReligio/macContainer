# Threat Model

## Scope and assets

This model covers the MacContainer app, privileged lifecycle helper, update
agent, direct Apple container bridge, compatibility evidence, local settings,
credentials, diagnostics, release workflow, and product-owned files.

Assets include administrator authorization, registry credentials, container
data, host filesystem integrity, signed update trust, the last known-good
runtime, and the user's informed intent.

## Trust boundaries

1. Untrusted UI and imported values enter typed, validated application models.
2. Runtime requests cross into reviewed Apple container protocols without a CLI
   or arbitrary shell boundary.
3. Lifecycle requests cross an authenticated XPC boundary to a narrowly scoped
   privileged helper.
4. GitHub, registries, update feeds, packages, and images are external and
   untrusted until identity, signature, checksum, and policy checks succeed.
5. Exported diagnostics cross from local private data to user-selected storage.

## Principal threats and controls

| Threat | Required controls |
| --- | --- |
| Argument or command injection | Typed requests, fixed executables, no shell interpolation, allowlists |
| Confused-deputy privilege escalation | Code-signature validation, protocol versioning, authorization per action, minimal helper API |
| Malicious or corrupted runtime update | HTTPS, pinned release identity, package signature and checksum checks, staged install |
| Unknown runtime breaks the app | Default hold, isolated compatibility suite, signed attestation, explicit promotion |
| Failed upgrade leaves no working runtime | Transaction journal, preflight, last known-good retention, rollback and recovery |
| Uninstall deletes user data or leaves residue | Ownership inventory, scope preview, idempotent removal, postcondition scan |
| Credential or personal-data leakage | Keychain, log redaction, diagnostics preview, no default telemetry |
| Dependency or CI compromise | Immutable action pins, checksum-pinned tools, secret-free verification, guarded release jobs |
| UI misrepresents a destructive action | Effective-parameter review, explicit scope, authentication, accessible confirmation |

## Assumptions and non-goals

The operating system, Secure Enclave, Keychain, Apple code-signing roots, and a
fully patched supported macOS installation are trusted. A host already
controlled by root malware is outside the protection boundary. MacContainer
does not claim to make untrusted container workloads safe beyond the isolation
provided by Apple's runtime and macOS.

## Verification

Each control needs automated positive, negative, interruption, and cleanup
tests. Privileged lifecycle and release/update controls additionally require
physical-Mac validation. New trust boundaries or externally sourced inputs must
update this model in the same reviewed change. Report gaps through the private
process in [Security](../../SECURITY.md).
