#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
checker="$repo_root/scripts/check-licenses.swift"
resolved="$repo_root/MacContainer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
inventory="$repo_root/Config/dependencies.json"
licenses="$repo_root/ThirdPartyLicenses"
notices="$repo_root/THIRD_PARTY_NOTICES"
fixture="$(mktemp -d "${TMPDIR%/}/maccontainer-license-policy.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

swift "$checker" "$resolved" "$inventory" "$licenses" "$notices"

ditto "$inventory" "$fixture/dependencies.json"
/usr/bin/jq '.dependencies[0].licenseID = "AGPL-3.0-only"' "$inventory" > "$fixture/forbidden.json"
if swift "$checker" "$resolved" "$fixture/forbidden.json" "$licenses" "$notices" >/dev/null 2>&1; then
    print -u2 -- "checker accepted a forbidden license"
    exit 1
fi

ditto "$licenses" "$fixture/licenses"
first_license="$(/usr/bin/jq -r '.dependencies[0].licenseFile' "$inventory")"
print -n -- 'mutated' >> "$fixture/licenses/$first_license"
if swift "$checker" "$resolved" "$inventory" "$fixture/licenses" "$notices" >/dev/null 2>&1; then
    print -u2 -- "checker accepted a modified license text"
    exit 1
fi

/usr/bin/jq 'del(.dependencies[0])' "$inventory" > "$fixture/missing.json"
if swift "$checker" "$resolved" "$fixture/missing.json" "$licenses" "$notices" >/dev/null 2>&1; then
    print -u2 -- "checker accepted a missing resolved dependency"
    exit 1
fi

print -r -- "License policy mutation tests PASS"

SOURCE_DATE_EPOCH=1784044800 swift "$repo_root/scripts/generate-sbom.swift"
first_hashes="$(/usr/bin/shasum -a 256 "$repo_root/dist/MacContainer.cdx.json" "$repo_root/dist/MacContainer.spdx.json")"
SOURCE_DATE_EPOCH=1784044800 swift "$repo_root/scripts/generate-sbom.swift"
second_hashes="$(/usr/bin/shasum -a 256 "$repo_root/dist/MacContainer.cdx.json" "$repo_root/dist/MacContainer.spdx.json")"
[[ "$first_hashes" == "$second_hashes" ]] || {
    print -u2 -- "SBOM regeneration changed output hashes"
    exit 1
}
(cd "$repo_root" && /usr/bin/shasum -a 256 -c dist/sbom-checksums.txt)
print -r -- "SBOM reproducibility PASS"
