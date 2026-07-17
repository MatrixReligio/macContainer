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
