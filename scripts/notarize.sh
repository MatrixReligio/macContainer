#!/bin/zsh
set -euo pipefail
source "${0:A:h}/release-common.sh"

[[ $# -eq 2 ]] || die "usage: notarize.sh --app MacContainer.app | --dmg MacContainer.dmg"
mode="$1"
artifact="${2:A}"
profile="${MACCONTAINER_NOTARY_PROFILE:-maccontainer-notary}"
if [[ "$profile" != "maccontainer-notary" ]]; then
    [[ "${MC_ALLOW_SHARED_LOCAL_NOTARY_PROFILE:-0}" == "1" && "$profile" == "gamemaster-notary" ]] || \
        die "notary profile must be maccontainer-notary"
fi
notary_arguments=(--keychain-profile "$profile")
if [[ -n "${MACCONTAINER_NOTARY_KEYCHAIN:-}" ]]; then
    require_file "$MACCONTAINER_NOTARY_KEYCHAIN"
    notary_arguments+=(--keychain "$MACCONTAINER_NOTARY_KEYCHAIN")
fi

temporary=""
mountpoint=""
cleanup() {
    if [[ -n "$mountpoint" ]] && /sbin/mount | /usr/bin/grep -Fq -- "on $mountpoint "; then
        /usr/bin/hdiutil detach -quiet "$mountpoint" || /usr/bin/hdiutil detach -force "$mountpoint" >/dev/null
    fi
    [[ -z "$temporary" ]] || /bin/rm -rf "$temporary"
    [[ -z "$mountpoint" ]] || /bin/rm -rf "$mountpoint"
}
trap cleanup EXIT INT TERM

case "$mode" in
    --app)
        [[ -d "$artifact" ]] || die "application bundle missing"
        temporary="$(/usr/bin/mktemp -d "${TMPDIR%/}/maccontainer-app-notary.XXXXXX")"
        archive="$temporary/MacContainer.zip"
        /usr/bin/ditto -c -k --keepParent "$artifact" "$archive"
        /usr/bin/xcrun notarytool submit "$archive" $notary_arguments --wait
        /usr/bin/xcrun stapler staple "$artifact"
        /usr/bin/xcrun stapler validate "$artifact"
        /usr/sbin/spctl --assess --type execute --verbose=2 "$artifact"
        /usr/bin/codesign --verify --deep --strict --verbose=2 "$artifact"
        ;;
    --dmg)
        require_file "$artifact"
        /usr/bin/xcrun notarytool submit "$artifact" $notary_arguments --wait
        /usr/bin/xcrun stapler staple "$artifact"
        /usr/bin/xcrun stapler validate "$artifact"
        mountpoint="$(/usr/bin/mktemp -d "${TMPDIR%/}/maccontainer-dmg-notary.XXXXXX")"
        /usr/bin/hdiutil attach -readonly -nobrowse -quiet -mountpoint "$mountpoint" "$artifact"
        mounted_app="$mountpoint/MacContainer.app"
        /usr/sbin/spctl --assess --type execute --verbose=2 "$mounted_app"
        /usr/bin/codesign --verify --deep --strict --verbose=2 "$mounted_app"
        ;;
    *)
        die "unknown notarization mode: $mode"
        ;;
esac

print -r -- "Notarization PASS: ${artifact:t}"
