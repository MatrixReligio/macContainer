#!/bin/zsh
set -euo pipefail
source "${0:A:h}/release-common.sh"

[[ $# -eq 1 ]] || die "usage: sign.sh MacContainer.app"
app="${1:A}"
[[ -d "$app" ]] || die "application bundle missing: $app"
require_release_identity

sign_code() {
    local path="$1"
    local identifier="${2:-}"
    local entitlements="${3:-}"
    local arguments=(--force --sign "$DEVELOPER_ID_IDENTITY" --timestamp --options runtime)
    [[ -z "$identifier" ]] || arguments+=(--identifier "$identifier")
    [[ -z "$entitlements" ]] || arguments+=(--entitlements "$entitlements")
    /usr/bin/codesign $arguments "$path"
    verify_team_and_runtime "$path"
    [[ -z "$identifier" ]] || verify_designated_requirement "$path" "$identifier"
}

frameworks="$app/Contents/Frameworks"
sparkle="$frameworks/Sparkle.framework"
[[ -d "$sparkle" ]] || die "Contents/Frameworks/Sparkle.framework is missing"

# Sign individual Mach-O tools and dylibs before their containing Sparkle/SwiftTerm/upstream bundles.
while IFS= read -r binary; do
    /usr/bin/file "$binary" | /usr/bin/grep -q 'Mach-O' || continue
    sign_code "$binary"
done < <(/usr/bin/find "$frameworks" -type f \( -perm -0100 -o -name '*.dylib' \) | /usr/bin/sort)

while IFS= read -r bundle; do
    sign_code "$bundle"
done < <(/usr/bin/find "$frameworks" -depth -type d \( -name '*.xpc' -o -name '*.app' -o -name '*.framework' \) | /usr/bin/sort)

helper="$app/Contents/Library/PrivilegedHelperTools/container.matrixreligio.com.helper"
agent="$app/Contents/Library/LoginItems/container.matrixreligio.com.update-agent"
require_file "$helper"
require_file "$agent"
sign_code "$helper" "$HELPER_BUNDLE_ID" "$REPO_ROOT/App/PrivilegedHelper/PrivilegedHelper.entitlements"
sign_code "$agent" "$AGENT_BUNDLE_ID" "$REPO_ROOT/App/UpdateAgent/UpdateAgent.entitlements"

sign_code "$app" "$APP_BUNDLE_ID" "$REPO_ROOT/App/MacContainer/MacContainer.entitlements"

helper_requirement="anchor apple generic and identifier \"$HELPER_BUNDLE_ID\" and certificate leaf[subject.OU] = \"$TEAM_ID\""
embedded_requirement="$(/usr/libexec/PlistBuddy -c "Print :SMPrivilegedExecutables:$HELPER_BUNDLE_ID" "$app/Contents/Info.plist")"
[[ "$embedded_requirement" == "$helper_requirement" ]] || die "app/helper mutual designated requirement mismatch"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
print -r -- "Signing PASS: nested code, helper, agent, and app use $TEAM_ID hardened runtime"
