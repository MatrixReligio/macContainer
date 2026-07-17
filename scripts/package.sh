#!/bin/zsh
set -euo pipefail
source "${0:A:h}/release-common.sh"

[[ $# -eq 2 ]] || die "usage: package.sh MacContainer.app output.dmg"
app="${1:A}"
output="${2:A}"
[[ -d "$app" ]] || die "application bundle missing: $app"

staging="$(/usr/bin/mktemp -d "${TMPDIR%/}/maccontainer-package.XXXXXX")"
cleanup() {
    /bin/rm -rf "$staging"
}
trap cleanup EXIT INT TERM

/usr/bin/ditto "$app" "$staging/MacContainer.app"
/bin/ln -s /Applications "$staging/Applications"
epoch="${SOURCE_DATE_EPOCH:-0}"
stamp="$(/bin/date -r "$epoch" -u '+%Y%m%d%H%M.%S')"
/usr/bin/find "$staging" -exec /usr/bin/touch -h -t "$stamp" {} +
/bin/mkdir -p "${output:h}"
/bin/rm -f "$output"
/usr/bin/hdiutil create -quiet -ov -fs HFS+ -format UDZO -imagekey zlib-level=9 \
    -volname MacContainer -srcfolder "$staging" "$output"
[[ -s "$output" ]] || die "DMG was not created"
print -r -- "Packaging PASS: ${output:t} contains MacContainer.app and /Applications"
