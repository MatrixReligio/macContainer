#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
fixture="$(mktemp -d "${TMPDIR%/}/maccontainer-localization-policy.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
resources="$repo_root/App/MacContainer/Resources"
catalog="$resources/Localizable.xcstrings"
contract="$repo_root/Sources/MCContracts/Resources/apple-container-1.1.0.json"

for file in "$repo_root/scripts/check-localizations.swift" "$repo_root/scripts/check-parameter-help.swift"; do
    [[ -f "$file" ]] || { print -u2 -- "missing required file: ${file#$repo_root/}"; exit 1; }
done

swift "$repo_root/scripts/check-localizations.swift" "$resources"
swift "$repo_root/scripts/check-parameter-help.swift" "$contract" "$catalog"

typeset -a update_agent_notification_keys=(
    "MacContainer runtime update"
    "Apple container %@ is compatibility-approved and ready to review."
    "An approved runtime update is waiting. Open MacContainer for details."
    "A discovered runtime is held for safety. Open MacContainer for details."
    "The runtime update was rolled back. Open MacContainer for recovery details."
    "Runtime recovery requires attention in MacContainer."
    "Open MacContainer to review runtime update status."
)
for key in "${update_agent_notification_keys[@]}"; do
    /usr/bin/jq -e --arg key "$key" '
        .strings[$key].localizations as $localizations
        | ($localizations != null) and all(
            ["en", "zh-Hans", "zh-Hant", "ja", "ko"][];
            ($localizations[.].stringUnit.state == "translated") and
            (($localizations[.].stringUnit.value | type) == "string") and
            (($localizations[.].stringUnit.value | length) > 0)
        )
    ' "$catalog" >/dev/null || {
        print -u2 -- "missing localized update-agent notification key: $key"
        exit 1
    }
done

cp -R "$resources" "$fixture/resources"
first_key="$(/usr/bin/jq -r '.strings | keys[0]' "$fixture/resources/Localizable.xcstrings")"
/usr/bin/jq --arg key "$first_key" 'del(.strings[$key].localizations.ko)' \
    "$catalog" > "$fixture/resources/Localizable.xcstrings"
if swift "$repo_root/scripts/check-localizations.swift" "$fixture/resources" >/dev/null 2>&1; then
    print -u2 -- "checker accepted a missing Korean translation"
    exit 1
fi

cp "$catalog" "$fixture/resources/Localizable.xcstrings"
/usr/bin/jq --arg key "$first_key" '.strings[$key].localizations.ja.stringUnit.state = "needs_review"' \
    "$catalog" > "$fixture/resources/Localizable.xcstrings"
if swift "$repo_root/scripts/check-localizations.swift" "$fixture/resources" >/dev/null 2>&1; then
    print -u2 -- "checker accepted a needs-review translation"
    exit 1
fi

cp "$catalog" "$fixture/resources/Localizable.xcstrings"
/usr/bin/jq '.strings["Mutation %@"] = {"localizations": {
    "en": {"stringUnit": {"state": "translated", "value": "Value %@"}},
    "zh-Hans": {"stringUnit": {"state": "translated", "value": "值 %@"}},
    "zh-Hant": {"stringUnit": {"state": "translated", "value": "值 %@"}},
    "ja": {"stringUnit": {"state": "translated", "value": "値 %@"}},
    "ko": {"stringUnit": {"state": "translated", "value": "값 %d"}}
}}' "$catalog" > "$fixture/resources/Localizable.xcstrings"
if swift "$repo_root/scripts/check-localizations.swift" "$fixture/resources" >/dev/null 2>&1; then
    print -u2 -- "checker accepted a placeholder type mismatch"
    exit 1
fi

cp "$catalog" "$fixture/resources/Localizable.xcstrings"
/usr/bin/jq 'del(.strings["MacContainer runtime update"])' \
    "$catalog" > "$fixture/resources/Localizable.xcstrings"
if swift "$repo_root/scripts/check-localizations.swift" "$fixture/resources" "$repo_root/App" >/dev/null 2>&1; then
    print -u2 -- "checker accepted a missing update-agent notification key"
    exit 1
fi

mkdir -p "$fixture/app/MacContainer"
cat > "$fixture/app/MacContainer/DynamicCopy.swift" <<'SWIFT'
import SwiftUI

let dynamicCopy = LocalizedStringKey("Dynamic localization key")
SWIFT
if swift "$repo_root/scripts/check-localizations.swift" \
    "$fixture/resources" "$fixture/app" >/dev/null 2>&1; then
    print -u2 -- "checker accepted a missing LocalizedStringKey initializer"
    exit 1
fi

parameter_key="$(/usr/bin/jq -r '.operations[0].parameters[0].detailedHelpKey' "$contract")"
cp "$catalog" "$fixture/parameter.xcstrings"
/usr/bin/jq --arg key "$parameter_key" 'del(.strings[$key])' \
    "$catalog" > "$fixture/parameter.xcstrings"
if swift "$repo_root/scripts/check-parameter-help.swift" "$contract" "$fixture/parameter.xcstrings" >/dev/null 2>&1; then
    print -u2 -- "parameter checker accepted a missing detail key"
    exit 1
fi

print -r -- "Localization policy PASS: completeness and mutation cases rejected"
