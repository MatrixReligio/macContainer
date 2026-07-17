#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
manifest="$repo_root/Config/release-tools.json"
committed_project="$repo_root/MacContainer.xcodeproj"
/bin/mkdir -p "$repo_root/.build"
temporary_root="$(mktemp -d "$repo_root/.build/xcodegen-check.XXXXXX")"
trap 'rm -rf "$temporary_root"' EXIT
# XcodeGen derives the display name and stable object ID of a root-local package
# from the specification directory name. Generate from the canonical checkout
# basename so committed output is independent of an agent/worktree directory.
temporary_repo="$temporary_root/macContainer"

if [[ -x "$repo_root/.tools/bin/xcodegen" ]]; then
    xcodegen="$repo_root/.tools/bin/xcodegen"
else
    xcodegen="$(command -v xcodegen || true)"
fi

if [[ -z "$xcodegen" ]]; then
    print -u2 -- "Generated project check FAIL: XcodeGen is not installed; run scripts/bootstrap-tools.sh"
    exit 1
fi

expected_version="$(/usr/bin/plutil -extract xcodegen.version raw -o - "$manifest")"
actual_version="$($xcodegen --version | /usr/bin/sed -E 's/[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
if [[ "$actual_version" != "$expected_version" ]]; then
    print -u2 -- "Generated project check FAIL: expected XcodeGen $expected_version, found $actual_version"
    exit 1
fi

/bin/mkdir -p "$temporary_repo/Tests"
/usr/bin/ditto "$repo_root/project.yml" "$temporary_repo/project.yml"
/usr/bin/ditto "$repo_root/Package.swift" "$temporary_repo/Package.swift"
/usr/bin/ditto "$repo_root/App" "$temporary_repo/App"
/usr/bin/ditto \
    "$repo_root/Tests/MacContainerIntegrationTests" \
    "$temporary_repo/Tests/MacContainerIntegrationTests"
/usr/bin/ditto \
    "$repo_root/Tests/MacContainerUITests" \
    "$temporary_repo/Tests/MacContainerUITests"

"$xcodegen" generate \
    --quiet \
    --no-env \
    --spec "$temporary_repo/project.yml"

typeset -a generated_files=(
    project.pbxproj
    project.xcworkspace/contents.xcworkspacedata
    xcshareddata/xcschemes/MacContainer.xcscheme
)

for relative_path in "${generated_files[@]}"; do
    if ! /usr/bin/diff -u \
        "$committed_project/$relative_path" \
        "$temporary_repo/MacContainer.xcodeproj/$relative_path"; then
        print -u2 -- "Generated project check FAIL: $relative_path has drifted"
        exit 1
    fi
done

if ! /usr/bin/diff -u \
    "$repo_root/App/MacContainer/Info.plist" \
    "$temporary_repo/App/MacContainer/Info.plist"; then
    print -u2 -- "Generated project check FAIL: generated Info.plist has drifted"
    exit 1
fi

workspace_lock="$committed_project/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
/usr/bin/grep -Eq '^[[:space:]]+ARCHS: arm64$' "$repo_root/project.yml" || {
    print -u2 -- "Generated project check FAIL: project.yml must restrict application products to arm64"
    exit 1
}
/usr/bin/grep -Eq 'ARCHS = arm64;' "$committed_project/project.pbxproj" || {
    print -u2 -- "Generated project check FAIL: generated project is not restricted to arm64"
    exit 1
}
/usr/bin/grep -Eq '"identity" : "sparkle"' "$workspace_lock"
/usr/bin/grep -Eq '"version" : "2.9.4"' "$workspace_lock"
/usr/bin/grep -Eq '"identity" : "swiftterm"' "$workspace_lock"
/usr/bin/grep -Eq '"version" : "1.13.0"' "$workspace_lock"

print -r -- "Generated project check PASS: XcodeGen $actual_version"
