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

if ! /usr/bin/grep -Fq -- 'swift test --jobs 1 --enable-code-coverage --parallel' \
    "$fixture/.github/workflows/ci.yml"; then
    print -u2 -- "expected coverage compilation to respect the macOS runner resource limit"
    exit 1
fi

if ! /usr/bin/grep -Fq -- \
    'MC_REQUIRE_CLEAN_WORKTREE=1 MC_SKIP_PACKAGE_TESTS=1 scripts/check-repository.sh' \
    "$fixture/.github/workflows/ci.yml"; then
    print -u2 -- "expected lint and policy CI to leave package tests to Build & Test"
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
if [[ "$intel_runner_count" != 0 || "$arm_runner_count" != 3 ]]; then
    print -u2 -- "expected exactly three native Apple Silicon macOS 26 gates"
    exit 1
fi

/usr/bin/ruby -e '
    require "yaml"
    path = ARGV.fetch(0)
    jobs = YAML.load_file(path).fetch("jobs")
    abort "daily CI must contain only verification, coverage, and app build" unless
      jobs.keys == %w[verify coverage app-build]
    expected_names = {
      "verify" => "Lint & Policy",
      "coverage" => "Build & Test",
      "app-build" => "Build App Target"
    }
    abort "daily CI names must mirror macGameMaster responsibilities" unless
      expected_names.all? { |id, name| jobs.fetch(id).fetch("name") == name }
    text = File.read(path)
    abort "daily CI must not run one-time marketing or UI automation" if
      text.include?("MarketingScreenshotTests") ||
      text.include?("MacContainerUITests") ||
      text.include?("test-without-building")
    app_runs = jobs.fetch("app-build").fetch("steps").map { |step| step["run"] }.compact.join("\n")
    abort "daily CI must compile the Debug app target" unless app_runs.include?("-configuration Debug")
    abort "daily CI must leave Release packaging to the release workflow" if
      app_runs.include?("-configuration Release")
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
    's/actions\/checkout@[0-9a-f]*/actions\/upload-artifact@330a01c490aca151604b8cf639adc76d48f6c5d4/' \
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
