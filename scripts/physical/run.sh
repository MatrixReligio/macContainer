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
        run_signed_helper_bootstrap run_signed_helper_cleanup
        --physical-helper-bootstrap-output= --physical-helper-cleanup-output=
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
packet_filter_audit_output="${TMPDIR%/}/packet-filter-$RUN_UUID.json"
helper_bootstrap_output="${TMPDIR%/}/helper-bootstrap-$RUN_UUID.json"
helper_cleanup_output="${TMPDIR%/}/helper-cleanup-$RUN_UUID.json"
physical_audit_app="${MACCONTAINER_PHYSICAL_AUDIT_APP:-}"
helper_registration_attempted=0
runtime_mutation_attempted=0
cleanup_running=0
helper_bootstrap_passed=0
summary_results_copy=""
summary_copy_preserved=0
package_100=""
package_110=""
upgrade_state=""
swiftpm_scratch=""

cleanup() {
    local original_status=$?
    (( cleanup_running == 0 )) || return $original_status
    cleanup_running=1
    if (( runtime_mutation_attempted == 1 )); then
        if ! production_complete_uninstall; then
            print -u2 -- "emergency production uninstall failed; preserving failure status"
            original_status=1
        fi
    fi
    if (( helper_registration_attempted == 1 )); then
        if ! run_signed_helper_cleanup "$physical_audit_app"; then
            print -u2 -- "signed helper cleanup failed; preserving failure status"
            original_status=1
        fi
    fi
    /bin/rm -f -- "$preflight_output"
    /bin/rm -f -- "$packet_filter_audit_output"
    /bin/rm -f -- "$helper_bootstrap_output"
    /bin/rm -f -- "$helper_cleanup_output"
    if [[ -n "$summary_results_copy" && -d "$summary_results_copy" && $summary_copy_preserved -eq 0 ]]; then
        [[ "$summary_results_copy" == "${TMPDIR%/}/maccontainer-physical-results-$RUN_UUID" ]] || return 1
        /bin/rm -R -- "$summary_results_copy"
    fi
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
        if [[ -n "$physical_audit_app" ]]; then
            run_signed_packet_filter_audit "$physical_audit_app" || return $?
            return 0
        fi
        return $rc
    fi
}

verify_signed_physical_app() {
    local app="$1"
    [[ -d "$app" && -x "$app/Contents/MacOS/MacContainer" ]] || \
        die "MACCONTAINER_PHYSICAL_AUDIT_APP is invalid"
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
    /usr/bin/codesign --verify --strict \
        --test-requirement '=anchor apple generic and identifier "container.matrixreligio.com" and certificate leaf[subject.OU] = "4DUQGD879H"' \
        "$app"
}

run_signed_helper_bootstrap() {
    local app="$1"
    local helper_status
    verify_signed_physical_app "$app"
    helper_registration_attempted=1
    /bin/rm -f -- "$helper_bootstrap_output"
    run_with_timeout 60 /usr/bin/open -n -W \
        --env "PHYSICAL_AUDIT_AUTHORIZATION=$RUN_UUID" \
        --env "PHYSICAL_AUDIT_ROOT=${TMPDIR%/}" \
        "$app" --args "--physical-helper-bootstrap-output=$helper_bootstrap_output"
    [[ -f "$helper_bootstrap_output" ]] || die "signed helper bootstrap produced no result"
    helper_status="$(/usr/bin/plutil -extract status raw -o - "$helper_bootstrap_output")"
    case "$helper_status" in
        enabled)
            helper_bootstrap_passed=1
            print -r -- "Signed helper bootstrap PASS"
            ;;
        requires-approval) die "privileged helper requires approval in System Settings > Login Items & Extensions" ;;
        *) die "signed helper bootstrap failed: $helper_status" ;;
    esac
}

run_signed_helper_cleanup() {
    local app="$1"
    local helper_status
    [[ -d "$app" && -x "$app/Contents/MacOS/MacContainer" ]] || return 1
    /bin/rm -f -- "$helper_cleanup_output"
    run_with_timeout 60 /usr/bin/open -n -W \
        --env "PHYSICAL_AUDIT_AUTHORIZATION=$RUN_UUID" \
        --env "PHYSICAL_AUDIT_ROOT=${TMPDIR%/}" \
        "$app" --args "--physical-helper-cleanup-output=$helper_cleanup_output" || return 1
    [[ -f "$helper_cleanup_output" ]] || return 1
    helper_status="$(/usr/bin/plutil -extract status raw -o - "$helper_cleanup_output")"
    [[ "$helper_status" == unregistered ]]
}

run_signed_packet_filter_audit() {
    local app="$1"
    local baseline_output="${2:-$preflight_output}"
    verify_signed_physical_app "$app"
    /bin/rm -f -- "$packet_filter_audit_output"
    run_with_timeout 60 /usr/bin/open -n -W \
        --env "PHYSICAL_AUDIT_AUTHORIZATION=$RUN_UUID" \
        --env "PHYSICAL_AUDIT_ROOT=${TMPDIR%/}" \
        "$app" --args "--physical-pf-audit-output=$packet_filter_audit_output"
    [[ -f "$packet_filter_audit_output" ]] || die "signed packet-filter audit produced no result"
    /usr/bin/swift run --package-path "$repo_root" mc-physical apply-pf-audit \
        "$baseline_output" "$packet_filter_audit_output"
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
        PHYSICAL_RESULTS_ROOT="$run_root/results" \
        /usr/bin/xcodebuild \
        -project "$repo_root/MacContainer.xcodeproj" \
        -scheme MacContainer \
        -derivedDataPath "$derived_data" \
        PHYSICAL_RUN_ID="$RUN_UUID" \
        PHYSICAL_RUN_ROOT="$run_root" \
        PHYSICAL_TEST_AUTHORIZATION="$RUN_UUID" \
        PHYSICAL_RESULTS_ROOT="$run_root/results" \
        PHYSICAL_TEST_PHASE="$selected_phase" test
}

run_physical_ui_tests() {
    run_with_timeout 7200 /usr/bin/env \
        PHYSICAL_RUN_ID="$RUN_UUID" \
        PHYSICAL_RUN_ROOT="$run_root" \
        PHYSICAL_TEST_AUTHORIZATION="$RUN_UUID" \
        PHYSICAL_RESULTS_ROOT="$run_root/results" \
        /usr/bin/xcodebuild \
        -project "$repo_root/MacContainer.xcodeproj" \
        -scheme MacContainer \
        -derivedDataPath "$derived_data" \
        -only-testing:MacContainerUITests/PhysicalRuntimeUITests test
}

run_physical_package_tests() {
    local selected_filter="$1"
    local selected_phase="${2:-$phase}"
    run_with_timeout 7200 /usr/bin/env \
        PHYSICAL_RUN_ID="$RUN_UUID" \
        PHYSICAL_RUN_ROOT="$run_root" \
        PHYSICAL_TEST_AUTHORIZATION="$RUN_UUID" \
        PHYSICAL_RESULTS_ROOT="$run_root/results" \
        PHYSICAL_TEST_PHASE="$selected_phase" \
        PHYSICAL_PACKAGE_100="$package_100" \
        PHYSICAL_PACKAGE_110="$package_110" \
        PHYSICAL_UPGRADE_STATE="$upgrade_state" \
        /usr/bin/swift test --package-path "$repo_root" --scratch-path "$swiftpm_scratch" \
        --skip-build --filter "$selected_filter"
}

prepare_signed_physical_test_harness() {
    /usr/bin/swift build --package-path "$repo_root" --scratch-path "$swiftpm_scratch" --build-tests
    local binary_root
    binary_root="$(/usr/bin/swift build --package-path "$repo_root" --scratch-path "$swiftpm_scratch" --show-bin-path)"
    local executable="$binary_root/MacContainerCorePackageTests.xctest/Contents/MacOS/MacContainerCorePackageTests"
    [[ -x "$executable" ]] || die "physical test executable missing"
    /usr/bin/codesign --force \
        --sign "Developer ID Application: MatrixReligio LLC (4DUQGD879H)" \
        --options runtime --timestamp --identifier container.matrixreligio.com "$executable"
    /usr/bin/codesign --verify --strict \
        --test-requirement '=anchor apple generic and identifier "container.matrixreligio.com" and certificate leaf[subject.OU] = "4DUQGD879H"' \
        "$executable"
    print -r -- "Signed physical test harness PASS"
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
    run_physical_package_tests PhysicalUninstallTests complete-uninstall-and-restore
    runtime_mutation_attempted=0
}

compare_restored_baseline() {
    /usr/bin/swift "$script_dir/compare-baseline.swift" \
        "$run_root/physical-baseline.json" "$run_root/post-physical.json"
}

capture_post_baseline() {
    local output="$run_root/post-physical.json"
    local message command_result=0
    ledger_transition file "$output" planned
    message="$(/usr/bin/swift "$script_dir/preflight.swift" --output "$output" --read-only)" || command_result=$?
    if (( command_result != 0 )); then
        [[ "$message" == *packet-filter-unverified* && -n "$physical_audit_app" ]] || \
            die "post-run read-only inventory failed: $message"
        run_signed_packet_filter_audit "$physical_audit_app" "$output"
    fi
    ledger_transition file "$output" created
}

summarize_results() {
    local output="$repo_root/.artifacts/physical-summary.json"
    /usr/bin/swift "$script_dir/summarize.swift" \
        --plan "$plan" \
        --results "$summary_results_copy" \
        --app "$physical_audit_app" \
        --output "$output" \
        --source-commit 5973b9cc626a3e7a499bb316a958237ebe14e2ed \
        --runtime-version 1.1.0 \
        --runtime-sha256 "$digest_110" \
        --signer-key-id matrixreligio-physical-2026-07-r1 \
        --residue-count 0 \
        --baseline-restored true \
        --cleanup-ledger-empty true
    print -r -- "Physical unsigned attestation: $output"
}

record_result_at() {
    local root="$1"
    local id="$2"
    [[ "$id" =~ '^[a-z0-9.-]+$' ]] || die "invalid physical result ID"
    [[ -d "$root" ]] || die "physical result root missing"
    local destination="$root/$id.json"
    local expected="{\"id\":\"$id\",\"passed\":true}"
    if [[ -e "$destination" ]]; then
        [[ "$(<"$destination")" == "$expected" ]] || die "conflicting physical result: $id"
        return
    fi
    print -r -- "$expected" > "$destination"
    /bin/chmod 0600 "$destination"
}

record_result() {
    record_result_at "$run_root/results" "$1"
}

finalize_physical_results() {
    summary_results_copy="${TMPDIR%/}/maccontainer-physical-results-$RUN_UUID"
    [[ ! -e "$summary_results_copy" ]] || die "physical summary copy already exists"
    /bin/mkdir -m 0700 "$summary_results_copy"
    /usr/bin/ditto "$run_root/results" "$summary_results_copy"
    summary_copy_preserved=1
    cleanup
    [[ ! -e "$run_root" ]] || die "physical run root survived cleanup"
    record_result_at "$summary_results_copy" cleanup.ledger-empty
    if ! summarize_results; then
        /bin/rm -R -- "$summary_results_copy"
        summary_results_copy=""
        summary_copy_preserved=0
        return 1
    fi
    /bin/rm -R -- "$summary_results_copy"
    summary_results_copy=""
    summary_copy_preserved=0
}

if [[ "$mode" != "--simulated-host" ]]; then
    [[ -n "$physical_audit_app" ]] || die "MACCONTAINER_PHYSICAL_AUDIT_APP is required for signed physical mutation"
    run_signed_helper_bootstrap "$physical_audit_app"
fi

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

results_root="$run_root/results"
ledger_transition temporary-directory "$results_root" planned
/bin/mkdir -m 0700 "$results_root"
ledger_transition temporary-directory "$results_root" created
record_result preflight.host-identity
record_result preflight.macos-version
record_result preflight.existing-state-refusal
(( helper_bootstrap_passed == 1 )) || die "signed helper authorization was not established"
record_result install.authorization

baseline="$run_root/physical-baseline.json"
ledger_transition file "$baseline" planned
/bin/cp "$preflight_output" "$baseline"
ledger_transition file "$baseline" created

derived_data="$run_root/DerivedData"
ledger_transition temporary-directory "$derived_data" planned
/bin/mkdir -- "$derived_data"
ledger_transition temporary-directory "$derived_data" created

swiftpm_scratch="$run_root/SwiftPM"
ledger_transition temporary-directory "$swiftpm_scratch" planned
/bin/mkdir -- "$swiftpm_scratch"
ledger_transition temporary-directory "$swiftpm_scratch" created
prepare_signed_physical_test_harness

downloads="$run_root/downloads"
ledger_transition temporary-directory "$downloads" planned
/bin/mkdir -- "$downloads"
ledger_transition temporary-directory "$downloads" created

if [[ "$phase" == "install-and-operations" || "$phase" == "upgrade-rollback" || \
      "$phase" == "physical-ui" || "$phase" == "complete-uninstall-and-restore" || "$phase" == "all" ]]; then
    package_110="$downloads/container-1.1.0-installer-signed.pkg"
    ledger_transition runtime-package "$package_110" planned
    download_verified_package "$package_url_110" "$package_110" "$digest_110"
    ledger_transition runtime-package "$package_110" created
    record_result install.package-digest
    record_result install.package-signature
fi

if [[ "$phase" == "upgrade-rollback" || "$phase" == "all" ]]; then
    package_100="$downloads/container-1.0.0-installer-signed.pkg"
    ledger_transition runtime-package "$package_100" planned
    download_verified_package "$package_url_100" "$package_100" "$digest_100"
    ledger_transition runtime-package "$package_100" created
    upgrade_state="$run_root/upgrade-state"
    ledger_transition temporary-directory "$upgrade_state" planned
    /bin/mkdir -- "$upgrade_state"
    ledger_transition temporary-directory "$upgrade_state" created
fi

case "$phase" in
    install-and-operations)
        runtime_mutation_attempted=1
        run_physical_package_tests PhysicalOperationTests
        ;;
    upgrade-rollback)
        runtime_mutation_attempted=1
        run_physical_package_tests PhysicalUpgradeTests
        ;;
    physical-ui)
        runtime_mutation_attempted=1
        run_physical_package_tests PhysicalOperationTests install-and-operations
        run_physical_ui_tests
        ;;
    complete-uninstall-and-restore)
        runtime_mutation_attempted=1
        run_physical_package_tests PhysicalOperationTests install-and-operations
        production_complete_uninstall
        capture_post_baseline
        compare_restored_baseline
        ;;
    all)
        runtime_mutation_attempted=1
        run_physical_package_tests PhysicalOperationTests install-and-operations
        run_physical_package_tests PhysicalUpgradeTests upgrade-rollback
        run_physical_ui_tests
        production_complete_uninstall
        capture_post_baseline
        compare_restored_baseline
        record_result cleanup.baseline-compare
        finalize_physical_results
        ;;
    *) die "unsupported physical phase: $phase" ;;
esac
