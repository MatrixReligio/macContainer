#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
output_dir=${MARKETING_SCREENSHOT_OUTPUT_DIR:-"$repository_root/docs/marketing/producthunt/screenshots/en"}
temporary_root=${TMPDIR:-/tmp}/maccontainer-producthunt-$$
derived_data="$temporary_root/DerivedData"
result_bundle="$temporary_root/MarketingScreenshots.xcresult"
attachment_dir="$temporary_root/attachments"
staging_dir="$temporary_root/output"

cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT INT TERM

mkdir -p "$attachment_dir" "$staging_dir"

set -- xcodebuild -quiet \
    -project "$repository_root/MacContainer.xcodeproj" \
    -scheme MacContainer \
    -derivedDataPath "$derived_data" \
    -resultBundlePath "$result_bundle" \
    -only-testing:MacContainerUITests/MarketingScreenshotTests/testCaptureSixEnglishProductHuntScreenshots \
    MARKETING_SCREENSHOT_DIR="$staging_dir"

if [ -n "${MACCONTAINER_CODE_SIGN_IDENTITY:-}" ] || [ -n "${MACCONTAINER_DEVELOPMENT_TEAM:-}" ]; then
    if [ -z "${MACCONTAINER_CODE_SIGN_IDENTITY:-}" ] || [ -z "${MACCONTAINER_DEVELOPMENT_TEAM:-}" ]; then
        echo "Both MACCONTAINER_CODE_SIGN_IDENTITY and MACCONTAINER_DEVELOPMENT_TEAM are required." >&2
        exit 2
    fi
    set -- "$@" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="$MACCONTAINER_CODE_SIGN_IDENTITY" \
        DEVELOPMENT_TEAM="$MACCONTAINER_DEVELOPMENT_TEAM"
fi

set -- "$@" test
(cd "$repository_root" && "$@")

xcrun xcresulttool export attachments \
    --path "$result_bundle" \
    --output-path "$attachment_dir" >/dev/null

manifest="$attachment_dir/manifest.json"
attachment_count=$(plutil -extract 0.attachments raw -o - "$manifest")
index=0
while [ "$index" -lt "$attachment_count" ]; do
    suggested=$(plutil -extract "0.attachments.$index.suggestedHumanReadableName" raw -o - "$manifest")
    exported=$(plutil -extract "0.attachments.$index.exportedFileName" raw -o - "$manifest")
    case "$suggested" in
        0[1-6]-*_0_*.png)
            normalized=${suggested%%_0_*}.png
            cp "$attachment_dir/$exported" "$staging_dir/$normalized"
            ;;
    esac
    index=$((index + 1))
done

expected_files='01-overview.png
02-scenario-templates.png
03-compatible-upgrade.png
04-complete-uninstall.png
05-terminal-safety.png
06-actionable-error.png'

actual_count=$(find "$staging_dir" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')
if [ "$actual_count" -ne 6 ]; then
    echo "Expected exactly six PNG files, found $actual_count." >&2
    exit 3
fi

for filename in $expected_files; do
    image="$staging_dir/$filename"
    if [ ! -f "$image" ]; then
        echo "Missing screenshot: $filename" >&2
        exit 4
    fi
    if ! file "$image" | grep -q 'PNG image data'; then
        echo "Not a valid PNG: $filename" >&2
        exit 5
    fi
    width=$(sips -g pixelWidth "$image" | awk '/pixelWidth/ {print $2}')
    height=$(sips -g pixelHeight "$image" | awk '/pixelHeight/ {print $2}')
    if [ "$width" -lt 1000 ] || [ "$height" -lt 620 ]; then
        echo "Screenshot is too small: $filename (${width}x${height})" >&2
        exit 6
    fi
done

(
    cd "$staging_dir"
    for filename in $expected_files; do
        shasum -a 256 "$filename"
    done > manifest.sha256
)

mkdir -p "$(dirname -- "$output_dir")"
rm -rf "$output_dir"
mkdir -p "$output_dir"
ditto "$staging_dir" "$output_dir"

echo "Generated six English Product Hunt screenshots in $output_dir"
