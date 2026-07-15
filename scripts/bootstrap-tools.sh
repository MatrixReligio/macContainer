#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
manifest="$repo_root/Config/release-tools.json"
tools_root="$repo_root/.tools"
download_root="$tools_root/downloads"
bin_root="$tools_root/bin"
share_root="$tools_root/share"

read_manifest() {
    /usr/bin/plutil -extract "$1" raw -o - "$manifest"
}

verify_sha256() {
    local file="$1"
    local expected="$2"
    local actual
    actual="$(/usr/bin/shasum -a 256 "$file" | /usr/bin/awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        print -u2 -- "Checksum mismatch for ${file:t}: expected $expected, got $actual"
        return 1
    fi
}

download_verified() {
    local url="$1"
    local destination="$2"
    local expected_sha="$3"
    local partial="$destination.partial"

    if [[ -f "$destination" ]] && verify_sha256 "$destination" "$expected_sha"; then
        return 0
    fi

    rm -f "$destination" "$partial"
    /usr/bin/curl \
        --fail \
        --location \
        --proto '=https' \
        --show-error \
        --silent \
        --tlsv1.2 \
        --output "$partial" \
        "$url"
    verify_sha256 "$partial" "$expected_sha"
    /bin/mv "$partial" "$destination"
}

if [[ ! -f "$manifest" ]]; then
    print -u2 -- "Missing tool manifest: $manifest"
    exit 1
fi

/usr/bin/plutil -convert json -o /dev/null -- "$manifest"
/bin/mkdir -p "$download_root" "$bin_root" "$share_root"

xcodegen_version="$(read_manifest xcodegen.version)"
xcodegen_archive="$(read_manifest xcodegen.archive)"
xcodegen_sha="$(read_manifest xcodegen.sha256)"
xcodegen_download="$download_root/$xcodegen_archive"
xcodegen_url="https://github.com/yonaskolb/XcodeGen/releases/download/$xcodegen_version/$xcodegen_archive"

sparkle_version="$(read_manifest sparkle.version)"
sparkle_archive="$(read_manifest sparkle.archive)"
sparkle_sha="$(read_manifest sparkle.sha256)"
sparkle_download="$download_root/$sparkle_archive"
sparkle_url="https://github.com/sparkle-project/Sparkle/releases/download/$sparkle_version/$sparkle_archive"

swiftformat_version="$(read_manifest swiftFormat.version)"
swiftformat_archive="$(read_manifest swiftFormat.archive)"
swiftformat_sha="$(read_manifest swiftFormat.sha256)"
swiftformat_download="$download_root/$swiftformat_archive"
swiftformat_url="https://github.com/nicklockwood/SwiftFormat/releases/download/$swiftformat_version/$swiftformat_archive"

swiftlint_version="$(read_manifest swiftLint.version)"
swiftlint_archive="$(read_manifest swiftLint.archive)"
swiftlint_sha="$(read_manifest swiftLint.sha256)"
swiftlint_download="$download_root/$swiftlint_archive"
swiftlint_url="https://github.com/realm/SwiftLint/releases/download/$swiftlint_version/$swiftlint_archive"

download_verified "$xcodegen_url" "$xcodegen_download" "$xcodegen_sha"
download_verified "$sparkle_url" "$sparkle_download" "$sparkle_sha"
download_verified "$swiftformat_url" "$swiftformat_download" "$swiftformat_sha"
download_verified "$swiftlint_url" "$swiftlint_download" "$swiftlint_sha"

xcodegen_root="$tools_root/xcodegen-$xcodegen_version"
sparkle_root="$tools_root/sparkle-$sparkle_version"
swiftformat_root="$tools_root/swiftformat-$swiftformat_version"
swiftlint_root="$tools_root/swiftlint-$swiftlint_version"
/bin/rm -rf "$xcodegen_root" "$sparkle_root" "$swiftformat_root" "$swiftlint_root"
/bin/mkdir -p "$xcodegen_root" "$sparkle_root" "$swiftformat_root" "$swiftlint_root"
/usr/bin/ditto -x -k "$xcodegen_download" "$xcodegen_root"
/usr/bin/tar -xf "$sparkle_download" -C "$sparkle_root"
/usr/bin/ditto -x -k "$swiftformat_download" "$swiftformat_root"
/usr/bin/ditto -x -k "$swiftlint_download" "$swiftlint_root"

xcodegen_binary="$(find "$xcodegen_root" -type f -name xcodegen -perm -111 -print -quit)"
swiftformat_binary="$(find "$swiftformat_root" -type f -name swiftformat -perm -111 -print -quit)"
swiftlint_binary="$(find "$swiftlint_root" -type f -name swiftlint -perm -111 -print -quit)"
xcodegen_share="${xcodegen_binary:h:h}/share/xcodegen"
if [[ -z "$xcodegen_binary" || -z "$swiftformat_binary" || -z "$swiftlint_binary" || \
      ! -d "$xcodegen_share/SettingPresets" ]]; then
    print -u2 -- "A pinned tool archive did not contain its expected executable"
    exit 1
fi

/bin/ln -sfn "$xcodegen_binary" "$bin_root/xcodegen"
/bin/ln -sfn "$xcodegen_share" "$share_root/xcodegen"
/bin/ln -sfn "$swiftformat_binary" "$bin_root/swiftformat"
/bin/ln -sfn "$swiftlint_binary" "$bin_root/swiftlint"

actual_xcodegen="$($bin_root/xcodegen --version | /usr/bin/sed -E 's/[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
actual_swiftformat="$($bin_root/swiftformat --version)"
actual_swiftlint="$($bin_root/swiftlint version)"
[[ "$actual_xcodegen" == "$xcodegen_version" ]]
[[ "$actual_swiftformat" == "$swiftformat_version" ]]
[[ "$actual_swiftlint" == "$swiftlint_version" ]]

print -r -- "Pinned tools ready: XcodeGen $actual_xcodegen, SwiftFormat $actual_swiftformat, SwiftLint $actual_swiftlint"
