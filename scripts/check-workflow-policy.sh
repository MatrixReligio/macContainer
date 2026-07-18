#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
ci="$repo_root/.github/workflows/ci.yml"
upstream="$repo_root/.github/workflows/upstream-monitor.yml"
verification="$repo_root/.github/workflows/verify-compatibility-pr.yml"
release="$repo_root/.github/workflows/release.yml"
release_verification="$repo_root/.github/workflows/release-verify.yml"
approved_upload_artifact_sha="043fb46d1a93c77aae656e7c1c64a875d1fc6a0a"
errors=()

workflows=("$ci" "$upstream" "$verification" "$release" "$release_verification")

for workflow in $workflows; do
    if [[ ! -f "$workflow" ]]; then
        errors+=("missing workflow: ${workflow#$repo_root/}")
    fi
done

if (( ${#errors} > 0 )); then
    printf '%s\n' "${errors[@]}" | LC_ALL=C sort >&2
    exit 1
fi

for workflow in $workflows; do
    relative="${workflow#$repo_root/}"
    if ! /usr/bin/ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' "$workflow"; then
        errors+=("invalid YAML: $relative")
    fi

    while IFS= read -r use; do
        reference="${use##*@}"
        action="${use%%@*}"
        if [[ "$action" == ./* ]]; then
            continue
        fi
        if [[ ! "$reference" =~ '^[0-9a-f]{40}$' ]]; then
            errors+=("unpinned action in $relative: $use")
        fi
        if [[ "$action" == "actions/upload-artifact" && "$reference" != "$approved_upload_artifact_sha" ]]; then
            errors+=("unapproved upload-artifact release in $relative: $use")
        fi
    done < <(/usr/bin/sed -En 's/^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*([^#[:space:]]+).*/\1/p' "$workflow")

    if /usr/bin/grep -Eq '(^|[^[:alnum:]_])(write-all|read-all)([^[:alnum:]_]|$)' "$workflow"; then
        errors+=("broad token permission in $relative")
    fi
    if /usr/bin/grep -Eq 'pull_request_target' "$workflow"; then
        errors+=("pull_request_target is forbidden in $relative")
    fi

    secret_errors="$(/usr/bin/ruby - "$workflow" <<'RUBY'
require "yaml"

document = YAML.load_file(ARGV.fetch(0))
jobs = document.fetch("jobs", {})
top_level = document.reject { |key, _| key == "jobs" }
if top_level.inspect.include?("${{ secrets.")
  puts "top-level secrets are exposed to pull-request jobs"
end
jobs.each do |name, job|
  next unless job.inspect.include?("${{ secrets.")

  guard = job.fetch("if", "").to_s
  needs = Array(job.fetch("needs", nil)).compact
  unless guard.include?("github.event_name != 'pull_request'") && needs.include?("verify")
    puts "secret-bearing job must exclude pull requests and depend on verify: #{name}"
  end
end
RUBY
)"
    if [[ -n "$secret_errors" ]]; then
        errors+=("${(f)secret_errors}")
    fi
done

if ! /usr/bin/grep -Eq '^[[:space:]]*runs-on:[[:space:]]*macos-26[[:space:]]*$' "$ci"; then
    errors+=("ci.yml must build on native Apple Silicon macos-26")
fi
if /usr/bin/grep -E '^[[:space:]]*runs-on:' "$ci" | \
   /usr/bin/grep -Evq 'macos-26[[:space:]]*$'; then
    errors+=("ci.yml contains an unapproved runner")
fi
if ! /usr/bin/grep -Fq 'scripts/check-repository.sh' "$ci"; then
    errors+=("ci.yml must run scripts/check-repository.sh")
fi
arm64_build_count="$(/usr/bin/grep -cF 'ARCHS=arm64' "$ci" || true)"
if [[ "$arm64_build_count" != "1" ]]; then
    errors+=("ci.yml must restrict the application build invocation to arm64")
fi
if ! /usr/bin/grep -Eq '^[[:space:]]*contents:[[:space:]]*read([[:space:]]|$)' "$ci"; then
    errors+=("ci.yml must grant only read access to repository contents")
fi
if ! /usr/bin/grep -Eq '^[[:space:]]*issues:[[:space:]]*write([[:space:]]|$)' "$upstream"; then
    errors+=("upstream-monitor.yml must grant issue write access at job scope")
fi
if /usr/bin/grep -Eq 'contents:[[:space:]]*write|pull_request_target|auto-merge|merge_method' "$upstream"; then
    errors+=("upstream monitor has forbidden compatibility mutation authority")
fi
if /usr/bin/grep -Eq 'Config/compatibility/catalog-v1.json|git[[:space:]]+(add|commit|push)' "$upstream"; then
    errors+=("upstream monitor must not edit compatibility sources")
fi
if ! /usr/bin/grep -Eq '^[[:space:]]*pull-requests:[[:space:]]*read([[:space:]]|$)' "$verification"; then
    errors+=("compatibility verification must have pull-request read access only")
fi
if ! /usr/bin/grep -Fq 'scripts/verify-physical-attestation.swift' "$verification" || \
   ! /usr/bin/grep -Fq 'pulls.listReviews' "$verification"; then
    errors+=("compatibility verification must check signed proof and reviewer approval")
fi

if ! /usr/bin/grep -Eq '^[[:space:]]*contents:[[:space:]]*read([[:space:]]|$)' "$release"; then
    errors+=("release.yml must default to read-only contents")
fi
release_intel_runner_count="$(/usr/bin/grep -Ec '^[[:space:]]*runs-on:[[:space:]]*macos-26-intel[[:space:]]*$' "$release" || true)"
release_native_runner_count="$(/usr/bin/grep -Ec '^[[:space:]]*runs-on:[[:space:]]*macos-26[[:space:]]*$' "$release" || true)"
if [[ "$release_intel_runner_count" != "1" || "$release_native_runner_count" != "1" ]]; then
    errors+=("release.yml must use native macOS for CI attestation and a 14 GB Intel runner for publication")
fi
if ! /usr/bin/grep -Fq 'needs: verify' "$release" || \
   ! /usr/bin/grep -Fq "github.event_name != 'pull_request'" "$release"; then
    errors+=("release secret-bearing job must follow secret-free verify and exclude pull requests")
fi
for required in 'gh run list' '--workflow ci.yml' '--commit "$GITHUB_SHA"' \
    '.conclusion == "success"' 'refs/heads/main' 'actions: read'; do
    if ! /usr/bin/grep -Fq -- "$required" "$release"; then
        errors+=("release.yml missing exact-main CI attestation: $required")
    fi
done
release_preflight_errors="$(/usr/bin/ruby - "$release" <<'RUBY'
require "yaml"

jobs = YAML.load_file(ARGV.fetch(0)).fetch("jobs")
verify = jobs.fetch("verify")
runs = verify.fetch("steps").map { |step| step["run"] }.compact.join("\n")
forbidden = ["scripts/check-repository.sh", "swift test", "xcodebuild", "rm -rf .build"]
puts "release preflight repeats work already passed on main" if forbidden.any? { |text| runs.include?(text) }
RUBY
)"
if [[ -n "$release_preflight_errors" ]]; then
    errors+=("${(f)release_preflight_errors}")
fi
if ! /usr/bin/grep -Eq '^[[:space:]]*contents:[[:space:]]*write([[:space:]]|$)' "$release"; then
    errors+=("release publish job requires scoped contents write access")
fi
for secret in DEVELOPER_ID_CERT_P12 DEVELOPER_ID_CERT_PASSWORD ASC_KEY_P8 ASC_KEY_ID ASC_ISSUER_ID SPARKLE_PRIVATE_KEY; do
    if ! /usr/bin/grep -Fq "secrets.$secret" "$release"; then
        errors+=("release.yml missing repository secret contract: $secret")
    fi
done
for required in '::add-mask::' 'security create-keychain' 'security delete-keychain' \
    'trap cleanup EXIT INT TERM' 'maccontainer-notary' 'scripts/release.sh --release' \
    'scripts/verify-release.sh' 'gh release create' 'Sparkle-2.9.4.tar.xz' \
    'ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9' \
    'dist/release-notes.md dist/THIRD_PARTY_NOTICES'; do
    if ! /usr/bin/grep -Fq -- "$required" "$release"; then
        errors+=("release.yml missing guarded release step: $required")
    fi
done
if /usr/bin/grep -Eq 'pull_request_target|brew[[:space:]]+install|login\.keychain|GameMaster|GAMEMASTER' \
    "$release" "$release_verification"; then
    errors+=("release workflows contain forbidden trigger, mutable install, persistent keychain, or foreign key material")
fi
verify_line="$(/usr/bin/grep -nF 'scripts/verify-release.sh' "$release" | /usr/bin/tail -1 | /usr/bin/cut -d: -f1)"
publish_line="$(/usr/bin/grep -nF 'gh release create' "$release" | /usr/bin/tail -1 | /usr/bin/cut -d: -f1)"
if [[ -z "$verify_line" || -z "$publish_line" ]] || (( verify_line >= publish_line )); then
    errors+=("release publication must occur only after independent verification")
fi
if /usr/bin/grep -Fq '${{ secrets.' "$release_verification" || \
   /usr/bin/grep -Eq 'contents:[[:space:]]*write' "$release_verification"; then
    errors+=("public release verification must be secret-free and read-only")
fi
for required in 'gh release download' 'isDraft' 'scripts/verify-release.sh'; do
    if ! /usr/bin/grep -Fq -- "$required" "$release_verification"; then
        errors+=("release-verify.yml missing public verification step: $required")
    fi
done

if (( ${#errors} > 0 )); then
    printf '%s\n' "${errors[@]}" | LC_ALL=C sort -u >&2
    exit 1
fi

print -r -- "Workflow policy PASS: three native macOS 26 gates, no daily UI, least privilege, reviewed action SHAs"
