# MacContainer

MacContainer is a native macOS control center for Apple's `container` runtime.
It is designed to make the complete upstream feature set approachable without
hiding advanced parameters or delegating operations to the `container` CLI.

> Development status: pre-release. The repository currently establishes the
> reviewed upstream 1.1.0 contract, reproducible build, application identity,
> icon, and supply-chain gates. Runtime and lifecycle features land only with
> tests and stage-review evidence.

## Product principles

- Native SwiftUI interaction that follows macOS conventions and accessibility.
- Safe scenario templates for common tasks, with every effective parameter
  inspectable before execution.
- Direct use of reviewed Apple container libraries and protocols; production
  code must not shell out to the `container` CLI.
- Explicit privileged boundaries for installation, upgrade, rollback, and
  complete product-owned cleanup.
- Compatibility-gated runtime updates: unknown versions are held until they pass
  the published compatibility suite.
- Local processing and no telemetry by default.

## Requirements

- macOS 26 or later on Apple silicon
- Xcode 26 for development
- Network access only when an operation explicitly needs GitHub, a registry, or
  an update feed

## Build and verify

```console
scripts/bootstrap-tools.sh
scripts/check-repository.sh
xcodebuild -project MacContainer.xcodeproj -scheme MacContainer \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

The checksum-pinned bootstrap installs project-local development tools under
`.tools`; it does not modify the system toolchain. See [Development](DEVELOPMENT.md)
for the isolated workflow and [Architecture](ARCHITECTURE.md) for trust boundaries.

## Community and security

- Read [Contributing](CONTRIBUTING.md) before proposing a change.
- Use [Support](SUPPORT.md) for usage questions.
- Report vulnerabilities privately as described in [Security](SECURITY.md).
- Review local data handling in [Privacy](PRIVACY.md).

MacContainer is licensed under Apache-2.0. See [LICENSE](LICENSE),
[NOTICE](NOTICE), and [third-party notices](THIRD_PARTY_NOTICES).
