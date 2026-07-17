#!/bin/zsh
set -euo pipefail
source "${0:A:h}/release-common.sh"

[[ $# -eq 3 ]] || die "usage: generate-appcast.sh dist version candidate.dmg"
dist="${1:A}"
version="$2"
candidate="${3:A}"
key="${SPARKLE_PRIVATE_KEY_FILE:-}"
tool="${SPARKLE_GENERATE_APPCAST:-$REPO_ROOT/.tools/sparkle/bin/generate_appcast}"
require_private_file_permissions "$key"
[[ -x "$tool" ]] || die "pinned Sparkle generate_appcast tool missing"
require_file "$candidate"
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || die "invalid appcast version"

input="$(/usr/bin/mktemp -d "${TMPDIR%/}/maccontainer-appcast.XXXXXX")"
cleanup() {
    /bin/rm -rf "$input"
}
trap cleanup EXIT INT TERM

start="$(/bin/date +%s)"
/usr/bin/ditto "$candidate" "$input/${candidate:t}"
download_prefix="https://github.com/MatrixReligio/macContainer/releases/download/v$version/"
"$tool" --ed-key-file "$key" --download-url-prefix "$download_prefix" "$input"
generated="$input/appcast.xml"
require_file "$generated"
(( $(/usr/bin/stat -f '%m' "$generated") >= start )) || die "generated appcast is stale"
/usr/bin/xmllint --noout "$generated"
/usr/bin/grep -Fq 'sparkle:edSignature=' "$generated" || die "appcast lacks EdDSA signature"
/bin/mkdir -p "$dist"
/usr/bin/ditto "$generated" "$dist/appcast.xml"
print -r -- "Appcast generation PASS: fresh EdDSA feed for $version"
