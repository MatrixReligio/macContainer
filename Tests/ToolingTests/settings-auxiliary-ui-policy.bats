#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
advanced="$repo_root/App/MacContainer/Views/Settings/AdvancedSettingsView.swift"
templates="$repo_root/App/MacContainer/Views/Templates/TemplateLibraryView.swift"
activity="$repo_root/App/MacContainer/Views/Shared/EmptyStateView.swift"

/usr/bin/grep -Fq '.sheet(isPresented: $activityCenterPresented)' "$advanced" || {
    print -u2 -- "settings activity center must be an owned sheet"
    exit 1
}
if /usr/bin/grep -Fq 'openWindow(id: "activity-center")' "$advanced"; then
    print -u2 -- "settings activity center must not own an independent app window"
    exit 1
fi
/usr/bin/grep -Fq \
    '.contentMargins(.top, AppWindowLayout.templateLibraryTopInset, for: .scrollContent)' \
    "$templates" || {
    print -u2 -- "template list must preserve titlebar-safe top spacing"
    exit 1
}
if /usr/bin/grep -Fq 'LocalizedStringKey(activity.titleKey)' "$activity" \
    || /usr/bin/grep -Fq 'LocalizedStringKey(activity.phaseKey)' "$activity"; then
    print -u2 -- "activity center must not expose dynamic localization keys"
    exit 1
fi

print -r -- "Settings auxiliary UI policy PASS"
