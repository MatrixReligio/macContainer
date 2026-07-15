#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
ci="$repo_root/.github/workflows/ci.yml"
upstream="$repo_root/.github/workflows/upstream-monitor.yml"
errors=()

for workflow in "$ci" "$upstream"; do
    if [[ ! -f "$workflow" ]]; then
        errors+=("missing workflow: ${workflow#$repo_root/}")
    fi
done

if (( ${#errors} > 0 )); then
    printf '%s\n' "${errors[@]}" | LC_ALL=C sort >&2
    exit 1
fi

for workflow in "$ci" "$upstream"; do
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

if ! /usr/bin/grep -Eq '^[[:space:]]*runs-on:[[:space:]]*macos-26([[:space:]]|$)' "$ci"; then
    errors+=("ci.yml must run tests on macos-26")
fi
if /usr/bin/grep -E '^[[:space:]]*runs-on:' "$ci" | /usr/bin/grep -Evq 'macos-26([[:space:]]|$)'; then
    errors+=("ci.yml contains a non-macos-26 runner")
fi
if ! /usr/bin/grep -Fq 'scripts/check-repository.sh' "$ci"; then
    errors+=("ci.yml must run scripts/check-repository.sh")
fi
arm64_build_count="$(/usr/bin/grep -cF 'ARCHS=arm64' "$ci" || true)"
if [[ "$arm64_build_count" != "4" ]]; then
    errors+=("ci.yml must restrict all four application build/test invocations to arm64")
fi
if ! /usr/bin/grep -Eq '^[[:space:]]*contents:[[:space:]]*read([[:space:]]|$)' "$ci"; then
    errors+=("ci.yml must grant only read access to repository contents")
fi
if ! /usr/bin/grep -Eq '^[[:space:]]*issues:[[:space:]]*write([[:space:]]|$)' "$upstream"; then
    errors+=("upstream-monitor.yml must grant issue write access at job scope")
fi

if (( ${#errors} > 0 )); then
    printf '%s\n' "${errors[@]}" | LC_ALL=C sort -u >&2
    exit 1
fi

print -r -- "Workflow policy PASS: macos-26, least privilege, full action SHAs, no PR secrets"
