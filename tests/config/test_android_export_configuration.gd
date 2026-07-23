extends GutTest

const EXPORT_PRESETS_PATH := "res://export_presets.cfg"


func test_android_debug_preset_is_runnable_and_reproducible() -> void:
	var config := ConfigFile.new()
	assert_eq(config.load(EXPORT_PRESETS_PATH), OK)
	assert_eq(config.get_value("preset.0", "name"), "Android Debug")
	assert_eq(config.get_value("preset.0", "platform"), "Android")
	assert_true(config.get_value("preset.0", "runnable", false))
	assert_eq(
		config.get_value("preset.0", "export_path"),
		"build/crash-remix-debug.apk"
	)
	var exclusions: String = config.get_value("preset.0", "exclude_filter", "")
	assert_string_contains(exclusions, "addons/gut/**")
	assert_string_contains(exclusions, "tests/**")


func test_android_preset_targets_arm64_and_requests_haptics() -> void:
	var config := ConfigFile.new()
	assert_eq(config.load(EXPORT_PRESETS_PATH), OK)
	assert_true(
		config.get_value("preset.0.options", "architectures/arm64-v8a", false)
	)
	assert_true(
		config.get_value("preset.0.options", "gradle_build/use_gradle_build", false)
	)
	assert_false(
		config.get_value("preset.0.options", "architectures/armeabi-v7a", true)
	)
	assert_true(config.get_value("preset.0.options", "permissions/vibrate", false))
	assert_eq(
		config.get_value("preset.0.options", "gradle_build/min_sdk"),
		"29"
	)
	assert_eq(
		config.get_value("preset.0.options", "gradle_build/target_sdk"),
		"35"
	)
	assert_eq(
		config.get_value("preset.0.options", "package/unique_name"),
		"com.personal.crashremix"
	)
	assert_eq(
		config.get_value("preset.0.options", "keystore/debug"),
		"build/debug.keystore"
	)
	assert_eq(
		config.get_value("preset.0.options", "keystore/debug_user"),
		"androiddebugkey"
	)


func test_android_build_has_a_repo_owned_placeholder_icon() -> void:
	var icon_path: String = ProjectSettings.get_setting("application/config/icon", "")
	assert_eq(icon_path, "res://assets/icon.svg")
	assert_true(FileAccess.file_exists(icon_path))
	var config := ConfigFile.new()
	assert_eq(config.load(EXPORT_PRESETS_PATH), OK)
	for key: String in [
		"launcher_icons/main_192x192",
		"launcher_icons/adaptive_background_432x432",
		"launcher_icons/adaptive_foreground_432x432",
		"launcher_icons/adaptive_monochrome_432x432",
	]:
		var path: String = config.get_value("preset.0.options", key, "")
		assert_false(path.is_empty())
		assert_true(FileAccess.file_exists(path))
