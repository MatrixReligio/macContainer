---
source_revision: f94970774a25e899b7fb4a623d35c555d11f12e2
language: en
document_id: user-guide
---

<a id="user-guide"></a>
# MacContainer User Guide

MacContainer provides native controls for the reviewed Apple container runtime without requiring Terminal. It shows effective values, safety impact, progress, and recovery information before and after every operation.

<a id="getting-started"></a>
## Getting started

On first launch, choose **Start with Simple Mode**. Pick an outcome, enter the image reference and any workspace or port information, then select **Review all values**. The review shows the native operation, every generated value, its source, and differences from the Apple default. Nothing runs until you select **Run**.

The eight built-in scenarios are immutable. They favor a read-only root filesystem, local-only networking where appropriate, graceful shutdown, and host-aware CPU and memory recommendations. Home-folder sharing and nested virtualization remain off until you explicitly enable them.

Switch to Advanced controls whenever you need the complete Apple contract. Values entered in Simple Mode remain editable and are not discarded.

<a id="domains"></a>
## Domains

- **Overview** reports runtime health, compatibility status, running work, recent activity, and the safest next action.
- **Containers** creates, starts, stops, inspects, copies, exports, removes, and opens interactive sessions for containers.
- **Images** pulls, pushes, loads, saves, tags, inspects, and removes OCI images.
- **Builds** configures native builds and shows progress in Activity Center.
- **Machines** manages the virtual machines used by the runtime, including configuration, logs, and default selection.
- **Networks** creates and audits container networks, DNS, and packet-filter state.
- **Volumes** creates, inspects, and removes persistent storage.
- **Registries** manages registry sessions through **Log In** and secure credential entry. An empty list means no reviewed credential is stored; log in and then refresh. Secret values are never written into templates or diagnostics.
- **System** exposes runtime status, version, disk use, logs, configuration, service state, and kernel selection.

Select a resource row to inspect details. **Refresh** reloads the current domain. Destructive actions display an explicit confirmation with the affected resource and recovery expectation.

<a id="machine-workflow"></a>
## Machine workflow

Open **Machines** and select **New Machine**. Simple Mode opens with **Linux machine** selected; review the generated machine name, image, CPU, and memory, then select **Run**. The machine is created and started by default. Home-folder sharing and nested virtualization remain disabled during creation.

Select one machine to use **Configure**, where you can change CPU and memory or explicitly enable read-only home-folder sharing and nested virtualization. **Start** and **Stop** act on the selected machines. **Delete** always shows the affected machine identifiers before removal.

<a id="registry-workflow"></a>
## Registry workflow

Apple container does not operate a general-purpose image-hosting service. It consumes and produces standard OCI images, so public images can be pulled anonymously and private credentials can be used with OCI-compatible services such as Docker Hub, GitHub Container Registry, Amazon ECR, Google Artifact Registry, Azure Container Registry, Harbor, and compatible self-hosted registries.

Open **Registries** and select **Log In**. Enter the registry hostname without an image path, your username, and the password or access token required by that provider. For Docker Hub use `docker.io`; for GitHub Container Registry use `ghcr.io` and a personal access token with the required package scope. MacContainer verifies the endpoint before storing a device-only credential in the same Apple container registry security domain used for image pulls, pushes, and machine creation. Public registries do not require a saved login for anonymous pulls.

<a id="parameters"></a>
## Parameters and review

Every supported upstream parameter has a localized label, concise explanation, detailed purpose, default, accepted format, repeat and ordering behavior, dependencies and conflicts, platform limits, security or data impact, example, validation message, and recovery action. Select the information button beside a field to read it.

Required fields are marked. Repeated values preserve the order you enter. Path and URL values are validated before dispatch. The final review identifies changed values and security-sensitive capabilities. Production operations use the typed runtime bridge; no shell command is generated.

<a id="templates"></a>
## Templates

Open **Settings → Defaults & Templates → Open Template Library** to select a built-in template and inspect its purpose and operation. Built-ins are immutable. Use **New** or **Duplicate** to create a custom template, edit its name, operation, and workload fields in the detail pane, then select **Save**. Custom templates persist in Application Support and can be selected, edited, exported, or deleted later. Import migrates supported older schema versions and blocks secrets or unknown high-impact fields before saving; credentials and authorization material are always excluded.

<a id="terminal"></a>
## Interactive terminal

Interactive container sessions use the embedded terminal view. Remote clipboard requests, links, notifications, and title changes are blocked. **Detach** leaves the workload running; **Terminate** sends the reviewed termination signal. With Reduce Motion enabled, output updates without decorative animation.

<a id="activity-settings"></a>
## Activity Center and settings

Activity Center records operation progress and item-level outcomes. Open it from the Window menu or with the keyboard shortcut below. Errors include a stable code, a plain-language cause, a redacted diagnostic, whether retry is safe, and relevant recovery actions.

Settings contain:

- **General:** Simple Mode preference, application language, and privacy summary.
- **Runtime:** install, preserve-data removal, and complete uninstall controls.
- **Runtime Updates:** check-only, download-and-notify, or automatic-when-idle policy.
- **Compatibility:** fail-closed evidence and approved runtime information.
- **Defaults & Templates:** built-in defaults and the template library.
- **Advanced:** redacted diagnostic retention and residue re-audit.
- **About:** version, license, and support contact.

Changing language waits for unsaved work and active operations, then relaunches safely.

<a id="keyboard-accessibility"></a>
## Keyboard and accessibility

- Command–N opens a new scenario.
- Command–R refreshes the current domain.
- Command–Shift–L opens Activity Center.
- Command–1 through Command–9 select Overview through System.

All primary controls expose accessibility labels and stable identifiers. Keyboard focus has a visible indicator, tables and inspectors are navigable without a pointer, Dynamic Type and increased contrast remain readable, and Reduce Motion is respected.

<a id="data-support"></a>
## Data, export, and support

MacContainer performs local processing and sends no analytics or telemetry by default. Network requests occur only for an operation you initiate or an update mode you enable. Exported templates are intended for reviewable configuration, not backups of images or volumes; maintain separate backups for persistent data.

For installation help, read [Installation](INSTALLATION.md). For updates, read [Runtime Updates](RUNTIME_UPDATES.md). For removal, read [Complete Uninstallation](COMPLETE_UNINSTALLATION.md). If an operation fails, use [Troubleshooting](TROUBLESHOOTING.md) or contact [contact@matrixreligio.com](mailto:contact@matrixreligio.com).
