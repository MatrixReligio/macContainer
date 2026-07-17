#!/bin/zsh
set -euo pipefail
source "${0:A:h}/release-common.sh"

[[ $# -eq 2 ]] || die "usage: verify-release.sh dist version"
dist="${1:A}"
version="$2"
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || die "invalid verification version"
require_file "$dist/checksums.txt"
require_file "$dist/sbom-checksums.txt"
require_file "$dist/appcast.xml"
require_file "$dist/release-notes.md"
[[ -s "$dist/release-notes.md" ]] || die "release notes are empty"

cd "$REPO_ROOT"
/usr/bin/shasum -a 256 -c "$dist/checksums.txt"
/usr/bin/shasum -a 256 -c "$dist/sbom-checksums.txt"
/usr/bin/xmllint --noout "$dist/appcast.xml"
/usr/bin/plutil -convert json -o /dev/null "$dist/MacContainer.cdx.json"
/usr/bin/plutil -convert json -o /dev/null "$dist/MacContainer.spdx.json"
/usr/bin/grep -Fq "\"version\" : \"$version\"" "$dist/MacContainer.cdx.json" || die "SBOM version mismatch"

dmg_name="$(/usr/bin/xmllint --xpath 'string(//*[local-name()="enclosure"]/@url)' "$dist/appcast.xml")"
dmg_name="${dmg_name:t}"
dmg="$dist/$dmg_name"
require_file "$dmg"
signature="$(/usr/bin/xmllint --xpath 'string(//*[local-name()="enclosure"]/@*[local-name()="edSignature"])' "$dist/appcast.xml")"
[[ -n "$signature" ]] || die "appcast signature missing"

mountpoint="$(/usr/bin/mktemp -d "${TMPDIR%/}/maccontainer-release-verify.XXXXXX")"
cleanup() {
    if /sbin/mount | /usr/bin/grep -Fq -- "on $mountpoint "; then
        /usr/bin/hdiutil detach -quiet "$mountpoint" || /usr/bin/hdiutil detach -force "$mountpoint" >/dev/null
    fi
    /bin/rm -rf "$mountpoint"
}
trap cleanup EXIT INT TERM

/usr/bin/xcrun stapler validate "$dmg"
/usr/bin/hdiutil attach -readonly -nobrowse -quiet -mountpoint "$mountpoint" "$dmg"
app="$mountpoint/MacContainer.app"
/usr/sbin/spctl --assess --type execute --verbose=2 "$app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
verify_team_and_runtime "$app"
verify_designated_requirement "$app" "$APP_BUNDLE_ID"

info="$app/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")" == "$version" ]] || die "app version mismatch"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$info")" == \
    'https://github.com/matrixreligio/macContainer/releases/latest/download/appcast.xml' ]] || die "feed URL mismatch"
public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$info")"
swift "$SCRIPT_DIR/verify-sparkle-signature.swift" "$public_key" "$signature" "$dmg"
print -r -- "Release verification PASS: signatures, notarization, Gatekeeper, appcast, checksums, and SBOM"
