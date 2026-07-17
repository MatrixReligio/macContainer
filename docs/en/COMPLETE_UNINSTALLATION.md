---
source_revision: f94970774a25e899b7fb4a623d35c555d11f12e2
language: en
document_id: complete-uninstallation
---

<a id="complete-uninstallation"></a>
# Complete Uninstallation

MacContainer provides two deliberately different removal choices in **Settings → Runtime**. Read the summary and current inventory before choosing either one.

<a id="preserve-data"></a>
## Remove runtime and preserve data

This option removes the runtime components while keeping container images, volumes, user configuration, and registry credentials. Use it when you plan to reinstall or want to retain workloads. The completion message explicitly says that user data was preserved; it is not a complete uninstall.

<a id="complete-choice"></a>
## Complete uninstall

Complete uninstall permanently removes the Apple container runtime and all product-controlled runtime data, credentials, caches, test fixtures, and rollback points. The button remains disabled until you type the exact phrase `REMOVE APPLE CONTAINER`.

Immediately before removal, MacContainer refreshes the inventory rather than trusting an earlier screen. It gracefully stops workloads and services, verifies that reviewed processes have exited, removes user-context credentials, requests only fixed privileged cleanup operations, and then runs an independent residue audit. A missing or unverifiable category prevents a success result.

<a id="residue-inventory"></a>
## Fifteen residue categories

The zero-residue contract covers:

1. reviewed launch services;
2. runtime processes;
3. the installer receipt;
4. receipt-owned payload files;
5. runtime Application Support data;
6. user configuration under the reviewed container configuration root;
7. the runtime defaults domain;
8. registry credentials in Keychain;
9. container DNS resolver entries;
10. container packet-filter anchors and rules;
11. downloaded runtime packages;
12. retained rollback points;
13. physical-test fixtures;
14. runtime download caches; and
15. reviewed runtime-owned directories.

Removal uses exact, freshly inventoried URLs and manifest intersections. It refuses symlinks, unexpected file types, path traversal, unknown ownership, and overbroad directory deletion. Known parent directories are removed only when empty.

<a id="verification"></a>
## Verification and recovery

After cleanup, the independent auditor rechecks all 15 categories and returns **Complete** only if every category is proven absent. **Unverifiable** is treated as failure, not absence. Activity Center identifies remaining categories and their stable recovery keys. Restore administrator access or resolve the reported ownership issue, then select **Re-run residue audit** or resume the durable uninstall transaction.

MacContainer never converts a partially completed uninstall into success. The lifecycle journal allows safe resumption after interruption without repeating already verified destructive steps.

<a id="unified-logging"></a>
## macOS Unified Logging exclusion

Historical entries already committed to macOS Unified Logging are managed by macOS and cannot be selectively deleted by an application. They are not writable product residue and are therefore excluded from the zero-residue claim. MacContainer still removes every product-controlled file, service, process, credential, rule, receipt, package, cache, test artifact, and rollback point listed above. Diagnostics redact credentials and private paths before logging.

For a failed category or authorization problem, read [Troubleshooting](TROUBLESHOOTING.md). For reinstalling later, read [Installation](INSTALLATION.md).
