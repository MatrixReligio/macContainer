#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
fixture="$(mktemp -d "${TMPDIR%/}/maccontainer-upstream-policy.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
monitor="$repo_root/.github/workflows/upstream-monitor.yml"
verification="$repo_root/.github/workflows/verify-compatibility-pr.yml"
inspector="$repo_root/scripts/inspect-upstream-release.swift"

for file in "$monitor" "$verification" "$inspector"; do
    [[ -f "$file" ]] || { print -u2 -- "missing required file: ${file#$repo_root/}"; exit 1; }
done

for workflow in "$monitor" "$verification"; do
    /usr/bin/ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' "$workflow"
    if /usr/bin/grep -Eq 'contents:[[:space:]]*write|pull_request_target|auto-merge|merge_method' "$workflow"; then
        print -u2 -- "workflow grants forbidden mutation authority: ${workflow#$repo_root/}"
        exit 1
    fi
    while IFS= read -r use; do
        [[ "${use##*@}" =~ '^[0-9a-f]{40}$' ]] || {
            print -u2 -- "mutable action reference: $use"
            exit 1
        }
    done < <(/usr/bin/sed -En 's/^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*([^#[:space:]]+).*/\1/p' "$workflow")
done

/usr/bin/grep -Fq 'Status: UNVERIFIED' "$inspector"
/usr/bin/grep -Fq 'Compatibility candidate: Apple container' "$inspector"
/usr/bin/grep -Fq 'scripts/inspect-upstream-release.swift' "$monitor"
/usr/bin/grep -Fq 'scripts/verify-physical-attestation.swift' "$verification"
/usr/bin/grep -Fq 'pulls.listReviews' "$verification"

if /usr/bin/grep -Eq 'Config/compatibility/catalog-v1.json|git[[:space:]]+(add|commit|push)|compatib(le|ility).*label' "$monitor"; then
    print -u2 -- "monitor can modify compatibility authority"
    exit 1
fi

before="$(git -C "$repo_root" status --porcelain=v1)"
output="$(swift "$inspector" --fixture "$repo_root/Tests/Fixtures/github/apple-container-release-1.1.0.json")"
after="$(git -C "$repo_root" status --porcelain=v1)"
[[ "$before" == "$after" ]]
[[ "$output" == *'Compatibility candidate: Apple container 1.1.0'* ]]
[[ "$output" == *'Status: UNVERIFIED'* ]]
[[ "$output" == *'container-1.1.0-installer-signed.pkg'* ]]

print -n -- 'independently downloaded installer fixture' > "$fixture/installer.pkg"
size="$(/usr/bin/stat -f '%z' "$fixture/installer.pkg")"
/usr/bin/jq --argjson size "$size" '.assets[0].size = $size' \
    "$repo_root/Tests/Fixtures/github/apple-container-release-1.1.0.json" \
    > "$fixture/release.json"
digest="$(/usr/bin/shasum -a 256 "$fixture/installer.pkg" | /usr/bin/awk '{print $1}')"
hashed="$(swift "$inspector" --fixture "$fixture/release.json" --asset-file "$fixture/installer.pkg")"
[[ "$hashed" == *"Independent SHA-256: $digest"* ]]

print -r -- "Upstream monitor policy PASS: metadata-only issue, immutable compatibility authority"
