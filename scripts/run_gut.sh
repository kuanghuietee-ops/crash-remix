#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-/root/.local/share/godot/4.7.1/Godot_v4.7.1-stable_linux.x86_64}"
test_user_roots=()
# These suites repeatedly instantiate and tear down the real main scene. Keeping
# each in its own process prevents ResourceLoader/renderer state from leaking
# across suites while preserving GUT's strict unexpected-engine-error capture.
isolated_suites=(
    "res://tests/integration/test_main_boot.gd"
    "res://tests/integration/test_island_slice.gd"
    "res://tests/integration/test_warp_room.gd"
    "res://tests/integration/test_cup_flow_e2e.gd"
    "res://tests/integration/test_r8_papu_cup_reload_e2e.gd"
)

cleanup() {
    local test_user_root
    for test_user_root in "${test_user_roots[@]}"; do
        rm -rf -- "$test_user_root"
    done
}
trap cleanup EXIT HUP INT TERM

run_gut_process() {
    local test_user_root
    test_user_root="$(mktemp -d /tmp/crash-remix-gut-user.XXXXXX)"
    test_user_roots+=("$test_user_root")

    XDG_DATA_HOME="$test_user_root" "$godot_bin" \
        --headless \
        --disable-render-loop \
        --path "$repo_root" \
        -s addons/gut/gut_cmdln.gd \
        -gexit \
        "$@"
}

is_isolated_suite() {
    local candidate="$1"
    local isolated_suite
    for isolated_suite in "${isolated_suites[@]}"; do
        if [[ "$candidate" == "$isolated_suite" ]]; then
            return 0
        fi
    done
    return 1
}

if (( $# > 0 )); then
    run_gut_process "$@"
    exit
fi

shared_process_suites=()
while IFS= read -r test_file; do
    test_path="res://${test_file#"$repo_root"/}"
    if ! is_isolated_suite "$test_path"; then
        shared_process_suites+=("$test_path")
    fi
done < <(find "$repo_root/tests" -type f -name 'test_*.gd' -print | sort)

for isolated_suite in "${isolated_suites[@]}"; do
    if [[ ! -f "$repo_root/${isolated_suite#res://}" ]]; then
        echo "Missing isolated GUT suite: $isolated_suite" >&2
        exit 1
    fi
done

shared_process_test_list="$(
    IFS=,
    printf '%s' "${shared_process_suites[*]}"
)"
overall_status=0
if ! run_gut_process -gdir= "-gtest=$shared_process_test_list"; then
    overall_status=1
fi

for isolated_suite in "${isolated_suites[@]}"; do
    if ! run_gut_process -gdir= "-gtest=$isolated_suite"; then
        overall_status=1
    fi
done

exit "$overall_status"
