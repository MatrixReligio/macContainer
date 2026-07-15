# Architecture

MacContainer is a native SwiftUI application whose unprivileged core talks
directly to reviewed Apple container libraries and protocols. Shelling out to
the `container` CLI is prohibited in production sources.

## Modules

- `MCContracts` stores the versioned upstream operation and parameter contract.
- `MCModel` owns typed domain models and stable product identity.
- `MCTemplates` provides explicit, reviewable scenario defaults.
- `MCContainerBridge` implements direct runtime operations.
- `MCSystemLifecycle` coordinates installation, upgrade, rollback, and cleanup.
- `MCCompatibility` evaluates signed compatibility evidence and update holds.
- `MCAppCore` composes workflows for the SwiftUI application.
- `MacContainer` is the sandboxed user-facing app.
- The privileged helper exposes a narrow authenticated lifecycle protocol.
- The update agent checks app and runtime updates under explicit policy.

Dependencies point inward toward typed contracts and models. UI code does not
own privileged logic, construct arbitrary commands, or silently change runtime
compatibility state.

## Trust boundaries

Only the signed privileged helper may invoke the fixed system installation and
service-management tools permitted by policy. Requests are allowlisted,
versioned, authenticated, idempotent, and recorded without secrets. Runtime
upgrades are staged, verified, compatibility-tested, and committed only after a
health check; failure retains or restores the last known-good version.

Product-owned files are inventoried before mutation so uninstall can remove
them without deleting user-owned container data unless the user explicitly
chooses that scope. See the [threat model](docs/en/THREAT_MODEL.md) for abuse
cases and [Privacy](PRIVACY.md) for data handling.
