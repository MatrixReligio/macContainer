# MacContainer Product Hunt screenshots

These six English screenshots are generated from deterministic macOS UI tests and are ordered for a Product Hunt gallery:

1. `01-overview.png` — See runtime health, compatibility, and the safest next action at a glance.
2. `02-scenario-templates.png` — Start from a goal while MacContainer fills in conservative, host-aware defaults.
3. `03-compatible-upgrade.png` — Automatically install only signed, compatibility-approved Apple container updates, with a verified rollback point.
4. `04-complete-uninstall.png` — Inventory and remove every runtime-owned artifact without leaving hidden residue.
5. `05-terminal-safety.png` — Use a direct interactive session while remote clipboard, links, notifications, and title changes stay blocked.
6. `06-actionable-error.png` — Recover from failures with redacted diagnostics and safe, concrete next actions.

## Regenerate

From the repository root:

```sh
MACCONTAINER_CODE_SIGN_IDENTITY="<Apple Development certificate hash>" \
MACCONTAINER_DEVELOPMENT_TEAM="<team ID>" \
scripts/capture-producthunt-screenshots.sh
```

The signing variables are optional when the local Xcode configuration can already sign the UI test Runner.

## Privacy and repeatability

- The app launches only with `--fake-runtime` and fixed English locale arguments.
- XCTest captures only the identified MacContainer window, never the desktop.
- The test Runner retains named screenshots as `.xcresult` attachments only when the explicit output switch is present; the driver exports and validates them after the test exits.
- Fixtures contain no user paths, credentials, live runtime state, current dates, or network data.
- A cleanup trap removes DerivedData, the result bundle, exported attachments, and staging files after every run.
- `manifest.sha256` records the six final PNG digests.
