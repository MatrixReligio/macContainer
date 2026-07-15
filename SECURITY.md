# Security Policy

## Supported versions and branches

Until the first stable release, only the latest commit on `main` receives
security fixes. After stable release, the newest major release branch and the
latest patch release are supported. Older, prerelease, and locally modified
builds are not guaranteed to receive fixes.

## Private reporting

Do not disclose vulnerability details in a public issue, discussion, pull
request, or chat. Report them privately by emailing contact@matrixreligio.com
with the affected version, reproduction conditions, impact, and any suggested
mitigation. If email is unsuitable, request a private GitHub security advisory
without including exploit details in a public channel.

We target acknowledgement within 2 business days. We will validate the report,
agree on a coordinated disclosure timeline, prepare supported-version fixes,
and credit the reporter if requested. Please allow reasonable remediation time
before publication.

## Scope and data

Security-sensitive areas include privileged installation and cleanup, runtime
protocol boundaries, credential storage, update signing, rollback, diagnostic
redaction, and compatibility attestations. MacContainer has no default
telemetry, so reports should include only the minimum redacted diagnostics
needed to reproduce the problem.

See the [threat model](docs/en/THREAT_MODEL.md) and [privacy policy](PRIVACY.md)
for the documented boundaries.
