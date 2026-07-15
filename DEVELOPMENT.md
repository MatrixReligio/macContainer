# Development

## Prerequisites

- macOS 26 on Apple silicon
- Xcode 26 selected with `xcode-select`
- Git and the standard macOS command-line tools

Do not install unpinned global formatters for this project. Bootstrap verifies
checksums and installs SwiftFormat and SwiftLint under `.tools`:

```console
scripts/bootstrap-tools.sh
```

## Test-driven workflow

1. Add the narrowest failing test and observe the intended failure.
2. Implement the smallest production change that passes it.
3. Run the focused test, then the deterministic repository gate.
4. Review failure paths, security boundaries, accessibility, and cleanup.
5. Commit one coherent change with its evidence.

```console
scripts/check-repository.sh
swift test --parallel
xcodebuild -project MacContainer.xcodeproj -scheme MacContainer \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Use project-local `.build` paths for derived artifacts. Tests that touch the
filesystem must use unique temporary directories and remove them. Never weaken
Gatekeeper, change machine-wide security settings, or install an Apple runtime
on a developer machine unless a physical-validation procedure explicitly
authorizes it.

Architecture and policy changes must update [Architecture](ARCHITECTURE.md),
[Security](SECURITY.md), or [Privacy](PRIVACY.md) in the same pull request.
