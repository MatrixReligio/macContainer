# Release Policy

Releases are produced from reviewed commits on `main` by the pinned GitHub
workflow. A release is not complete until source, signed and notarized app,
checksums, SBOM, third-party notices, Sparkle appcast, and compatibility
attestation are independently verified from the public release.

## Required gates

1. Repository, package, integration, UI, accessibility, localization, and
   failure-injection tests pass.
2. Apple container compatibility passes for every version marked supported.
3. Privileged lifecycle install, upgrade, rollback, and complete product-owned
   cleanup pass on a disposable physical validation Mac.
4. Dependency licenses, vulnerabilities, provenance, and generated notices are
   reviewed.
5. Version, changelog, signing identities, notarization, and update signatures
   are consistent.
6. A signed seed build upgrades through Sparkle and remains functional.

Secrets are available only to guarded non-pull-request release jobs after
secret-free verification. Releases are immutable; a bad release is withdrawn
and superseded, never silently replaced. See [Security](SECURITY.md) for urgent
fix coordination and [Changelog](CHANGELOG.md) for public changes.
