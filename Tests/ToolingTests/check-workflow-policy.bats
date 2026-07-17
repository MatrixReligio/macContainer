#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
fixture="$(mktemp -d "${TMPDIR%/}/maccontainer-workflow-policy.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/scripts" "$fixture/.github/workflows"
cp "$repo_root/scripts/check-workflow-policy.sh" "$fixture/scripts/"
cp "$repo_root/.github/workflows/ci.yml" "$fixture/.github/workflows/"
cp "$repo_root/.github/workflows/upstream-monitor.yml" "$fixture/.github/workflows/"
cp "$repo_root/.github/workflows/verify-compatibility-pr.yml" "$fixture/.github/workflows/"
cp "$repo_root/.github/workflows/release.yml" "$fixture/.github/workflows/"
cp "$repo_root/.github/workflows/release-verify.yml" "$fixture/.github/workflows/"

approved_upload_artifact='actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1'
if ! /usr/bin/grep -Fq "$approved_upload_artifact" "$fixture/.github/workflows/ci.yml"; then
    print -u2 -- "expected the reviewed Node 24 upload-artifact release"
    exit 1
fi

if ! /usr/bin/grep -Fq -- 'swift test --jobs 1 --enable-code-coverage --parallel' \
    "$fixture/.github/workflows/ci.yml"; then
    print -u2 -- "expected coverage compilation to respect the macOS runner resource limit"
    exit 1
fi

if ! /usr/bin/grep -Fq -- \
    'MC_REQUIRE_CLEAN_WORKTREE=1 MC_SWIFTPM_JOBS=1 scripts/check-repository.sh' \
    "$fixture/.github/workflows/ci.yml"; then
    print -u2 -- "expected the repository gate to use one build job on hosted macOS"
    exit 1
fi

gate_line="$(/usr/bin/grep -nF 'scripts/check-repository.sh' \
    "$fixture/.github/workflows/ci.yml" | /usr/bin/head -1 | /usr/bin/cut -d: -f1)"
metal_line="$(/usr/bin/grep -nF 'xcodebuild -downloadComponent MetalToolchain' \
    "$fixture/.github/workflows/ci.yml" | /usr/bin/head -1 | /usr/bin/cut -d: -f1)"
if [[ -z "$gate_line" || -z "$metal_line" ]] || (( gate_line >= metal_line )); then
    print -u2 -- "expected SwiftPM verification before the disk-heavy Metal component"
    exit 1
fi

intel_runner_count="$(/usr/bin/grep -Ec '^[[:space:]]*runs-on:[[:space:]]*macos-26-intel[[:space:]]*$' \
    "$fixture/.github/workflows/ci.yml" || true)"
arm_runner_count="$(/usr/bin/grep -Ec '^[[:space:]]*runs-on:[[:space:]]*macos-26[[:space:]]*$' \
    "$fixture/.github/workflows/ci.yml" || true)"
linux_runner_count="$(/usr/bin/grep -Ec '^[[:space:]]*runs-on:[[:space:]]*ubuntu-24.04[[:space:]]*$' \
    "$fixture/.github/workflows/ci.yml" || true)"
if [[ "$intel_runner_count" != 3 || "$arm_runner_count" != 1 || "$linux_runner_count" != 1 ]]; then
    print -u2 -- "expected three Intel gates, one Apple Silicon matrix, and one lightweight aggregator"
    exit 1
fi

/usr/bin/ruby -e '
    require "yaml"
    jobs = YAML.load_file(ARGV.fetch(0)).fetch("jobs")
    %w[verify coverage app-build ui-shards ui-tests].each { |name| jobs.fetch(name) }

    shards = jobs.fetch("ui-shards")
    abort "UI shards must start independently" if shards.key?("needs")
    abort "UI shards need a measured 45 minute budget" unless shards.fetch("timeout-minutes") >= 45
    include_rows = shards.fetch("strategy").fetch("matrix").fetch("include")
    abort "UI shards must split accessibility and functional coverage" unless
      include_rows.map { |row| row.fetch("id") } == %w[accessibility functional]
    selections = include_rows.map { |row| row.fetch("test-selection") }
    abort "UI shard selectors are incomplete" unless
      selections.any? { |value| value.include?("-only-testing:MacContainerUITests/AccessibilityAuditTests") } &&
      selections.any? { |value| value.include?("-skip-testing:MacContainerUITests/AccessibilityAuditTests") }
    shard_runs = shards.fetch("steps").map { |step| step["run"] }.compact.join("\n")
    abort "UI tests need realistic per-test allowances" unless
      shard_runs.include?("-default-test-execution-time-allowance 180") &&
      shard_runs.include?("-maximum-test-execution-time-allowance 300")

    aggregate = jobs.fetch("ui-tests")
    needs = aggregate.fetch("needs")
    abort "UI result must wait for every parallel gate and shard" unless
      needs == %w[verify coverage app-build ui-shards]
    abort "UI result must always evaluate dependencies" unless aggregate.fetch("if") == "always()"
    abort "UI result must use the lightweight pinned Linux image" unless
      aggregate.fetch("runs-on") == "ubuntu-24.04"
    abort "UI result should finish quickly" unless aggregate.fetch("timeout-minutes") <= 5
' "$fixture/.github/workflows/ci.yml"

"$fixture/scripts/check-workflow-policy.sh"

printf '\nenv:\n  UNSAFE: ${{ secrets.TEST_ONLY }}\n' >> "$fixture/.github/workflows/ci.yml"
if "$fixture/scripts/check-workflow-policy.sh"; then
    print -u2 -- "expected a top-level secret exposed to pull requests to fail"
    exit 1
fi

cp "$repo_root/.github/workflows/ci.yml" "$fixture/.github/workflows/ci.yml"
/usr/bin/sed -i '' 's/actions\/checkout@[0-9a-f]*/actions\/checkout@v7/' "$fixture/.github/workflows/ci.yml"
if "$fixture/scripts/check-workflow-policy.sh"; then
    print -u2 -- "expected a floating action tag to fail"
    exit 1
fi

cp "$repo_root/.github/workflows/ci.yml" "$fixture/.github/workflows/ci.yml"
/usr/bin/sed -i '' \
    's/actions\/upload-artifact@[0-9a-f]*/actions\/upload-artifact@330a01c490aca151604b8cf639adc76d48f6c5d4/' \
    "$fixture/.github/workflows/ci.yml"
if "$fixture/scripts/check-workflow-policy.sh"; then
    print -u2 -- "expected a stale Node 20 upload-artifact release to fail"
    exit 1
fi

cp "$repo_root/.github/workflows/ci.yml" "$fixture/.github/workflows/ci.yml"
printf '%s\n' \
    '  unsafe-signing:' \
    '    needs: verify' \
    '    runs-on: macos-26' \
    '    steps:' \
    '      - run: test -n "$CERTIFICATE"' \
    '        env:' \
    '          CERTIFICATE: ${{ secrets.TEST_ONLY }}' \
    >> "$fixture/.github/workflows/ci.yml"
if "$fixture/scripts/check-workflow-policy.sh"; then
    print -u2 -- "expected an unguarded secret-bearing job to fail"
    exit 1
fi

print -r -- "Workflow policy scanner tests PASS"
