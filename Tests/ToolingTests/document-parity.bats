#!/bin/zsh
set -euo pipefail
setopt NULL_GLOB

repo_root="${0:A:h:h:h}"
checker="$repo_root/scripts/check-doc-parity.swift"
fixture="$(mktemp -d "${TMPDIR%/}/maccontainer-doc-parity.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

[[ -f "$checker" ]] || { print -u2 -- "missing document parity checker"; exit 1; }
readmes=("$repo_root/README.md" "$repo_root"/README.*.md)
swift "$checker" "$repo_root/docs" "${readmes[@]}"

ditto "$repo_root/docs" "$fixture/docs"
for readme in "$repo_root"/README*.md; do ditto "$readme" "$fixture/${readme:t}"; done
readmes=("$fixture/README.md" "$fixture"/README.*.md)

/usr/bin/sed -i '' 's/^source_revision: .*/source_revision: deadbeef/' "$fixture/docs/ja/USER_GUIDE.md"
if swift "$checker" "$fixture/docs" "${readmes[@]}" >/dev/null 2>&1; then
    print -u2 -- "checker accepted a stale source revision"
    exit 1
fi

ditto "$repo_root/docs/ja/USER_GUIDE.md" "$fixture/docs/ja/USER_GUIDE.md"
/usr/bin/sed -i '' '0,/<a id=/s///' "$fixture/docs/ja/USER_GUIDE.md"
if swift "$checker" "$fixture/docs" "${readmes[@]}" >/dev/null 2>&1; then
    print -u2 -- "checker accepted missing stable heading IDs"
    exit 1
fi

ditto "$repo_root/docs/ja/USER_GUIDE.md" "$fixture/docs/ja/USER_GUIDE.md"
print -r -- '\n[broken](DOES_NOT_EXIST.md)' >> "$fixture/docs/ja/USER_GUIDE.md"
if swift "$checker" "$fixture/docs" "${readmes[@]}" >/dev/null 2>&1; then
    print -u2 -- "checker accepted a broken local link"
    exit 1
fi

print -r -- "Document parity policy PASS: stale, heading, and link mutations rejected"
