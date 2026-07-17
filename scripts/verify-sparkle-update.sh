#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
script_path="${0:A}"
host_keychains="${HOME:?}/Library/Keychains"
expectations="$repo_root/Tests/Fixtures/sparkle/seed-expectations.json"
ui_test="$repo_root/Tests/MacContainerUITests/SparkleUpdateUITests.swift"

fail() {
    print -u2 -- "Sparkle update harness FAIL: $*"
    exit 1
}

policy_check() {
    for file in "$expectations" "$ui_test"; do
        [[ -f "$file" ]] || fail "required harness file missing: ${file#$repo_root/}"
    done
    local required=(
        '.artifacts/sparkle-test/' 'CFFIXED_USER_HOME' '127.0.0.1' 'trap cleanup EXIT INT TERM'
        'hdiutil attach -readonly -nobrowse' 'spctl --assess --type execute'
        'SPARKLE_PRIVATE_KEY_FILE' '--ed-key-file' 'SparkleUpdateUITests'
        'preferenceMarkerKey' 'lsregister -u' 'cleanup empty'
    )
    for text in $required; do
        /usr/bin/grep -Fq -- "$text" "$script_path" || fail "missing policy token: $text"
    done
    local applications_path='/'"Applications"
    local kill_all='kill'"all"
    local process_kill='p'"kill"
    local forbidden="(^|[^[:alnum:]_])${applications_path}(/|[^[:alnum:]_]|$)|${kill_all}|${process_kill}"
    if /usr/bin/grep -Eq "$forbidden" "$script_path"; then
        fail "harness may affect an installed app or unrelated process"
    fi
    /usr/bin/plutil -convert json -o /dev/null "$expectations"
    print -r -- "Sparkle update harness policy PASS: isolated home, loopback feed, exact process cleanup"
}

if [[ "${1:-}" == "--policy-check" ]]; then
    [[ $# -eq 1 ]] || fail "--policy-check takes no additional arguments"
    policy_check
    exit 0
fi

[[ $# -eq 4 && "$1" == "--seed" && "$3" == "--candidate" ]] || \
    fail "usage: verify-sparkle-update.sh --seed seed.dmg --candidate candidate.dmg"
seed="${2:A}"
candidate="${4:A}"
[[ -f "$seed" && -f "$candidate" ]] || fail "seed and candidate DMGs are required"
policy_check >/dev/null

key="${SPARKLE_PRIVATE_KEY_FILE:-}"
generator="${SPARKLE_GENERATE_APPCAST:-$repo_root/.tools/sparkle/bin/generate_appcast}"
gatekeeper_mode="${MC_SPARKLE_GATEKEEPER_MODE:-require}"
[[ -f "$key" && -x "$generator" ]] || fail "private key file and pinned Sparkle generator are required"
[[ "$gatekeeper_mode" == "require" || "$gatekeeper_mode" == "development" ]] || fail "invalid Gatekeeper mode"
(( (8#$(/usr/bin/stat -f '%Lp' "$key") & 8#077) == 0 )) || fail "private key permissions are too broad"

run_uuid="${RUN_UUID:-$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')}"
root="$repo_root/.artifacts/sparkle-test/$run_uuid"
home="$root/home"
server="$root/server"
logs="$root/logs"
tmp="$root/tmp"
apps="$root/apps"
result_bundle="$root/SparkleUpdate.xcresult"
server_pid=""
app_pid=""
registered_app=""
mounts=()

cleanup() {
    local owned_pids=()
    [[ -z "$app_pid" ]] || /bin/kill "$app_pid" >/dev/null 2>&1 || true
    [[ -z "$server_pid" ]] || /bin/kill "$server_pid" >/dev/null 2>&1 || true
    for pid in $(/usr/bin/pgrep -f "$root" 2>/dev/null || true); do
        if [[ "$pid" != "$$" ]]; then
            owned_pids+=("$pid")
            /bin/kill "$pid" >/dev/null 2>&1 || true
        fi
    done
    for _ in {1..20}; do
        local running=0
        for pid in $owned_pids; do
            /bin/kill -0 "$pid" >/dev/null 2>&1 && running=1
        done
        (( running == 0 )) && break
        /bin/sleep 0.1
    done
    for pid in $owned_pids; do
        /bin/kill -9 "$pid" >/dev/null 2>&1 || true
    done
    [[ -z "$registered_app" ]] || \
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u \
        "$registered_app" >/dev/null 2>&1 || true
    for mountpoint in $mounts; do
        /usr/bin/hdiutil detach -quiet "$mountpoint" >/dev/null 2>&1 || \
            /usr/bin/hdiutil detach -force "$mountpoint" >/dev/null 2>&1 || true
    done
    /bin/rm -rf "$root"
}
trap cleanup EXIT INT TERM

/bin/mkdir -p "$home/Library/Caches" "$home/Library/Preferences" "$server" "$logs" "$tmp" "$apps"
[[ -d "$host_keychains" ]] || fail "host keychain directory is required to sign the UI test runner"
/bin/ln -s "$host_keychains" "$home/Library/Keychains"

copy_app_from_dmg() {
    local dmg="$1"
    local destination="$2"
    local mountpoint="$root/mount-$((${#mounts} + 1))"
    /bin/mkdir -p "$mountpoint"
    mounts+=("$mountpoint")
    /usr/bin/hdiutil attach -readonly -nobrowse -quiet -mountpoint "$mountpoint" "$dmg"
    [[ -d "$mountpoint/MacContainer.app" ]] || fail "DMG does not contain MacContainer.app"
    /usr/bin/ditto "$mountpoint/MacContainer.app" "$destination"
    /usr/bin/hdiutil detach -quiet "$mountpoint"
    mounts=("${(@)mounts:#$mountpoint}")
    /bin/rmdir "$mountpoint"
}

seed_app="$apps/MacContainer Seed.app"
candidate_app="$apps/MacContainer Candidate.app"
copy_app_from_dmg "$seed" "$seed_app"
copy_app_from_dmg "$candidate" "$candidate_app"

expected_bundle="$(/usr/bin/plutil -extract bundleIdentifier raw -o - "$expectations")"
expected_team="$(/usr/bin/plutil -extract teamIdentifier raw -o - "$expectations")"
expected_key="$(/usr/bin/plutil -extract publicEDKey raw -o - "$expectations")"
seed_version="$(/usr/bin/plutil -extract seed.version raw -o - "$expectations")"
seed_build="$(/usr/bin/plutil -extract seed.build raw -o - "$expectations")"
candidate_version="$(/usr/bin/plutil -extract candidate.version raw -o - "$expectations")"
candidate_build="$(/usr/bin/plutil -extract candidate.build raw -o - "$expectations")"
marker_key="$(/usr/bin/plutil -extract preferenceMarkerKey raw -o - "$expectations")"

verify_app() {
    local app="$1"
    local version="$2"
    local build="$3"
    local info="$app/Contents/Info.plist"
    [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$info")" == "$expected_bundle" ]] || \
        fail "unexpected bundle identifier in ${app:t}"
    [[ "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$info")" == "$version" ]] || \
        fail "unexpected version in ${app:t}; expected $version"
    [[ "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$info")" == "$build" ]] || \
        fail "unexpected build in ${app:t}; expected $build"
    [[ "$(/usr/bin/plutil -extract SUPublicEDKey raw -o - "$info")" == "$expected_key" ]] || \
        fail "unexpected Sparkle public key in ${app:t}"
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
    details="$(/usr/bin/codesign -d --verbose=4 "$app" 2>&1)"
    [[ "$details" == *"TeamIdentifier=$expected_team"* ]] || fail "unexpected signing team in ${app:t}"
    if [[ "$gatekeeper_mode" == "require" ]]; then
        /usr/sbin/spctl --assess --type execute --verbose=2 "$app"
    else
        [[ "$details" == *"Authority=Apple Development:"* ]] || fail "development rehearsal requires Apple Development signing"
    fi
}

verify_app "$seed_app" "$seed_version" "$seed_build"
verify_app "$candidate_app" "$candidate_version" "$candidate_build"
/usr/bin/ditto "$candidate" "$server/${candidate:t}"
port="$(ruby -rsocket -e 'server = TCPServer.new("127.0.0.1", 0); puts server.addr[1]; server.close')"
feed_url="http://127.0.0.1:$port/appcast.xml"
HOME="$home" CFFIXED_USER_HOME="$home" "$generator" --ed-key-file "$key" \
    --download-url-prefix "http://127.0.0.1:$port/" "$server" > "$logs/generate-appcast.log"
[[ -f "$server/appcast.xml" ]] || fail "local appcast was not generated"

(cd "$server" && ruby -run -e httpd . -b 127.0.0.1 -p "$port" > "$logs/http.log" 2>&1) &
server_pid=$!
for _ in {1..40}; do
    /usr/bin/curl --fail --silent "$feed_url" >/dev/null 2>&1 && break
    /bin/sleep 0.1
done
/usr/bin/curl --fail --silent "$feed_url" >/dev/null || fail "loopback update server did not start"

registered_app="$seed_app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f \
    "$registered_app" >/dev/null
HOME="$home" CFFIXED_USER_HOME="$home" /usr/bin/defaults write "$expected_bundle" "$marker_key" "$run_uuid"

identity="${MC_UI_TEST_CODE_SIGN_IDENTITY:-}"
team="${MC_UI_TEST_DEVELOPMENT_TEAM:-}"
[[ -n "$identity" && -n "$team" ]] || fail "UI test signing identity and development team are required"
if ! SPARKLE_TEST_SEED_APP="$seed_app" SPARKLE_TEST_FEED_URL="$feed_url" SPARKLE_TEST_ROOT="$root" \
    SPARKLE_TEST_HOME="$home" SPARKLE_TEST_EXPECTED_VERSION="$candidate_version" \
    HOME="$home" CFFIXED_USER_HOME="$home" TMPDIR="$tmp" \
    xcodebuild -quiet -project "$repo_root/MacContainer.xcodeproj" -scheme MacContainer \
        -derivedDataPath "$root/DerivedData" \
        -only-testing:MacContainerUITests/SparkleUpdateUITests \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$team" build-for-testing \
        > "$logs/xcodebuild.log" 2>&1; then
    /usr/bin/tail -200 "$logs/xcodebuild.log" >&2
    fail "UI test build failed"
fi
if ! SPARKLE_TEST_SEED_APP="$seed_app" SPARKLE_TEST_FEED_URL="$feed_url" SPARKLE_TEST_ROOT="$root" \
    SPARKLE_TEST_HOME="$home" SPARKLE_TEST_EXPECTED_VERSION="$candidate_version" \
    HOME="$home" CFFIXED_USER_HOME="$home" TMPDIR="$tmp" \
    xcodebuild -quiet -project "$repo_root/MacContainer.xcodeproj" -scheme MacContainer \
        -derivedDataPath "$root/DerivedData" -resultBundlePath "$result_bundle" \
        -only-testing:MacContainerUITests/SparkleUpdateUITests test-without-building \
        >> "$logs/xcodebuild.log" 2>&1; then
    /usr/bin/tail -200 "$logs/xcodebuild.log" >&2
    if [[ -d "$result_bundle" ]]; then
        print -u2 -- "Sparkle UI test result summary:"
        xcrun xcresulttool get test-results summary --path "$result_bundle" >&2 || true
        print -u2 -- "Sparkle UI test failure details:"
        xcrun xcresulttool get test-results tests --path "$result_bundle" >&2 || true
    fi
    fail "UI update test failed"
fi

[[ "$(HOME="$home" CFFIXED_USER_HOME="$home" /usr/bin/defaults read "$expected_bundle" "$marker_key")" == "$run_uuid" ]] || \
    fail "preference marker was not preserved"
verify_app "$seed_app" "$candidate_version" "$candidate_build"

if [[ "$gatekeeper_mode" == "require" ]]; then
    summary="Sparkle update PASS: $seed_version (seed) -> $candidate_version (candidate), cleanup empty"
else
    summary="Sparkle development rehearsal PASS: $seed_version -> $candidate_version, Gatekeeper deferred, cleanup empty"
fi
cleanup
trap - EXIT INT TERM
[[ ! -e "$root" ]] || fail "isolated test root remains"
print -r -- "$summary"
