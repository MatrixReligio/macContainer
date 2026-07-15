# Contributing

Thank you for improving MacContainer. Contributions must preserve the product's
direct-runtime architecture, privilege boundaries, compatibility gates, and
accessibility commitments.

## Before opening a change

1. Search existing issues and open a focused proposal for behavior changes.
2. Do not publish suspected vulnerabilities; follow [Security](SECURITY.md).
3. Work from `main` in a short-lived branch.
4. Add a failing test before production behavior, then make the smallest change
   that passes it.
5. Run the complete repository gate and relevant Xcode tests.

```console
scripts/bootstrap-tools.sh
scripts/check-repository.sh
```

Changes to Apple container behavior must update the versioned contract evidence
and preserve exact operation coverage. Privileged or updater changes also need
failure-injection and cleanup tests. UI changes need keyboard, VoiceOver,
localization, and macOS automation evidence.

## Pull requests

Complete the pull request template, keep commits reviewable, and record the test
commands that actually ran. A maintainer may ask for a threat-model or
compatibility review. By contributing, you agree that your contribution is
licensed under the repository's Apache-2.0 license.

See [Development](DEVELOPMENT.md), [Code style](CODE_STYLE.md), and
[Governance](GOVERNANCE.md) for the rest of the project policy.
