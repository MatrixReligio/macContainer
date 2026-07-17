---
source_revision: 2b364a7
language: en
document_id: installation
---

<a id="installation"></a>
# Installation

MacContainer requires macOS 26 or later on Apple silicon. The application can open without the Apple container runtime, but container operations remain unavailable until a reviewed runtime is installed.

<a id="before-installing"></a>
## Before installing

Download MacContainer only from the canonical GitHub release. Confirm that macOS identifies the application as signed and notarized. Move it to Applications, then open it normally. Do not bypass a Gatekeeper warning; if macOS cannot verify the app, remove that copy and download the published release again.

MacContainer does not silently install the runtime. Open **Settings → Runtime** to see the candidate version, source, signer, SHA-256 status, disk impact, and compatibility state before any privileged action.

<a id="runtime-package"></a>
## Runtime package verification

The embedded compatibility catalog currently recognizes Apple container 1.1.0 for MacContainer 0.1.x. Its reviewed package identity includes:

- Asset: `container-1.1.0-installer-signed.pkg`
- Installer team: `UPBK2H6LZM`
- Signer: `Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)`
- Receipt: `com.apple.container-installer`
- SHA-256: `0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714`

MacContainer downloads into a private staging directory, rejects links and unexpected file types, checks the exact byte count and digest, verifies the installer signature and receipt identity, and only then enables **Review and install**. A metadata match alone is never sufficient.

<a id="administrator-approval"></a>
## Administrator approval

Administrator approval is requested only after download, verification, and your final review, when installation actually begins. The privileged helper accepts fixed, typed operations and reviewed paths; it does not accept arbitrary shell text. Canceling the approval leaves the current runtime unchanged and clears the private staging area.

During installation, Activity Center records the transaction phases. Closing the main window does not convert a failed or interrupted transaction into success. On the next launch, MacContainer reads the durable lifecycle journal and offers only the verified recovery action.

<a id="post-install"></a>
## Post-install compatibility

Installation is not considered complete merely because the package installer succeeds. MacContainer checks runtime health and all required API domains: containers, images, builder, networks, volumes, registries, machines, disk usage, configuration, and capabilities. It also verifies the installed version and owned-artifact baseline.

If every probe passes, Runtime status becomes **Ready**. If a probe fails during an upgrade, MacContainer restores the retained rollback point and verifies the previous runtime. A first installation that cannot pass postflight is reported as incomplete with a recovery action.

<a id="app-updates"></a>
## Updating MacContainer

Application updates and Apple container runtime updates are separate. MacContainer application updates use the signed Sparkle feed and preserve application settings. Runtime behavior follows the stricter compatibility policy described in [Runtime Updates](RUNTIME_UPDATES.md).

For removal choices, read [Complete Uninstallation](COMPLETE_UNINSTALLATION.md). For signing, authorization, or health errors, read [Troubleshooting](TROUBLESHOOTING.md).
