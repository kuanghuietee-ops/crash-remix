#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-/root/.local/share/godot/4.7.1/Godot_v4.7.1-stable_linux.x86_64}"
temp_dir="$(mktemp -d /tmp/crash-remix-export-tuning.XXXXXX)"
pack_path="$temp_dir/crash-remix-export.pck"
export_log="$temp_dir/export.log"
runtime_log="$temp_dir/runtime.log"

cleanup() {
    if [[ "$temp_dir" == /tmp/crash-remix-export-tuning.* ]]; then
        rm -r -- "$temp_dir"
    fi
}
trap cleanup EXIT

if [[ ! -x "$godot_bin" ]]; then
    echo "Godot executable not found: $godot_bin" >&2
    exit 1
fi

if ! GODOT_SILENCE_ROOT_WARNING=1 "$godot_bin" \
    --headless \
    --path "$repo_root" \
    --export-pack "Android Debug" \
    "$pack_path" >"$export_log" 2>&1; then
    cat "$export_log" >&2
    exit 1
fi

GODOT_SILENCE_ROOT_WARNING=1 "$godot_bin" \
    --headless \
    --main-pack "$pack_path" \
    --quit-after 3 2>&1 | tee "$runtime_log"

if grep -qE "No loader found|Phase 0 tuning failed to load" "$runtime_log"; then
    echo "Exported build failed to load authored tuning resources" >&2
    exit 1
fi

grep -qE '^TUNING FINGERPRINT$' "$runtime_log"
grep -qE '^[0-9a-f]{64}$' "$runtime_log"
for tuning_path in gameplay move input camera depth wall_run grind swing phase; do
    grep -qE "^res://data/tuning/${tuning_path}\\.tres$" "$runtime_log"
done

echo "Exported tuning smoke passed"
