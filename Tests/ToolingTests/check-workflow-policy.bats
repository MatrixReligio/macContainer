#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
fixture="$(mktemp -d "${TMPDIR%/}/maccontainer-workflow-policy.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/scripts" "$fixture/.github/workflows"
cp "$repo_root/scripts/check-workflow-policy.sh" "$fixture/scripts/"
cp "$repo_root/.github/workflows/ci.yml" "$fixture/.github/workflows/"
cp "$repo_root/.github/workflows/upstream-monitor.yml" "$fixture/.github/workflows/"

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
