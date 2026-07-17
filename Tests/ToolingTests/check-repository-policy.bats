#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
gate="$repo_root/scripts/check-repository.sh"

required_tooling_tests=(
    check-app-icon.bats
    check-no-container-cli.bats
    check-open-source-baseline.bats
    check-repository-policy.bats
    check-workflow-policy.bats
    document-parity.bats
    license-policy.bats
    localization-policy.bats
    physical-runner-policy.bats
    physical-summary.bats
    release-script-policy.bats
    release-workflow-policy.bats
    upstream-monitor-policy.bats
)

for test_name in $required_tooling_tests; do
    /usr/bin/grep -Fq -- "zsh Tests/ToolingTests/$test_name" "$gate" || {
        print -u2 -- "repository gate omits Tests/ToolingTests/$test_name"
        exit 1
    }
done

/usr/bin/grep -Fq -- 'scripts/verify-sparkle-update.sh --policy-check' "$gate" || {
    print -u2 -- "repository gate omits the Sparkle update harness policy"
    exit 1
}

print -r -- "Repository gate composition policy PASS"
