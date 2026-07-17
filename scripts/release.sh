#!/bin/zsh
set -euo pipefail
source "${0:A:h}/release-common.sh"

policy_check() {
    local root="${MC_RELEASE_POLICY_ROOT:-$REPO_ROOT}"
    local required=(release-common.sh sign.sh package.sh notarize.sh generate-appcast.sh release.sh verify-release.sh verify-sparkle-signature.swift)
    for name in $required; do
        [[ -f "$root/scripts/$name" ]] || die "policy file missing: scripts/$name"
    done
    local checks=(
        'sign.sh|--options runtime'
        'sign.sh|verify_designated_requirement'
        'notarize.sh|notarytool submit'
        'notarize.sh|stapler staple'
        'notarize.sh|spctl --assess --type execute'
        'generate-appcast.sh|--ed-key-file'
        'release.sh|generate-sbom.swift'
        'verify-release.sh|verify-sparkle-signature.swift'
        'verify-release.sh|codesign --verify --deep --strict'
    )
    for check in $checks; do
        local file="${check%%|*}"
        local text="${check#*|}"
        /usr/bin/grep -Fq -- "$text" "$root/scripts/$file" || die "release policy missing $file: $text"
    done
    local private_word='PRIVATE'
    local trace_pattern='set '"-x"
    local keychain_dump_pattern='security dump-'"keychain"
    local unsafe_pattern="(${trace_pattern}|print.*${private_word}|echo.*${private_word}|${keychain_dump_pattern})"
    local release_paths=()
    for name in $required; do
        release_paths+=("$root/scripts/$name")
    done
    if /usr/bin/grep -Eq -- "$unsafe_pattern" $release_paths; then
        die "release policy found possible secret output"
    fi
    print -r -- "Release policy PASS: signing, notarization, appcast, SBOM, verification, and cleanup required"
}

if [[ "${1:-}" == "--policy-check" ]]; then
    [[ $# -eq 1 ]] || die "--policy-check takes no additional arguments"
    policy_check
    exit 0
fi

[[ $# -eq 2 ]] || die "usage: release.sh --release vMAJOR.MINOR.PATCH | --local-rehearsal MAJOR.MINOR.PATCH-seed"
mode="$1"
label="$2"
case "$mode" in
    --release)
        tag="$label"
        version="${tag#v}"
        ;;
    --local-rehearsal)
        [[ "$label" =~ '^[0-9]+\.[0-9]+\.[0-9]+-seed$' ]] || die "invalid rehearsal label"
        version="${label%-seed}"
        tag="v$version"
        ;;
    *) die "unknown release mode" ;;
esac

cd "$REPO_ROOT"
require_clean_tracked_worktree
validate_release_identity "$version" "$tag"
require_release_identity
policy_check >/dev/null

build="$(project_setting CURRENT_PROJECT_VERSION)"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git show -s --format=%ct HEAD)}"
artifacts="$REPO_ROOT/.artifacts/release"
archive="$artifacts/MacContainer.xcarchive"
dist="$REPO_ROOT/dist"
/bin/rm -rf "$artifacts" "$dist"
/bin/mkdir -p "$artifacts" "$dist"

xcodebuild -quiet -project MacContainer.xcodeproj -scheme MacContainer -configuration Release \
    -archivePath "$archive" DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID_IDENTITY" archive
app="$archive/Products/Applications/MacContainer.app"
"$SCRIPT_DIR/sign.sh" "$app"
"$SCRIPT_DIR/notarize.sh" --app "$app"
dmg="$dist/MacContainer-$label.dmg"
"$SCRIPT_DIR/package.sh" "$app" "$dmg"
"$SCRIPT_DIR/notarize.sh" --dmg "$dmg"

MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" \
    SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" swift scripts/generate-sbom.swift
/usr/bin/ditto CHANGELOG.md "$dist/release-notes.md"
/usr/bin/ditto THIRD_PARTY_NOTICES "$dist/THIRD_PARTY_NOTICES"
"$SCRIPT_DIR/generate-appcast.sh" "$dist" "$version" "$dmg"

checksum_files=("$dmg" "$dist/appcast.xml" "$dist/MacContainer.cdx.json" "$dist/MacContainer.spdx.json" \
    "$dist/release-notes.md" "$dist/THIRD_PARTY_NOTICES")
/usr/bin/shasum -a 256 $checksum_files | /usr/bin/sed "s#$REPO_ROOT/##" > "$dist/checksums.txt"
"$SCRIPT_DIR/verify-release.sh" "$dist" "$version"
print -r -- "Release PASS: MacContainer $version signed, notarized, packaged, and independently verified"
