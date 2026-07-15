#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
manifest="$repo_root/Config/release-tools.json"
module_cache="$repo_root/.build/check-repository-module-cache"
swiftpm_home="$repo_root/.build/check-repository-home"
swiftpm_cache="$repo_root/.build/check-repository-swiftpm/cache"
swiftpm_config="$repo_root/.build/check-repository-swiftpm/configuration"
swiftpm_security="$repo_root/.build/check-repository-swiftpm/security"

cd "$repo_root"
/bin/mkdir -p "$module_cache" "$swiftpm_home" "$swiftpm_cache" "$swiftpm_config" "$swiftpm_security"
export CLANG_MODULE_CACHE_PATH="$module_cache"
export SWIFT_MODULECACHE_PATH="$module_cache"

resolve_tool() {
    local name="$1"
    if [[ -x "$repo_root/.tools/bin/$name" ]]; then
        print -r -- "$repo_root/.tools/bin/$name"
        return 0
    fi
    command -v "$name" || return 1
}

require_version() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" != "$expected" ]]; then
        print -u2 -- "$label version mismatch: expected $expected, found $actual"
        exit 1
    fi
}

/usr/bin/plutil -convert json -o /dev/null -- "$manifest"
for script in scripts/*.sh Tests/ToolingTests/*.bats; do
    zsh -n "$script"
done
zsh Tests/ToolingTests/check-no-container-cli.bats
scripts/check-no-container-cli.sh
swift scripts/check-contract-coverage.swift \
    Config/contracts/apple-container-1.1.0-acceptance.json \
    Sources/MCContracts/Resources/apple-container-1.1.0.json
scripts/check-generated-project.sh

swiftformat="$(resolve_tool swiftformat || true)"
swiftlint="$(resolve_tool swiftlint || true)"
if [[ -z "$swiftformat" || -z "$swiftlint" ]]; then
    print -u2 -- "Repository check FAIL: SwiftFormat and SwiftLint are required"
    exit 1
fi

expected_swiftformat="$(/usr/bin/plutil -extract swiftFormat.version raw -o - "$manifest")"
expected_swiftlint="$(/usr/bin/plutil -extract swiftLint.version raw -o - "$manifest")"
require_version "SwiftFormat" "$expected_swiftformat" "$($swiftformat --version)"
require_version "SwiftLint" "$expected_swiftlint" "$($swiftlint version)"

"$swiftformat" App Sources Tests scripts --lint --cache ignore --config .swiftformat
"$swiftlint" lint --strict --no-cache --config .swiftlint.yml
HOME="$swiftpm_home" swift test \
    --cache-path "$swiftpm_cache" \
    --config-path "$swiftpm_config" \
    --security-path "$swiftpm_security" \
    --scratch-path "$repo_root/.build" \
    --disable-sandbox \
    --parallel
git diff --check

if [[ "${MC_REQUIRE_CLEAN_WORKTREE:-0}" == "1" ]] && [[ -n "$(git status --short)" ]]; then
    print -u2 -- "Repository check FAIL: worktree is not clean"
    git status --short >&2
    exit 1
fi

print -r -- "Repository check PASS"
