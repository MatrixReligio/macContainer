#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
master="$repo_root/Design/AppIcon/MacContainer-master.png"
committed="$repo_root/App/MacContainer/Resources/Assets.xcassets/AppIcon.appiconset"
fixture="$(mktemp -d "${TMPDIR%/}/maccontainer-app-icon.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

generated="$fixture/AppIcon.appiconset"
"$repo_root/scripts/generate-app-icon.swift" --input "$master" --output "$generated"
"$repo_root/scripts/check-app-icon.swift" --master "$master" --app-icon-set "$generated"
/usr/bin/diff -rq "$committed" "$generated"

broken="$fixture/Broken.appiconset"
/usr/bin/ditto "$generated" "$broken"
rm "$broken/icon_16x16.png"
if "$repo_root/scripts/check-app-icon.swift" --master "$master" --app-icon-set "$broken"; then
    print -u2 -- "expected missing icon slot validation to fail"
    exit 1
fi

print -r -- "App icon pipeline tests PASS"
