class_name AudioService
extends Node

## Named SFX slots resolved from `assets/audio/`. The slots are deliberately
## empty: 01-DESIGN's H10 reserves every byte of audio for the operator, and no
## agent may generate any. Until then this service exists so the call sites can
## be wired, reviewed and tested against silence rather than added later in a
## rush -- and so a missing file is silence, never an error.

const SLOT_CRATE_POP := &"crate_pop"
const SLOT_WUMPA := &"wumpa"
const SLOT_JUMP := &"jump"
const SLOT_DOUBLE_JUMP := &"double_jump"
const SLOT_SPIN := &"spin"
const SLOT_TNT_TICK := &"tnt_tick"
const SLOT_MASK := &"mask"
const SLOT_DEATH := &"death"
const SLOT_CHECKPOINT_GONG := &"checkpoint_gong"

const SLOT_NAMES: Array[StringName] = [
	SLOT_CRATE_POP,
	SLOT_WUMPA,
	SLOT_JUMP,
	SLOT_DOUBLE_JUMP,
	SLOT_SPIN,
	SLOT_TNT_TICK,
	SLOT_MASK,
	SLOT_DEATH,
	SLOT_CHECKPOINT_GONG,
]
const CLIP_EXTENSION := ".wav"

var _audio_dir := ""
var _boot_report := ""


func configure(audio_dir: String) -> void:
	_audio_dir = audio_dir
	var missing: Array[String] = []
	for slot: StringName in SLOT_NAMES:
		if not has_clip(slot):
			missing.append(String(slot))
	# One line, at boot, once. A silent game must not narrate every crate.
	_boot_report = (
		"AudioService: %d of %d slots have no clip yet (%s)"
		% [missing.size(), SLOT_NAMES.size(), ", ".join(missing)]
		if not missing.is_empty()
		else "AudioService: all %d slots resolved" % SLOT_NAMES.size()
	)
	print(_boot_report)


func boot_report() -> String:
	return _boot_report


func clip_path_for(slot: StringName) -> String:
	if not SLOT_NAMES.has(slot) or _audio_dir.is_empty():
		return ""
	return _audio_dir.path_join(String(slot) + CLIP_EXTENSION)


func has_clip(slot: StringName) -> bool:
	var path := clip_path_for(slot)
	if path.is_empty():
		return false
	return ResourceLoader.exists(path)


## Returns whether anything actually played. False is a normal, silent outcome
## until H10 delivers the clips -- never an error and never a log line.
func play(slot: StringName) -> bool:
	if not has_clip(slot):
		return false
	var stream := load(clip_path_for(slot)) as AudioStream
	if stream == null:
		return false
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	return true
