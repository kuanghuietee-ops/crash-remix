#!/usr/bin/env bash
set -euo pipefail

default_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="${CRASH_REMIX_REPO_ROOT:-$default_repo_root}"
godot_bin="${GODOT_BIN:-/root/.local/share/godot/4.7.1/Godot_v4.7.1-stable_linux.x86_64}"
adb_bin="${ADB_BIN:-/root/.local/share/android-sdk/platform-tools/adb}"
templates_dir="${GODOT_EXPORT_TEMPLATES_DIR:-/root/.local/share/godot/export_templates/4.7.1.stable}"
android_template_zip="$templates_dir/android_source.zip"
android_build_dir="$repo_root/android/build"
android_version_marker="$repo_root/android/.build_version"
godot_template_identifier="4.7.1.stable"
apk_path="$repo_root/build/crash-remix-debug.apk"
debug_keystore="$repo_root/build/debug.keystore"
debug_keystore_seed="${DEBUG_KEYSTORE_SEED:-$default_repo_root/scripts/android_debug_keystore.b64}"
debug_keystore_sha256="3926b1f9d7403e4067f3e062801c4d90ac5490132819893cc18075462d1a8aa9"
package_name="com.personal.crashremix"
build_only=false
requested_serial="${ANDROID_SERIAL:-}"

usage() {
    echo "Usage: scripts/deploy_android.sh [--build-only] [--serial DEVICE_SERIAL]"
}

while (($# > 0)); do
    case "$1" in
        --build-only)
            build_only=true
            shift
            ;;
        --serial)
            if (($# < 2)); then
                usage
                exit 2
            fi
            requested_serial="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ ! -x "$godot_bin" ]]; then
    echo "Godot 4.7.1 executable not found: $godot_bin" >&2
    echo "Set GODOT_BIN to the pinned Godot executable." >&2
    exit 1
fi

if [[ ! -f "$android_build_dir/build.gradle" ]]; then
    if [[ ! -f "$android_template_zip" ]]; then
        echo "Godot Android Gradle template not found: $android_template_zip" >&2
        echo "Install the matching 4.7.1 Android export templates." >&2
        exit 1
    fi
    if ! command -v unzip >/dev/null; then
        echo "unzip is required to install the Android Gradle template." >&2
        exit 1
    fi
    mkdir -p "$android_build_dir"
    unzip -q "$android_template_zip" -d "$android_build_dir"
    chmod +x "$android_build_dir/gradlew"
    echo "Installed the Godot 4.7.1 Android Gradle template."
fi

# Godot's editor writes this next to the extracted template. Headless export
# rejects Gradle templates without the matching identifier.
printf '%s\n' "$godot_template_identifier" > "$android_version_marker"

mkdir -p "$repo_root/build"
if [[ ! -f "$debug_keystore" ]]; then
    if [[ ! -f "$debug_keystore_seed" ]]; then
        echo "Repository-owned debug keystore seed not found: $debug_keystore_seed" >&2
        exit 1
    fi
    if ! command -v base64 >/dev/null; then
        echo "base64 is required to restore the stable debug keystore." >&2
        exit 1
    fi
    base64 --decode "$debug_keystore_seed" > "$debug_keystore"
    echo "Restored repository-pinned debug keystore at $debug_keystore"
fi
if ! command -v sha256sum >/dev/null; then
    echo "sha256sum is required to verify the stable debug keystore." >&2
    exit 1
fi
actual_keystore_sha256="$(sha256sum "$debug_keystore" | awk '{print $1}')"
if [[ "$actual_keystore_sha256" != "$debug_keystore_sha256" ]]; then
    echo "Refusing to sign with an unpinned debug certificate: $debug_keystore" >&2
    echo "Expected SHA-256: $debug_keystore_sha256" >&2
    echo "Actual SHA-256:   $actual_keystore_sha256" >&2
    exit 1
fi
"$godot_bin" --headless --path "$repo_root" --export-debug "Android Debug" "$apk_path"

if [[ ! -s "$apk_path" ]]; then
    echo "Android export did not create $apk_path" >&2
    exit 1
fi

echo "Built $apk_path"
if [[ "$build_only" == true ]]; then
    exit 0
fi

if [[ ! -x "$adb_bin" ]]; then
    echo "adb not found: $adb_bin" >&2
    echo "Set ADB_BIN to the Android SDK platform-tools adb executable." >&2
    exit 1
fi

serial="$requested_serial"
if [[ -z "$serial" ]]; then
    mapfile -t devices < <("$adb_bin" devices | awk '$2 == "device" {print $1}')
    if ((${#devices[@]} == 0)); then
        echo "No authorized Android device found. Connect one or pass --build-only." >&2
        exit 1
    fi
    if ((${#devices[@]} > 1)); then
        echo "Multiple Android devices found; pass --serial DEVICE_SERIAL." >&2
        printf '  %s\n' "${devices[@]}" >&2
        exit 1
    fi
    serial="${devices[0]}"
fi

if ! install_output="$("$adb_bin" -s "$serial" install -r "$apk_path" 2>&1)"; then
    printf '%s\n' "$install_output" >&2
    if [[ "$install_output" == *"INSTALL_FAILED_UPDATE_INCOMPATIBLE"* ]]; then
        echo "Certificate mismatch: Android rejected the in-place update." >&2
        echo "Do not uninstall $package_name: uninstalling destroys app data," >&2
        echo "including user://tuning/override.tres. Back up device data first." >&2
    fi
    exit 1
fi
if [[ -n "$install_output" ]]; then
    printf '%s\n' "$install_output"
fi
"$adb_bin" -s "$serial" shell am force-stop "$package_name"
"$adb_bin" -s "$serial" shell monkey -p "$package_name" -c android.intent.category.LAUNCHER 1
echo "Installed and launched $package_name on $serial"
