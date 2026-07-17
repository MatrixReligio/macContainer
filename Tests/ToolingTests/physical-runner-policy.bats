#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
runner="$repo_root/scripts/physical/run.sh"
plan="$repo_root/Config/physical-test-plan-v1.json"

[[ -x "$runner" ]] || { print -u2 -- "missing executable physical runner"; exit 1; }
[[ -f "$plan" ]] || { print -u2 -- "missing physical test plan"; exit 1; }
/usr/bin/ruby -rjson -e 'JSON.parse(File.read(ARGV.fetch(0)))' "$plan"

require_text() {
    local text="$1"
    /usr/bin/grep -Fq -- "$text" "$runner" || {
        print -u2 -- "physical runner missing policy: $text"
        exit 1
    }
}

require_text 'run_read_only_preflight'
require_text 'REFUSED_EXISTING_STATE'
require_text 'RUN_UUID'
require_text 'umask 077'
require_text 'chmod 0700'
require_text 'trap cleanup EXIT HUP INT TERM'
require_text 'verify_digest'
require_text 'verify_installer_signature'
require_text '0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714'
require_text '13f45f26da94c354adcbefe1e8f7631e7f126e93c5d4dd6a5a538aa66b4f479d'
require_text 'UPBK2H6LZM'
require_text 'run_with_timeout'
require_text '.artifacts/DerivedData'
require_text 'PHYSICAL_TEST_AUTHORIZATION'
require_text 'production_complete_uninstall'
require_text 'compare-baseline.swift'
require_text 'summarize.swift'
require_text 'recover.swift'
require_text 'cleanup ledger contains only verifiedAbsent states'

if /usr/bin/grep -Eq -- '(brew install|pip(3)? install|npm install -g|sudo[[:space:]]+rm|rm[[:space:]]+-rf)' "$runner"; then
    print -u2 -- "physical runner contains global install or unsafe cleanup"
    exit 1
fi

"$runner" --policy-check

before="$(find "$repo_root/.artifacts/physical" -mindepth 1 -maxdepth 1 -print 2>/dev/null | sort || true)"
output="$($runner --simulated-host)"
after="$(find "$repo_root/.artifacts/physical" -mindepth 1 -maxdepth 1 -print 2>/dev/null | sort || true)"
[[ "$output" == *'Physical simulation PASS: all test IDs exercised, baseline restored, cleanup ledger empty'* ]]
[[ "$before" == "$after" ]] || { print -u2 -- "simulation left a run root"; exit 1; }

fixture="$(mktemp -d "${TMPDIR%/}/maccontainer-physical-policy.XXXXXX")"
trap '/bin/rm -rf "$fixture"' EXIT
/bin/mkdir -p "$fixture/scripts/physical"
/bin/cp "$runner" "$fixture/scripts/physical/run.sh"
/usr/bin/sed -i '' '/^verify_digest() {/,/^}/d' "$fixture/scripts/physical/run.sh"
if MC_PHYSICAL_POLICY_ROOT="$fixture" "$fixture/scripts/physical/run.sh" --policy-check; then
    print -u2 -- "physical policy accepted package digest bypass"
    exit 1
fi

print -r -- "Physical runner policy and mutation tests PASS"
