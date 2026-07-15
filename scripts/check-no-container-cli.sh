#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
scan_root="${1:-$repo_root}"

if [[ ! -d "$scan_root" ]]; then
    print -u2 -- "Forbidden backend scan FAIL: not a directory: $scan_root"
    exit 2
fi

typeset -a production_roots=()
for relative_root in App Sources scripts; do
    if [[ -d "$scan_root/$relative_root" ]]; then
        production_roots+=("$scan_root/$relative_root")
    fi
done

if (( ${#production_roots} == 0 )); then
    print -r -- "Forbidden backend scan PASS: no production source roots"
    exit 0
fi

forbidden_pattern='(/usr/local/bin/container([[:space:]"'"'"'\\)]|$)|update-container\.sh|uninstall-container\.sh)'
typeset matches
typeset scan_status
typeset search_tool

set +e
if (( $+commands[rg] )); then
    search_tool="rg"
    matches="$(rg \
        --line-number \
        --no-heading \
        --color never \
        --glob '*.swift' \
        --glob '*.sh' \
        --glob '*.zsh' \
        --glob '!check-no-container-cli.sh' \
        --regexp "$forbidden_pattern" \
        "${production_roots[@]}" 2>&1)"
else
    search_tool="grep"
    matches="$(LC_ALL=C /usr/bin/grep \
        --extended-regexp \
        --recursive \
        --line-number \
        --with-filename \
        --include='*.swift' \
        --include='*.sh' \
        --include='*.zsh' \
        --exclude='check-no-container-cli.sh' \
        "$forbidden_pattern" \
        "${production_roots[@]}" 2>&1)"
fi
scan_status=$?
set -e

case "$scan_status" in
    0)
        print -u2 -- "Forbidden backend scan FAIL: production code references a prohibited container CLI backend"
        print -u2 -- "$matches"
        exit 1
        ;;
    1)
        print -r -- "Forbidden backend scan PASS: ${#production_roots} production roots ($search_tool)"
        ;;
    *)
        print -u2 -- "Forbidden backend scan ERROR: $search_tool exited $scan_status"
        print -u2 -- "$matches"
        exit "$scan_status"
        ;;
esac
