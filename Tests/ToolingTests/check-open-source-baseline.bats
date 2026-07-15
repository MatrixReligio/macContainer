#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
fixture="$(mktemp -d "${TMPDIR%/}/maccontainer-open-source.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

policy_documents=(
    ARCHITECTURE.md
    CHANGELOG.md
    CODE_OF_CONDUCT.md
    CODE_STYLE.md
    CONTRIBUTING.md
    DEVELOPMENT.md
    GOVERNANCE.md
    LICENSE
    NOTICE
    PRIVACY.md
    README.md
    RELEASE.md
    SECURITY.md
    SUPPORT.md
    THIRD_PARTY_NOTICES
    docs/en/THREAT_MODEL.md
)
community_templates=(
    .github/ISSUE_TEMPLATE/bug.yml
    .github/ISSUE_TEMPLATE/feature.yml
    .github/pull_request_template.md
)

mkdir -p "$fixture/scripts" "$fixture/docs/en" "$fixture/.github/ISSUE_TEMPLATE"
cp "$repo_root/scripts/check-open-source-baseline.sh" "$fixture/scripts/"
for required_file in "${policy_documents[@]}" "${community_templates[@]}"; do
    cp "$repo_root/$required_file" "$fixture/$required_file"
done

"$fixture/scripts/check-open-source-baseline.sh"

print -r -- '\nWrong security contact: security@example.invalid' >> "$fixture/SUPPORT.md"
if "$fixture/scripts/check-open-source-baseline.sh"; then
    print -u2 -- "expected an unapproved support contact to fail"
    exit 1
fi
cp "$repo_root/SUPPORT.md" "$fixture/SUPPORT.md"

print -r -- '\n[Missing document](does-not-exist.md)' >> "$fixture/README.md"
if "$fixture/scripts/check-open-source-baseline.sh"; then
    print -u2 -- "expected a broken local Markdown link to fail"
    exit 1
fi
cp "$repo_root/README.md" "$fixture/README.md"

/usr/bin/sed -i '' '/2 business days/d' "$fixture/SECURITY.md"
if "$fixture/scripts/check-open-source-baseline.sh"; then
    print -u2 -- "expected an incomplete security response policy to fail"
    exit 1
fi

print -r -- "Open-source baseline scanner tests PASS"
