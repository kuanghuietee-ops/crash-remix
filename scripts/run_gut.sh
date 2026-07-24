#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-/root/.local/share/godot/4.7.1/Godot_v4.7.1-stable_linux.x86_64}"
test_user_root="$(mktemp -d /tmp/crash-remix-gut-user.XXXXXX)"

cleanup() {
    rm -rf -- "$test_user_root"
}
trap cleanup EXIT HUP INT TERM

XDG_DATA_HOME="$test_user_root" "$godot_bin" \
    --headless \
    --path "$repo_root" \
    -s addons/gut/gut_cmdln.gd \
    -gexit \
    "$@"
