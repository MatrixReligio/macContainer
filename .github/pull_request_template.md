## Purpose

Describe the user-visible outcome and its scope.

## Evidence

- [ ] A focused test failed for the intended reason before production changes.
- [ ] Focused tests now pass.
- [ ] `scripts/check-repository.sh` passes.
- [ ] UI changes include keyboard, VoiceOver, localization, and automation evidence.
- [ ] Privileged/update changes include failure, rollback, and cleanup evidence.

List the exact commands and observed results:

```text

```

## Risk review

- [ ] No production code invokes the `container` CLI or upstream lifecycle scripts.
- [ ] Security, privacy, compatibility, data ownership, and uninstall effects were reviewed.
- [ ] Documentation and changelog are updated where behavior changed.
- [ ] No credentials, personal data, generated build products, or local machine paths are included.

Related issue:
