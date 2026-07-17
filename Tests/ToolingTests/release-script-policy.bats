#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
scripts=(
    release-common.sh sign.sh package.sh notarize.sh generate-appcast.sh
    release.sh verify-release.sh verify-sparkle-signature.swift
)

for name in $scripts; do
    file="$repo_root/scripts/$name"
    [[ -f "$file" ]] || { print -u2 -- "missing release script: scripts/$name"; exit 1; }
done

require_text() {
    local file="$1"
    local text="$2"
    /usr/bin/grep -Fq -- "$text" "$repo_root/$file" || {
        print -u2 -- "$file missing policy: $text"
        exit 1
    }
}

require_text scripts/release-common.sh 'Developer ID Application: MatrixReligio LLC (4DUQGD879H)'
require_text scripts/release-common.sh '4DUQGD879H'
require_text scripts/release-common.sh 'require_clean_tracked_worktree'
require_text scripts/sign.sh '--options runtime'
require_text scripts/sign.sh 'Contents/Frameworks/Sparkle.framework'
require_text scripts/sign.sh 'Contents/Library/PrivilegedHelperTools/container.matrixreligio.com.helper'
require_text scripts/sign.sh 'Contents/Library/LoginItems/container.matrixreligio.com.update-agent'
require_text scripts/sign.sh 'container.matrixreligio.com.helper'
require_text scripts/sign.sh 'container.matrixreligio.com.update-agent'
require_text scripts/sign.sh 'container.matrixreligio.com'
require_text scripts/sign.sh 'verify_designated_requirement'
require_text scripts/package.sh 'trap cleanup EXIT INT TERM'
require_text scripts/package.sh '/Applications'
require_text scripts/notarize.sh 'maccontainer-notary'
require_text scripts/notarize.sh 'MC_ALLOW_SHARED_LOCAL_NOTARY_PROFILE'
require_text scripts/notarize.sh 'gamemaster-notary'
require_text scripts/notarize.sh 'notarytool submit'
require_text scripts/notarize.sh 'stapler staple'
require_text scripts/notarize.sh 'hdiutil attach -readonly -nobrowse'
require_text scripts/notarize.sh 'spctl --assess --type execute'
require_text scripts/notarize.sh 'codesign --verify --deep --strict'
require_text scripts/generate-appcast.sh 'SPARKLE_PRIVATE_KEY_FILE'
require_text scripts/generate-appcast.sh '--ed-key-file'
require_text scripts/release.sh 'validate_release_identity'
require_text scripts/release.sh 'generate-sbom.swift'
require_text scripts/release.sh 'release-notes.md'
require_text scripts/release.sh 'checksums.txt'
require_text scripts/verify-release.sh 'verify-sparkle-signature.swift'
require_text scripts/verify-release.sh 'sbom-checksums.txt'
require_text scripts/verify-release.sh 'spctl --assess --type execute'

if /usr/bin/grep -REn -- '(set -x|print.*PRIVATE|echo.*PRIVATE|security dump-keychain)' \
    "$repo_root/scripts/release-common.sh" \
    "$repo_root/scripts/sign.sh" \
    "$repo_root/scripts/notarize.sh" \
    "$repo_root/scripts/generate-appcast.sh" \
    "$repo_root/scripts/release.sh"; then
    print -u2 -- "release scripts may expose secret material"
    exit 1
fi

"$repo_root/scripts/release.sh" --policy-check

fixture="$(mktemp -d "${TMPDIR%/}/maccontainer-release-policy.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
/bin/mkdir -p "$fixture/scripts"
for name in $scripts; do
    /bin/cp "$repo_root/scripts/$name" "$fixture/scripts/$name"
done
/usr/bin/sed -i '' '/notarytool submit/d' "$fixture/scripts/notarize.sh"
if MC_RELEASE_POLICY_ROOT="$fixture" "$fixture/scripts/release.sh" --policy-check; then
    print -u2 -- "release policy accepted a notarization bypass"
    exit 1
fi

/bin/cp "$repo_root/scripts/notarize.sh" "$fixture/scripts/notarize.sh"
/usr/bin/sed -i '' '/--options runtime/d' "$fixture/scripts/sign.sh"
if MC_RELEASE_POLICY_ROOT="$fixture" "$fixture/scripts/release.sh" --policy-check; then
    print -u2 -- "release policy accepted signing without hardened runtime"
    exit 1
fi

print -r -- "Release script policy and mutation tests PASS"
