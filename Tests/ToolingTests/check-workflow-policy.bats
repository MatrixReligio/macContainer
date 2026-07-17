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
if [[ "$intel_runner_count" != 1 || "$arm_runner_count" != 1 ]]; then
    print -u2 -- "expected one 14 GB Intel build runner and one native Apple Silicon UI runner"
    exit 1
fi

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
