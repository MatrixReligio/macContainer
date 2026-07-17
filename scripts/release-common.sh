#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
TEAM_ID="4DUQGD879H"
DEVELOPER_ID_IDENTITY="Developer ID Application: MatrixReligio LLC (4DUQGD879H)"
APP_BUNDLE_ID="container.matrixreligio.com"
HELPER_BUNDLE_ID="container.matrixreligio.com.helper"
AGENT_BUNDLE_ID="container.matrixreligio.com.update-agent"

die() {
    print -u2 -- "MacContainer release error: $*"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command unavailable: $1"
}

require_file() {
    [[ -f "$1" ]] || die "required file missing: $1"
}

require_clean_tracked_worktree() {
    git -C "$REPO_ROOT" diff --quiet -- || die "tracked worktree has unstaged changes"
    git -C "$REPO_ROOT" diff --cached --quiet -- || die "tracked worktree has staged changes"
}

project_setting() {
    local key="$1"
    /usr/bin/awk -F': ' -v key="$key" '$1 ~ "^[[:space:]]*" key "$" { gsub(/\"/, "", $2); print $2; exit }' \
        "$REPO_ROOT/project.yml"
}

validate_release_identity() {
    local version="$1"
    local tag="$2"
    [[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || die "version must be MAJOR.MINOR.PATCH"
    [[ "$tag" == "v$version" ]] || die "tag and version disagree"
    [[ "$(project_setting MARKETING_VERSION)" == "$version" ]] || die "project version and release version disagree"
    [[ "$(project_setting CURRENT_PROJECT_VERSION)" =~ '^[1-9][0-9]*$' ]] || die "build number must be positive"
    [[ "$(git -C "$REPO_ROOT" tag --points-at HEAD --list "$tag")" == "$tag" ]] || die "HEAD is not tagged $tag"
}

require_release_identity() {
    local requested="${MC_DEVELOPER_ID_IDENTITY:-$DEVELOPER_ID_IDENTITY}"
    [[ "$requested" == "$DEVELOPER_ID_IDENTITY" ]] || die "Developer ID identity override is forbidden"
    /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq -- "\"$DEVELOPER_ID_IDENTITY\"" || \
        die "exact Developer ID Application identity is unavailable"
}

codesign_details() {
    /usr/bin/codesign -d --verbose=4 "$1" 2>&1
}

verify_team_and_runtime() {
    local path="$1"
    local details
    details="$(codesign_details "$path")"
    [[ "$details" == *"TeamIdentifier=$TEAM_ID"* ]] || die "unexpected signing team: $path"
    [[ "$details" == *"flags="*"runtime"* ]] || die "hardened runtime missing: $path"
    /usr/bin/codesign --verify --strict --verbose=2 "$path"
}

verify_designated_requirement() {
    local path="$1"
    local identifier="$2"
    local requirement="anchor apple generic and identifier \"$identifier\" and certificate leaf[subject.OU] = \"$TEAM_ID\""
    /usr/bin/codesign --verify --strict --test-requirement="=$requirement" "$path" || \
        die "designated requirement mismatch: $identifier"
}

require_private_file_permissions() {
    local path="$1"
    require_file "$path"
    local mode
    mode="$(/usr/bin/stat -f '%Lp' "$path")"
    (( (8#$mode & 8#077) == 0 )) || die "private file must not be group/world accessible"
}
