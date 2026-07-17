# Physical compatibility attestations

This directory is intentionally fail-closed until a physical-host run produces
and signs `apple-container-1.1.0.json` together with its public
`apple-container-1.1.0.expectations.json` verification contract. Release builds
copy the signed evidence and the versioned physical test plan into the
application resources. Private signing keys never belong in this directory or
repository.
