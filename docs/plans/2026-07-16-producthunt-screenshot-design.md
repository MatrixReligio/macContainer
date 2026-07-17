# Product Hunt Screenshot Capture Design

## Goal

Create polished, repeatable MacContainer screenshots during macOS UI automation without
capturing desktop content or relying on manual window placement. The image set should
communicate the product's four core promises: an approachable native UI, safe templates,
compatibility-gated runtime upgrades with rollback, and complete uninstall verification.

## Approaches considered

1. **XCUITest window capture (selected).** Capture the identified app window after deterministic
   fake-runtime setup. This is repeatable, excludes desktop privacy, and can be regenerated for
   whenever the English UI changes.
2. OS-level `screencapture`. This preserves the window shadow but depends on window placement,
   Screen Recording permission, and the current desktop state.
3. Manual screenshots. This offers flexible art direction but is not reproducible and is easy to
   let drift from the shipped UI.

## Image set

The English baseline contains six app-window PNG files:

- `01-overview.png` — native resource overview and primary navigation.
- `02-scenario-templates.png` — safe outcome-first templates and host-aware defaults.
- `03-compatible-upgrade.png` — signed update approval, compatibility gate, and rollback point.
- `04-complete-uninstall.png` — explicit destructive confirmation and owned-artifact inventory.
- `05-terminal-safety.png` — direct terminal session with blocked remote side effects.
- `06-actionable-error.png` — diagnostic detail and recovery actions.

A manifest records the English locale, app version, dimensions, capture test, suggested Product
Hunt caption, and SHA-256 digest. Product Hunt screenshots are English-only; Stage 7 localization
testing does not generate additional marketing variants.

## Capture architecture

`MarketingScreenshotTests` launches only the fake runtime with reset state, selects a stable
fixture, waits for an explicit readiness identifier, and calls `XCUIElement.screenshot()` on the
main window. It writes PNG data only when `MARKETING_SCREENSHOT_DIR` is supplied and also keeps
an XCTest attachment for debugging. A repository script runs the selected test suite into a
temporary DerivedData directory, validates dimensions and file signatures, generates the
manifest, and removes temporary build/test artifacts.

## Quality and privacy gates

- No real Apple container command, user credential, home path, or desktop pixel may appear.
- Fake content must look plausible but use reserved/invalid example hosts where applicable.
- Screenshots must contain no audit sidebar, cursor, alert prompt, debug overlay, or clipped text.
- Window size, color scheme, contrast, and reduced-motion settings are explicit test inputs.
- PNG dimensions and digests are verified; each final image is inspected before handoff.
