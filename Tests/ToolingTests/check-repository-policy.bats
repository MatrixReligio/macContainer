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
    settings-auxiliary-ui-policy.bats
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

/usr/bin/grep -Fq -- 'swiftpm_jobs="${MC_SWIFTPM_JOBS:-2}"' "$gate" || {
    print -u2 -- "repository gate must default SwiftPM builds to two jobs"
    exit 1
}

/usr/bin/grep -Fq -- '--jobs "$swiftpm_jobs"' "$gate" || {
    print -u2 -- "repository gate must apply its SwiftPM job limit"
    exit 1
}

/usr/bin/grep -Fq -- 'skip_package_tests="${MC_SKIP_PACKAGE_TESTS:-0}"' "$gate" || {
    print -u2 -- "repository gate must expose an explicit CI-only package-test split"
    exit 1
}

/usr/bin/grep -Fq -- 'if [[ "$skip_package_tests" != "1" ]]; then' "$gate" || {
    print -u2 -- "repository gate must run package tests unless explicitly split by CI"
    exit 1
}

print -r -- "Repository gate composition policy PASS"
