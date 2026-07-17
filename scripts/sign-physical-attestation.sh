#!/bin/zsh
set -euo pipefail

if [[ $# -ne 2 ]]; then
    print -u2 -- "usage: $0 unsigned-attestation.json signed-attestation.json"
    exit 64
fi

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
private_key="${MACCONTAINER_ATTESTATION_PRIVATE_KEY:-}"

if [[ -z "$private_key" || "$private_key" != /* || "$private_key" == "$repo_root"/* ]]; then
    print -u2 -- "MACCONTAINER_ATTESTATION_PRIVATE_KEY must name a key outside the repository"
    exit 77
fi
if [[ -L "$private_key" || ! -f "$private_key" ]]; then
    print -u2 -- "attestation private key must be a regular non-symlink file"
    exit 77
fi
permissions="$(/usr/bin/stat -f '%Lp' "$private_key")"
owner="$(/usr/bin/stat -f '%u' "$private_key")"
if [[ "$permissions" != "600" || "$owner" != "$EUID" ]]; then
    print -u2 -- "attestation private key must be owned by the caller with mode 0600"
    exit 77
fi

cd "$repo_root"
exec /usr/bin/swift run --quiet mc-attestation sign "$1" "$2" --private-key "$private_key"
