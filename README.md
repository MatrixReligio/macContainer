---
source_revision: f94970774a25e899b7fb4a623d35c555d11f12e2
language: en
document_id: readme
---

<a id="maccontainer"></a>
# MacContainer

MacContainer is a native macOS control center for Apple's `container` runtime. It makes the complete reviewed runtime surface approachable through SwiftUI while retaining advanced parameters, explicit safety gates, and truthful recovery details.

> **Pre-release:** version 0.1.1 targets macOS 26 or later on Apple silicon. Treat it as early software: keep independent backups of important container data and review every destructive action.

[English](README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

<a id="why"></a>
## Why MacContainer

- Native controls for containers, images, builds, machines, networks, volumes, registries, and system operations.
- Eight safe scenario templates for common workloads, with every generated value visible before execution.
- Direct, typed integration with reviewed Apple container libraries and protocols; production code does not shell out to the `container` CLI.
- Explicit privileged boundaries for runtime installation, upgrade, rollback, and product-owned cleanup.
- Compatibility-gated runtime updates. Unknown versions are held until a signed physical-test attestation and the required probes approve them.
- Local processing with analytics and telemetry disabled by default.
- Complete uninstall that inventories and verifies all 15 product-controlled residue categories.

<a id="requirements"></a>
## Requirements

- macOS 26 or later
- Apple silicon
- An administrator account for runtime installation, update, rollback, or complete uninstall
- Network access only for operations that explicitly contact GitHub, a registry, or an approved update feed

Xcode 26 is required only for development.

<a id="documentation"></a>
## Documentation

- [User Guide](docs/en/USER_GUIDE.md)
- [Installation](docs/en/INSTALLATION.md)
- [Runtime Updates](docs/en/RUNTIME_UPDATES.md)
- [Complete Uninstallation](docs/en/COMPLETE_UNINSTALLATION.md)
- [Troubleshooting](docs/en/TROUBLESHOOTING.md)
- [Architecture](ARCHITECTURE.md), [Privacy](PRIVACY.md), and [Security](SECURITY.md)

All normal product workflows are available in the app. The user guides do not require Terminal.

<a id="development"></a>
## Development

The repository pins project-local build tools and verifies generated files, supply-chain metadata, formatting, tests, accessibility, and release policy.

```console
scripts/bootstrap-tools.sh
scripts/check-repository.sh
xcodebuild -project MacContainer.xcodeproj -scheme MacContainer -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

See [Development](DEVELOPMENT.md) for the isolated workflow and [Contributing](CONTRIBUTING.md) before proposing a change.

<a id="security-support"></a>
## Security and support

Do not post vulnerability details in a public issue. Follow [Security](SECURITY.md) for private reporting. For product support, read [Support](SUPPORT.md) or email [contact@matrixreligio.com](mailto:contact@matrixreligio.com).

The canonical repository is `matrixreligio/macContainer`. MacContainer is licensed under Apache-2.0; see [LICENSE](LICENSE), [NOTICE](NOTICE), and [third-party notices](THIRD_PARTY_NOTICES).
