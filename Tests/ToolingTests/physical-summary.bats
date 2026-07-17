#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
fixture="$(mktemp -d "${TMPDIR%/}/maccontainer-physical-summary.XXXXXX")"
trap '/bin/rm -rf "$fixture"' EXIT

app="$fixture/MacContainer.app"
/bin/mkdir -p "$app/Contents/MacOS" "$fixture/results"
/bin/cp /usr/bin/true "$app/Contents/MacOS/MacContainer"
/usr/bin/plutil -create xml1 "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string container.matrixreligio.com "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string 1.0.0 "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleVersion -string 1 "$app/Contents/Info.plist"
/usr/bin/codesign --force --sign - --identifier container.matrixreligio.com "$app"

print -r -- '{"schemaVersion":1,"tests":[{"id":"one","category":"test","phase":"one"},{"id":"two","category":"test","phase":"two"}]}' > "$fixture/plan.json"
print -r -- '{"id":"one","passed":true}' > "$fixture/results/one.json"

arguments=(
    --plan "$fixture/plan.json"
    --results "$fixture/results"
    --app "$app"
    --output "$fixture/summary.json"
    --source-commit 5973b9cc626a3e7a499bb316a958237ebe14e2ed
    --runtime-version 1.1.0
    --runtime-sha256 0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714
    --signer-key-id matrixreligio-physical-2026-07-r1
    --residue-count 0
    --baseline-restored true
    --cleanup-ledger-empty true
)

if /usr/bin/swift "$repo_root/scripts/physical/summarize.swift" $arguments; then
    print -u2 -- "physical summary accepted an incomplete result set"
    exit 1
fi
[[ ! -e "$fixture/summary.json" ]]

print -r -- '{"id":"two","passed":true}' > "$fixture/results/two.json"
/usr/bin/swift "$repo_root/scripts/physical/summarize.swift" $arguments

/usr/bin/plutil -convert json -o "$fixture/summary.plist.json" "$fixture/summary.json"
[[ "$(/usr/bin/plutil -extract schemaVersion raw -o - "$fixture/summary.json")" == 1 ]]
[[ "$(/usr/bin/plutil -extract operationResults.one raw -o - "$fixture/summary.json")" == true ]]
[[ "$(/usr/bin/plutil -extract operationResults.two raw -o - "$fixture/summary.json")" == true ]]
[[ "$(/usr/bin/plutil -extract baselineRestored raw -o - "$fixture/summary.json")" == true ]]
[[ "$(/usr/bin/plutil -extract cleanupLedgerEmpty raw -o - "$fixture/summary.json")" == true ]]
[[ "$(/usr/bin/plutil -extract signature raw -o - "$fixture/summary.json")" == "" ]]
[[ "$(/usr/bin/plutil -extract requiredOperationIDs.0 raw -o - "$fixture/summary.expectations.json")" == one ]]
[[ "$(/usr/bin/plutil -extract requiredOperationIDs.1 raw -o - "$fixture/summary.expectations.json")" == two ]]
[[ "$(/usr/bin/plutil -extract appBundleIdentifier raw -o - "$fixture/summary.expectations.json")" == container.matrixreligio.com ]]

print -r -- "Physical summary completeness tests PASS"
