#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
release="$repo_root/.github/workflows/release.yml"
verification="$repo_root/.github/workflows/release-verify.yml"
scanner="$repo_root/scripts/check-workflow-policy.sh"

for file in "$release" "$verification" "$scanner"; do
    [[ -f "$file" ]] || { print -u2 -- "missing release workflow policy file: ${file#$repo_root/}"; exit 1; }
done

for workflow in "$release" "$verification"; do
    /usr/bin/ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' "$workflow"
    while IFS= read -r use; do
        [[ "$use" == ./* ]] && continue
        [[ "${use##*@}" =~ '^[0-9a-f]{40}$' ]] || { print -u2 -- "mutable action: $use"; exit 1; }
    done < <(/usr/bin/sed -En 's/^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*([^#[:space:]]+).*/\1/p' "$workflow")
done

required_release_text=(
    'needs: verify'
    "github.event_name != 'pull_request'"
    'contents: write'
    'DEVELOPER_ID_CERT_P12'
    'DEVELOPER_ID_CERT_PASSWORD'
    'ASC_KEY_P8'
    'ASC_KEY_ID'
    'ASC_ISSUER_ID'
    'SPARKLE_PRIVATE_KEY'
    'maccontainer-notary'
    'security create-keychain'
    'security delete-keychain'
    'trap cleanup EXIT INT TERM'
    'Sparkle-2.9.4.tar.xz'
    'ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9'
    'scripts/release.sh --release'
    'scripts/verify-release.sh'
    'gh release create'
)
for text in $required_release_text; do
    /usr/bin/grep -Fq -- "$text" "$release" || { print -u2 -- "release.yml missing: $text"; exit 1; }
done

/usr/bin/grep -Fq -- 'MC_SWIFTPM_JOBS=2 scripts/check-repository.sh' "$release" || {
    print -u2 -- "release verification must use two SwiftPM build jobs on the 14 GB runner"
    exit 1
}

gate_line="$(/usr/bin/grep -nF 'scripts/check-repository.sh' "$release" | /usr/bin/head -1 | /usr/bin/cut -d: -f1)"
reclaim_line="$(/usr/bin/grep -nF 'rm -rf .build' "$release" | /usr/bin/head -1 | /usr/bin/cut -d: -f1)"
metal_line="$(/usr/bin/grep -nF 'xcodebuild -downloadComponent MetalToolchain' "$release" | /usr/bin/head -1 | /usr/bin/cut -d: -f1)"
if [[ -z "$gate_line" || -z "$reclaim_line" || -z "$metal_line" ]] || \
   (( gate_line >= reclaim_line || reclaim_line >= metal_line )); then
    print -u2 -- "release verification must reclaim SwiftPM storage before installing Metal"
    exit 1
fi

intel_runner_count="$(/usr/bin/grep -Ec '^[[:space:]]*runs-on:[[:space:]]*macos-26-intel[[:space:]]*$' \
    "$release" || true)"
if [[ "$intel_runner_count" != 2 ]]; then
    print -u2 -- "release verification and publication must use 14 GB Intel runners"
    exit 1
fi

/usr/bin/grep -Fq 'gh release download' "$verification"
/usr/bin/grep -Fq 'scripts/verify-release.sh' "$verification"
/usr/bin/grep -Fq 'isDraft' "$verification"

if /usr/bin/grep -REq -- '(pull_request_target|brew install|login\.keychain|GameMaster|GAMEMASTER)' "$release" "$verification"; then
    print -u2 -- "release workflow contains forbidden secret or mutable-system behavior"
    exit 1
fi

"$scanner"

fixture="$(mktemp -d "${TMPDIR%/}/maccontainer-release-workflow.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
/bin/mkdir -p "$fixture/.github/workflows" "$fixture/scripts"
/bin/cp "$scanner" "$fixture/scripts/check-workflow-policy.sh"
for workflow in ci.yml upstream-monitor.yml verify-compatibility-pr.yml release.yml release-verify.yml; do
    /bin/cp "$repo_root/.github/workflows/$workflow" "$fixture/.github/workflows/$workflow"
done

printf '\npull_request_target:\n' >> "$fixture/.github/workflows/release.yml"
if "$fixture/scripts/check-workflow-policy.sh"; then
    print -u2 -- "workflow policy accepted pull_request_target"
    exit 1
fi

/bin/cp "$release" "$fixture/.github/workflows/release.yml"
/usr/bin/sed -i '' '/security delete-keychain/d' "$fixture/.github/workflows/release.yml"
if "$fixture/scripts/check-workflow-policy.sh"; then
    print -u2 -- "workflow policy accepted persistent release keychain"
    exit 1
fi

/bin/cp "$release" "$fixture/.github/workflows/release.yml"
/usr/bin/sed -i '' '/set -euo pipefail/a\
          brew install unreviewed-tool
' "$fixture/.github/workflows/release.yml"
if "$fixture/scripts/check-workflow-policy.sh"; then
    print -u2 -- "workflow policy accepted Homebrew in a secret-bearing workflow"
    exit 1
fi

print -r -- "Release workflow policy and mutation tests PASS"
