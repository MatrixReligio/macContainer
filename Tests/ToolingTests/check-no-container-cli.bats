#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
fixture="$(mktemp -d "${TMPDIR%/}/maccontainer-cli-scan.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/Sources" "$fixture/scripts" "$fixture/Tests" "$fixture/docs"

assert_rejected() {
    local source_line="$1"
    local fixture_path="$2"
    local output

    print -r -- "$source_line" > "$fixture_path"
    if output="$("$repo_root/scripts/check-no-container-cli.sh" "$fixture" 2>&1)"; then
        print -u2 -- "expected forbidden backend scanner to reject: $source_line"
        exit 1
    fi
    if [[ "$output" != *"Forbidden backend scan FAIL"* ]]; then
        print -u2 -- "scanner rejection did not include the expected diagnostic"
        print -u2 -- "$output"
        exit 1
    fi
    rm "$fixture_path"
}

assert_rejected \
    'Process.run(URL(fileURLWithPath: "/usr/local/bin/container"))' \
    "$fixture/Sources/BadContainerCLI.swift"
assert_rejected \
    'let updater = "https://raw.githubusercontent.com/apple/container/main/scripts/update-container.sh"' \
    "$fixture/scripts/BadUpdater.zsh"
assert_rejected \
    'let uninstaller = "uninstall-container.sh"' \
    "$fixture/Sources/BadUninstaller.swift"

print -r -- 'let name = "container"' > "$fixture/Sources/Good.swift"
print -r -- 'let installer = "/usr/sbin/installer"' > "$fixture/Sources/Installer.swift"
print -r -- 'Process.run(URL(fileURLWithPath: "/usr/local/bin/container"))' > "$fixture/Tests/Fixture.swift"
print -r -- '`/usr/local/bin/container list` is prohibited.' > "$fixture/docs/security.md"

"$repo_root/scripts/check-no-container-cli.sh" "$fixture"
PATH=/usr/bin:/bin "$repo_root/scripts/check-no-container-cli.sh" "$fixture"

if [[ -e "$fixture/Sources/BadContainerCLI.swift" || \
      -e "$fixture/scripts/BadUpdater.zsh" || \
      -e "$fixture/Sources/BadUninstaller.swift" ]]; then
    print -u2 -- "forbidden fixture was not removed"
    exit 1
fi

print -r -- "Forbidden backend scanner tests PASS"
