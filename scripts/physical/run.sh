#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h:h}"
policy_root="${MC_PHYSICAL_POLICY_ROOT:-$repo_root}"
plan="$repo_root/Config/physical-test-plan-v1.json"
physical_root="$repo_root/.artifacts/physical"
derived_data="$repo_root/.artifacts/DerivedData"
expected_team_id="UPBK2H6LZM"
digest_100="13f45f26da94c354adcbefe1e8f7631e7f126e93c5d4dd6a5a538aa66b4f479d"
digest_110="0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714"
physical_confirmation="ALLOW_EMPTY_HOST_MUTATION_AND_COMPLETE_RESTORE"
package_url_100="https://github.com/apple/container/releases/download/1.0.0/container-1.0.0-installer-signed.pkg"
package_url_110="https://github.com/apple/container/releases/download/1.1.0/container-1.1.0-installer-signed.pkg"

die() {
    print -u2 -- "MacContainer physical validation error: $*"
    exit 1
}

policy_check() {
    local candidate="$policy_root/scripts/physical/run.sh"
    [[ -f "$candidate" ]] || die "runner missing from policy root"
    local required=(
        run_read_only_preflight REFUSED_EXISTING_STATE RUN_UUID 'umask 077' 'chmod 0700'
        'trap cleanup EXIT HUP INT TERM' verify_digest verify_installer_signature
        "$digest_100" "$digest_110" "$expected_team_id" run_with_timeout
        '.artifacts/DerivedData' PHYSICAL_TEST_AUTHORIZATION production_complete_uninstall
        compare-baseline.swift summarize.swift recover.swift
        'cleanup ledger contains only verifiedAbsent states'
    )
    local item
    for item in $required; do
        /usr/bin/grep -Fq -- "$item" "$candidate" || die "runner policy missing: $item"
    done
    /usr/bin/grep -Eq '^run_read_only_preflight\(\) \{' "$candidate" || die "preflight function missing"
    /usr/bin/grep -Eq '^verify_digest\(\) \{' "$candidate" || die "digest verification function missing"
    /usr/bin/grep -Eq '^verify_installer_signature\(\) \{' "$candidate" || die "signature verification function missing"
    /usr/bin/grep -Eq '^trap cleanup EXIT HUP INT TERM$' "$candidate" || die "cleanup trap missing"
    local forbidden='brew'' install|pip(3)?'' install|npm'' install -g|sudo[[:space:]]+''rm|rm[[:space:]]+''-rf'
    if /usr/bin/grep -Eq -- "($forbidden)" "$candidate"; then
        die "runner contains global install or unguarded recursive cleanup"
    fi
    print -r -- "Physical runner policy PASS"
}

if [[ "${1:-}" == "--policy-check" ]]; then
    policy_check
    exit 0
fi

mode="${1:-}"
phase=""
case "$mode" in
    --simulated-host) ;;
    --all) phase="all" ;;
    --phase)
        [[ $# -eq 2 ]] || die "--phase requires a phase name"
        phase="$2"
        ;;
    *) die "usage: run.sh --simulated-host | --all | --phase <name> | --policy-check" ;;
esac

umask 077
RUN_UUID="$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
run_root="$physical_root/$RUN_UUID"
preflight_output="${TMPDIR%/}/maccontainer-physical-preflight-$RUN_UUID.json"
cleanup_running=0

cleanup() {
    local original_status=$?
    (( cleanup_running == 0 )) || return $original_status
    cleanup_running=1
    /bin/rm -f -- "$preflight_output"
    if [[ -d "$run_root" && -f "$run_root/cleanup.jsonl" ]]; then
        if /usr/bin/swift "$script_dir/recover.swift" --run-root "$run_root" --run-id "$RUN_UUID"; then
            # Recovery proves the cleanup ledger contains only verifiedAbsent states before bootstrap removal.
            /bin/rm -f -- "$run_root/cleanup.jsonl"
            /bin/rmdir -- "$run_root" 2>/dev/null || true
        else
            print -u2 -- "physical recovery refused; preserving exact run root for guarded diagnosis: $run_root"
            original_status=1
        fi
    elif [[ -d "$run_root" ]]; then
        /bin/rmdir -- "$run_root" 2>/dev/null || {
            print -u2 -- "physical bootstrap root is nonempty without a ledger; refusing cleanup: $run_root"
            original_status=1
        }
    fi
    /bin/rmdir -- "$physical_root" 2>/dev/null || true
    return $original_status
}
trap cleanup EXIT HUP INT TERM

run_with_timeout() {
    local seconds="$1"
    shift
    "$@" &
    local command_pid=$!
    (
        local sleep_pid
        trap '[[ -n "${sleep_pid:-}" ]] && /bin/kill -TERM "$sleep_pid" 2>/dev/null || true; exit 0' TERM INT HUP
        /bin/sleep "$seconds" &
        sleep_pid=$!
        wait "$sleep_pid" || exit 0
        /bin/kill -TERM "$command_pid" 2>/dev/null || true
        /bin/sleep 2
        /bin/kill -KILL "$command_pid" 2>/dev/null || true
    ) &
    local watchdog_pid=$!
    local command_status=0
    wait "$command_pid" || command_status=$?
    /bin/kill -TERM "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    return $command_status
}

run_read_only_preflight() {
    if [[ "$mode" == "--simulated-host" ]]; then
        print -r -- '{"permission":"SAFE_TO_TEST","simulated":true}' > "$preflight_output"
        print -r -- "SAFE_TO_TEST"
        return
    fi
    local output rc=0
    output="$(/usr/bin/swift "$script_dir/preflight.swift" --output "$preflight_output" --read-only)" || rc=$?
    print -r -- "$output"
    if (( rc != 0 )); then
        [[ "$output" == *REFUSED_EXISTING_STATE* ]] || die "read-only preflight failed without refusal evidence"
        return $rc
    fi
}

verify_digest() {
    local package_path="$1"
    local expected="$2"
    local actual
    actual="$(/usr/bin/shasum -a 256 "$package_path" | /usr/bin/awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || die "package digest mismatch: ${package_path:t}"
}

verify_installer_signature() {
    local package_path="$1"
    local details
    details="$(/usr/sbin/pkgutil --check-signature "$package_path")"
    [[ "$details" == *"$expected_team_id"* ]] || die "package installer Team ID mismatch"
    [[ "$details" == *"Status: signed by a certificate trusted by Mac OS X"* ]] || \
        die "package installer signature is not trusted"
}

download_verified_package() {
    local url="$1"
    local destination="$2"
    local digest="$3"
    /usr/bin/curl --fail --location --proto '=https' --tlsv1.2 \
        --connect-timeout 20 --max-time 900 --retry 3 --output "$destination" "$url"
    verify_digest "$destination" "$digest"
    verify_installer_signature "$destination"
}

run_signed_helper_phase() {
    local selected_phase="$1"
    run_with_timeout 7200 /usr/bin/env \
        PHYSICAL_RUN_ID="$RUN_UUID" \
        PHYSICAL_RUN_ROOT="$run_root" \
        PHYSICAL_TEST_AUTHORIZATION="$RUN_UUID" \
        /usr/bin/xcodebuild \
        -project "$repo_root/MacContainer.xcodeproj" \
        -scheme MacContainer \
        -derivedDataPath "$derived_data" \
        PHYSICAL_RUN_ID="$RUN_UUID" \
        PHYSICAL_RUN_ROOT="$run_root" \
        PHYSICAL_TEST_AUTHORIZATION="$RUN_UUID" \
        PHYSICAL_TEST_PHASE="$selected_phase" test
}

run_physical_package_tests() {
    local selected_filter="$1"
    run_with_timeout 7200 /usr/bin/env \
        PHYSICAL_RUN_ID="$RUN_UUID" \
        PHYSICAL_RUN_ROOT="$run_root" \
        PHYSICAL_TEST_AUTHORIZATION="$RUN_UUID" \
        /usr/bin/swift test --package-path "$repo_root" --filter "$selected_filter"
}

ledger_transition() {
    local artifact_type="$1"
    local value="$2"
    local state="$3"
    /usr/bin/swift run --package-path "$repo_root" mc-physical ledger-transition \
        --run-root "$run_root" --run-id "$RUN_UUID" \
        --type "$artifact_type" --value "$value" --state "$state"
}

production_complete_uninstall() {
    run_signed_helper_phase complete-uninstall-and-restore
}

compare_restored_baseline() {
    /usr/bin/swift "$script_dir/compare-baseline.swift" \
        "$run_root/physical-baseline.json" "$run_root/post-physical.json"
}

summarize_results() {
    /usr/bin/swift "$script_dir/summarize.swift" \
        --input "$run_root/raw-results.json" --output "$run_root/physical-summary.json"
}

preflight_status=0
run_read_only_preflight || preflight_status=$?
if (( preflight_status != 0 )); then
    exit $preflight_status
fi

if [[ "$mode" != "--simulated-host" ]]; then
    [[ "${MACCONTAINER_PHYSICAL_CONFIRMATION:-}" == "$physical_confirmation" ]] || \
        die "MACCONTAINER_PHYSICAL_CONFIRMATION missing or mismatched"
fi

/bin/mkdir -p -- "$physical_root"
/bin/mkdir -- "$run_root"
/bin/chmod 0700 "$run_root"

if [[ "$mode" == "--simulated-host" ]]; then
    run_with_timeout 180 /usr/bin/swift run --package-path "$repo_root" mc-physical simulate-run \
        --run-root "$run_root" --run-id "$RUN_UUID" --plan "$plan"
    exit 0
fi

baseline="$run_root/physical-baseline.json"
ledger_transition file "$baseline" planned
/bin/cp "$preflight_output" "$baseline"
ledger_transition file "$baseline" created

derived_data="$run_root/DerivedData"
ledger_transition temporary-directory "$derived_data" planned
/bin/mkdir -- "$derived_data"
ledger_transition temporary-directory "$derived_data" created

downloads="$run_root/downloads"
ledger_transition temporary-directory "$downloads" planned
/bin/mkdir -- "$downloads"
ledger_transition temporary-directory "$downloads" created

if [[ "$phase" == "upgrade-rollback" || "$phase" == "all" ]]; then
    package_100="$downloads/container-1.0.0-installer-signed.pkg"
    package_110="$downloads/container-1.1.0-installer-signed.pkg"
    ledger_transition runtime-package "$package_100" planned
    download_verified_package "$package_url_100" "$package_100" "$digest_100"
    ledger_transition runtime-package "$package_100" created
    ledger_transition runtime-package "$package_110" planned
    download_verified_package "$package_url_110" "$package_110" "$digest_110"
    ledger_transition runtime-package "$package_110" created
fi

case "$phase" in
    install-and-operations)
        run_signed_helper_phase "$phase"
        run_physical_package_tests PhysicalOperationTests
        ;;
    upgrade-rollback)
        run_signed_helper_phase "$phase"
        run_physical_package_tests PhysicalUpgradeTests
        ;;
    physical-ui)
        run_signed_helper_phase "$phase"
        ;;
    complete-uninstall-and-restore)
        production_complete_uninstall
        compare_restored_baseline
        ;;
    all)
        run_signed_helper_phase install-and-operations
        run_physical_package_tests PhysicalOperationTests
        run_signed_helper_phase upgrade-rollback
        run_physical_package_tests PhysicalUpgradeTests
        run_signed_helper_phase physical-ui
        production_complete_uninstall
        compare_restored_baseline
        summarize_results
        ;;
    *) die "unsupported physical phase: $phase" ;;
esac
