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
    'dist/release-notes.md dist/THIRD_PARTY_NOTICES'
)
for text in $required_release_text; do
    /usr/bin/grep -Fq -- "$text" "$release" || { print -u2 -- "release.yml missing: $text"; exit 1; }
done

/usr/bin/grep -Fq -- 'gh run list' "$release" || {
    print -u2 -- "release verification must reuse the successful main CI run"
    exit 1
}
for text in '--workflow ci.yml' '--commit "$GITHUB_SHA"' '.conclusion == "success"' \
    'refs/heads/main' 'actions: read'; do
    /usr/bin/grep -Fq -- "$text" "$release" || {
        print -u2 -- "release CI attestation missing: $text"
        exit 1
    }
done

/usr/bin/ruby -e '
    require "yaml"
    jobs = YAML.load_file(ARGV.fetch(0)).fetch("jobs")
    verify = jobs.fetch("verify")
    release = jobs.fetch("release")
    abort "release preflight must use native macOS" unless verify.fetch("runs-on") == "macos-26"
    abort "secret-bearing release must keep the 14 GB Intel runner" unless
      release.fetch("runs-on") == "macos-26-intel"
    runs = verify.fetch("steps").map { |step| step["run"] }.compact.join("\n")
    forbidden = ["scripts/check-repository.sh", "swift test", "xcodebuild", "rm -rf .build"]
    abort "release preflight repeats main CI work" if forbidden.any? { |text| runs.include?(text) }
' "$release"

intel_runner_count="$(/usr/bin/grep -Ec '^[[:space:]]*runs-on:[[:space:]]*macos-26-intel[[:space:]]*$' \
    "$release" || true)"
if [[ "$intel_runner_count" != 1 ]]; then
    print -u2 -- "only secret-bearing publication should use a 14 GB Intel runner"
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
