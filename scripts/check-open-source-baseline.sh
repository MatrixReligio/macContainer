#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"

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

failures=()

for required_file in "${policy_documents[@]}" "${community_templates[@]}"; do
    if [[ ! -f "$repo_root/$required_file" ]]; then
        failures+=("Missing required file: $required_file")
    fi
done

if (( ${#failures[@]} > 0 )); then
    for failure in "${(@on)failures}"; do
        print -u2 -r -- "$failure"
    done
    print -u2 -r -- "Open-source baseline FAIL: ${#failures[@]} problem(s)"
    exit 1
fi

if ! /usr/bin/grep -qF 'SPDX-License-Identifier: Apache-2.0' "$repo_root/NOTICE"; then
    failures+=("NOTICE must contain SPDX-License-Identifier: Apache-2.0")
fi

email_pattern='[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}'
for policy_document in "${policy_documents[@]}"; do
    while IFS= read -r email; do
        if [[ "$email" != "contact@matrixreligio.com" ]]; then
            failures+=("Unexpected contact in $policy_document: $email")
        fi
    done < <(/usr/bin/grep -Eio "$email_pattern" "$repo_root/$policy_document" 2>/dev/null | /usr/bin/sort -u || true)
done

security="$repo_root/SECURITY.md"
if ! /usr/bin/grep -Eqi 'supported (versions|branches)' "$security"; then
    failures+=("SECURITY.md must document supported versions or branches")
fi
if ! /usr/bin/grep -qiF 'contact@matrixreligio.com' "$security"; then
    failures+=("SECURITY.md must use contact@matrixreligio.com")
fi
if ! /usr/bin/grep -Eqi '(privately|private report|private reporting|security advisory)' "$security"; then
    failures+=("SECURITY.md must document a private reporting path")
fi
if ! /usr/bin/grep -Eqi '2 business days' "$security"; then
    failures+=("SECURITY.md must state the 2-business-day acknowledgement target")
fi

markdown_files=("${(@f)$(/usr/bin/find "$repo_root" -type f -name '*.md' \
    -not -path "$repo_root/.git/*" \
    -not -path "$repo_root/.build/*" \
    -not -path "$repo_root/.tools/*" \
    -not -path "$repo_root/.worktrees/*" | /usr/bin/sort)}")

for markdown in "${markdown_files[@]}"; do
    relative_markdown="${markdown#$repo_root/}"
    markdown_dir="${markdown:h}"
    while IFS= read -r destination; do
        destination="${destination#<}"
        destination="${destination%>}"
        destination="${destination%% *}"
        case "$destination" in
            ''|'#'*|http://*|https://*|mailto:*|app://*) continue ;;
        esac

        local_path="${destination%%#*}"
        local_path="${local_path%%\?*}"
        [[ -z "$local_path" ]] && continue
        if [[ "$local_path" == /* ]]; then
            target="$repo_root$local_path"
        else
            target="$markdown_dir/$local_path"
        fi
        if [[ ! -e "${target:A}" ]]; then
            failures+=("Broken local Markdown link in $relative_markdown: $destination")
        fi
    done < <(/usr/bin/perl -ne 'while (/!?\[[^]]*\]\(([^)]+)\)/g) { print "$1\n" }' "$markdown")
done

if (( ${#failures[@]} > 0 )); then
    for failure in "${(@on)failures}"; do
        print -u2 -r -- "$failure"
    done
    print -u2 -r -- "Open-source baseline FAIL: ${#failures[@]} problem(s)"
    exit 1
fi

print -r -- "Open-source baseline PASS: ${#policy_documents[@]} policy documents, 0 broken links"
