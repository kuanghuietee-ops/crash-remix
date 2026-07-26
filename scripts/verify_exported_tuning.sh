#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-/root/.local/share/godot/4.7.1/Godot_v4.7.1-stable_linux.x86_64}"
temp_dir="$(mktemp -d /tmp/crash-remix-export-tuning.XXXXXX)"
pack_path="$temp_dir/crash-remix-export.zip"
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

zipinfo -1 "$pack_path" >"$temp_dir/pack.list"
for level_meta_path in "$repo_root"/data/tuning/levels/*.tres; do
    grep -qFx "${level_meta_path#"$repo_root"/}.remap" "$temp_dir/pack.list"
done

GODOT_SILENCE_ROOT_WARNING=1 XDG_DATA_HOME="$temp_dir/user" "$godot_bin" \
    --headless \
    --main-pack "$pack_path" \
    -s res://src/debug/export_level_meta_smoke.gd 2>&1 | tee "$runtime_log"

if grep -qE "No loader found|Phase [0-9]+ tuning failed to load" "$runtime_log"; then
    echo "Exported build failed to load authored tuning resources" >&2
    exit 1
fi

grep -qE '^TUNING FINGERPRINT$' "$runtime_log"
grep -qE '^[0-9a-f]{64}$' "$runtime_log"
for tuning_path in gameplay move input camera depth wall_run grind swing phase economy enemy_crab enemy_skink enemy_plant; do
    grep -qE "^res://data/tuning/${tuning_path}\\.tres$" "$runtime_log"
done
grep -qE '^LEVEL META$' "$runtime_log"
grep -qE '^res://data/tuning/levels/n_sanity_beach\.tres$' "$runtime_log"
grep -qE '^FINGERPRINT [0-9a-f]{12}$' "$runtime_log"
grep -qE '^EXPORTED LEVEL META SMOKE READY$' "$runtime_log"

echo "Exported tuning smoke passed"
