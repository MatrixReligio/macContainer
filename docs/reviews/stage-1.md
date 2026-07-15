# Stage 1: Foundation architecture and supply-chain review

- Review date: 2026-07-16
- Reviewed branch: `feature/maccontainer-implementation`
- Gate: PASS

## Verification result

The complete local foundation gate passed after resolving the Apple-silicon
finding below:

```text
swift test --parallel
PASS: 12 tests in 2 suites

scripts/check-repository.sh
PASS: repository, contract, generated project, icon, workflow, OSS, format,
lint, and package tests

xcodebuild ... -configuration Debug ... CODE_SIGNING_ALLOWED=NO build
PASS

xcodebuild ... -configuration Release ... CODE_SIGNING_ALLOWED=NO build
PASS

lipo -archs MacContainer.app/Contents/MacOS/MacContainer
PASS: arm64 in both Debug and Release

git diff --check
PASS
```

Both Xcode builds used repository-local DerivedData and cloned-package paths.
After verification, the main apps and Sparkle's nested Updater apps were
unregistered from LaunchServices, the saved-state path was confirmed absent,
and all Stage 1 DerivedData was removed.

## Finding resolved during review

### F-1: Release was not restricted to the supported architecture

The first Release review produced an `arm64 x86_64` main executable even though
MacContainer and Apple container require Apple silicon. This could imply false
Intel support and made hosted builds compile an unnecessary architecture.

TDD evidence:

1. `check-generated-project.sh` was extended to require `ARCHS: arm64` in the
   XcodeGen source and generated project.
2. The focused checker failed with `project.yml must restrict application
   products to arm64`.
3. `project.yml` was fixed, the project regenerated with pinned XcodeGen, and
   the checker passed.
4. Workflow policy was extended to require `ARCHS=arm64` on all four app
   build/test invocations; it failed before the workflow change and passed
   afterward.
5. Fresh Debug and Release products both reported exactly `arm64` via `lipo`.

The official GitHub runner-images matrix identifies `macos-26` as arm64, so the
restriction matches the hosted environment.

## Module dependency review

The dependency graph is acyclic and points from stable models toward
composition:

| Module | Direct app-owned dependencies | Review |
| --- | --- | --- |
| `MCModel` | none | Stable leaf types and identity |
| `MCContracts` | `MCModel` | Versioned upstream facts only |
| `MCTemplates` | `MCModel`, `MCContracts` | Pure template/model layer |
| `MCContainerBridge` | `MCModel`, `MCContracts` | Sole direct upstream runtime boundary |
| `MCCompatibility` | model, contracts, bridge | Evaluates bridge evidence |
| `MCSystemLifecycle` | model, contracts, bridge, compatibility | Owns privileged lifecycle policy |
| `MCAppCore` | all app-owned feature modules | Unprivileged workflow composition |

Only `MCContainerBridge` imports Apple container runtime products. The helper
depends on model plus lifecycle; the update agent depends on model, lifecycle,
and compatibility. Neither executable depends on SwiftUI, Sparkle, or SwiftTerm.

## Identity and containment review

| Product | Identity or path | Containment result |
| --- | --- | --- |
| Main app | `container.matrixreligio.com` | macOS 26, arm64, hardened runtime, App Sandbox intentionally disabled |
| Helper | `container.matrixreligio.com.helper` | Fixed requirement for Team `4DUQGD879H`; no dynamic executable/path input at this stage |
| Update agent | `container.matrixreligio.com.update-agent` | Fixed bundle path and 24-hour schedule; `RunAtLoad` is false |
| UI tests | `container.matrixreligio.com.ui-tests` | Fake-runtime launch only |

All three entitlement files are empty at the foundation stage. No accidental
App Sandbox, network, automation, keychain group, or broad temporary exception
was introduced. The helper has `KeepAlive: false` and `RunAtLoad: false`; the
agent has `RunAtLoad: false`. Until their authenticated protocols are built,
normal invocation exits with `EX_UNAVAILABLE` and only the explicit build smoke
argument succeeds.

The built app contained the helper, agent, launch plists, icon assets, Sparkle,
and SwiftTerm only in their fixed reviewed bundle locations. Its generated
Info.plist contained the expected app ID, five localization declarations,
version `0.1.0 (1)`, Sparkle feed, and helper signing requirement.

## Dependency and generated-build review

Direct release inputs are exact:

| Input | Version | Immutable identity |
| --- | --- | --- |
| Apple container | 1.1.0 | `5973b9cc626a3e7a499bb316a958237ebe14e2ed` |
| Sparkle | 2.9.4 | `b6496a74a087257ef5e6da1c5b29a447a60f5bd7` |
| SwiftTerm | 1.13.0 | `8e7a1e154f470e19c709a00a8768df348ba5fc43` |
| XcodeGen | 2.45.4 | archive SHA-256 `090ec29491aad50aec10631bf6e62253fed733c50f3aab0f5ffc86bc170bdbef` |
| SwiftFormat | 0.62.1 | archive SHA-256 `7cb1cb1fae04932047c7015441c543848e8e60e1572d808d080e0a1f1661114a` |
| SwiftLint | 0.65.0 | archive SHA-256 `d6cb0aa7a2f5f1ef306fc9e37bcb54dc9a26facc8f7784ac0c3dd3eccf5c6ba6` |

The root package lock and Xcode workspace lock intentionally differ only by the
Xcode-only Sparkle and SwiftTerm pins; every shared transitive pin and revision
matches. Regeneration with XcodeGen 2.45.4 produced no project, scheme, or
Info.plist drift.

## CI, repository, and open-source review

All third-party actions use full 40-character SHAs:

- `actions/checkout`: `9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0`
- `actions/upload-artifact`: `330a01c490aca151604b8cf639adc76d48f6c5d4`
- `actions/github-script`: `ed597411d8f924073f98dfc5c65a23a2325f34cd`

CI uses arm64 macOS 26 runners, top-level `contents: read`, no secrets, and a
secret-free verification job before UI testing. The upstream monitor alone has
job-scoped `issues: write`; it can create a draft review issue but cannot change
code or compatibility state. Negative workflow tests reject mutable action
tags, top-level secrets, and unguarded secret-bearing jobs.

The public repository is `MatrixReligio/macContainer`, default branch `main`,
issues enabled, wiki/projects disabled, and delete-merged-branch enabled. The
open-source checker reports 16 policy documents, the Apache-2.0 identifier,
approved contact address, required security policy, and zero broken local
links. Its negative tests reject an unapproved email, a broken link, and a
missing response-time policy.

## Hosted baseline

Run `29438722828` at commit
`300c94f9cb8595808f066d1a44295ff4989b68e2` passed the secret-free repository,
coverage, Debug, and Release job plus the isolated integration/UI job. The
downloaded Xcode result summary reported `result: Passed`, 2 passed tests, 0
failed, 0 skipped, and an arm64 macOS 26.4 Apple virtual machine. The temporary
artifact download was removed immediately after inspection.
