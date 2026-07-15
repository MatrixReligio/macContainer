# Privacy

MacContainer processes container configuration, state, and diagnostics locally.
It has no telemetry, advertising identifiers, analytics, or crash upload by
default.

Network requests occur only when the user requests or enables an operation that
needs them, such as checking GitHub releases, accessing a container registry,
pulling an image, or checking an app update feed. The destination, purpose, and
effective parameters must be visible in the workflow. Registry providers and
GitHub apply their own privacy terms.

Credentials and tokens are stored in macOS Keychain when persistence is
requested. They must not be written to project files, logs, diagnostics,
compatibility attestations, or telemetry. Diagnostics are locally generated,
redacted by default, previewed before export, and shared only by an explicit
user action.

Uninstall removes MacContainer-owned application state, helpers, agents,
receipts, caches, logs, and update artifacts in the selected scope. User-owned
container data is kept unless the user separately and explicitly selects its
removal. The cleanup report identifies retained and removed paths without
exposing secrets.

Privacy questions can be sent to contact@matrixreligio.com. Security reports
must follow [Security](SECURITY.md).
