# Code Style

Prefer straightforward Swift with explicit domain types, small dependency
surfaces, and names that describe user-visible intent. Optimize for safe review
rather than cleverness.

## Swift

- Follow the repository SwiftFormat and SwiftLint configurations.
- Use structured concurrency and make actor or sendability boundaries explicit.
- Represent commands and parameters as typed values; do not concatenate shell
  command strings.
- Inject clocks, filesystems, networking, and privileged clients so failure
  paths are testable.
- Keep errors structured, localizable, redacted, and paired with recovery
  actions where possible.
- Document public API invariants and security-sensitive assumptions.

## UI and content

- Use native SwiftUI controls and macOS terminology.
- Supply keyboard access, accessibility labels, help text, focus order, and
  reduced-motion behavior with the feature, not afterward.
- Every consequential parameter needs contextual help and a visible effective
  value before execution.
- User-facing strings belong in localization catalogs; do not assemble
  sentences from fragments.

Formatting is mechanical. Run `scripts/check-repository.sh` before review.
