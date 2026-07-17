---
source_revision: 2b364a7
language: en
document_id: troubleshooting
---

<a id="troubleshooting"></a>
# Troubleshooting

MacContainer reports a stable error code, plain-language explanation, redacted diagnostic detail, retry safety, and one or more recovery actions. Open Activity Center for the full item-level record.

<a id="first-steps"></a>
## First steps

Confirm that macOS is 26 or later, the Mac uses Apple silicon, the application came from the canonical release, and the runtime status is visible in Overview. Refresh the current domain once. If an install, update, rollback, or uninstall is active, let it reach a terminal state before starting another lifecycle action.

Do not repeatedly approve privileged dialogs or retry a destructive action unless the app explicitly says retry is safe. Preserve the activity record when contacting support.

<a id="error-map"></a>
## Error and recovery map

| Error or recovery ID | Meaning | Safe next action |
|---|---|---|
| `error.authentication` | Registry or authorization data was rejected. | Select **Edit credentials**, re-enter the secret, then retry once. |
| `error.upstream-data` | Signed or expected upstream data could not be decoded. | Refresh metadata; do not install the candidate. |
| `error.registry` | A registry request failed without exposing its secret. | Review registry address and credentials, then use **Retry** if offered. |
| `error.helper` | A fixed privileged request was denied or unavailable. | Select **Review authorization** and inspect Activity Center. |
| `error.compatibility` | Catalog, package, attestation, or a required probe failed. | Select **View compatibility report**; do not bypass the hold. |
| `error.lifecycle` | Install, upgrade, rollback, or uninstall did not verify. | Select **Resume recovery** and follow the recorded transaction. |
| `error.container`, `error.image`, `error.build`, `error.machine`, `error.network`, `error.volume`, `error.system` | A domain operation failed. | Review the affected item; retry only when the error says it is safe. |
| `uninstall.recovery.*` | One of the 15 residue categories remains or is unverifiable. | Restore required access, then re-run the residue audit. |

Parameter validation uses the stable key recorded in the field, followed by a matching recovery key. Correct the highlighted value; invalid values are never dispatched automatically.

<a id="update-holds"></a>
## Runtime update holds

An unknown version, invalid catalog, missing physical attestation, unapproved source runtime, package identity mismatch, unavailable rollback point, failed preflight, or failed postflight all stop automatic installation. **Work active** means the update will retry only after containers, machines, builds, builder work, lifecycle transactions, and destructive operations are idle. **Authorization required** means automatic consent or helper authorization is absent; review the update in Settings.

If the target runtime fails a probe, MacContainer blocks that attestation and rolls back. If the prior runtime passes its probes, continue using it and wait for new reviewed evidence. If the app says **Recovery required**, stop runtime work and follow the explicit recovery action; do not remove rollback data manually.

<a id="uninstall-problems"></a>
## Uninstall problems

**Uninstall incomplete** means at least one category is present or unverifiable. Activity Center names the category without revealing private paths. Resolver and packet-filter cleanup may require administrator access. Keychain credentials are removed in the user context. A changed owner, symlink, or unexpected file type is intentionally refused; correct the ownership issue or contact support rather than deleting a broader directory.

See [Complete Uninstallation](COMPLETE_UNINSTALLATION.md) for the exact inventory and Unified Logging exclusion.

<a id="diagnostic-redaction"></a>
## Diagnostic redaction

Diagnostics replace authorization headers, bearer and basic credentials, passwords, secrets, API keys, tokens, usernames, credentials embedded in URLs, private temporary paths, and home-directory user names. Failure details are single-line and length-limited. Templates reject secrets, and secure fields do not persist plain text.

You can retain redacted compatibility and rollback diagnostics in **Settings → Advanced**. Review them before sharing. Never send an unredacted Keychain item, token, private key, or container data.

<a id="support"></a>
## Support

Include the MacContainer version, macOS version, runtime version, stable error code, operation ID, activity timestamp, and redacted diagnostic. Do not include credentials. Read [Support](../../SUPPORT.md) or email [contact@matrixreligio.com](mailto:contact@matrixreligio.com). Security vulnerabilities must follow the private process in [Security](../../SECURITY.md).
