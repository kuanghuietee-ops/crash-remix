class_name CrateBreakEffect
extends Node3D

const DEFAULT_SHARD_COLOR := Color(0.56, 0.27, 0.08, 1.0)
const SHARD_COLORS := {
	&"standard": DEFAULT_SHARD_COLOR,
	&"bounce": Color(0.05, 0.28, 0.82, 1.0),
	&"tnt": Color(0.78, 0.05, 0.025, 1.0),
	&"checkpoint": Color(0.08, 0.52, 0.18, 1.0),
	&"iron": Color(0.42, 0.48, 0.54, 1.0),
	&"aku": Color(0.94, 0.31, 0.04, 1.0),
	&"time": Color(0.04, 0.70, 0.82, 1.0),
}

@onready var _shards: GPUParticles3D = $Shards
@onready var _dust: GPUParticles3D = $Dust
@onready var _tnt_sparks: GPUParticles3D = $TntSparks


func _ready() -> void:
	reset()


func play(crate_type: StringName) -> void:
	visible = true
	var shard_process := (
		_shards.process_material as ParticleProcessMaterial
	)
	if shard_process != null:
		shard_process.color = SHARD_COLORS.get(
			crate_type,
			DEFAULT_SHARD_COLOR
		)
	_restart(_shards)
	_restart(_dust)
	_tnt_sparks.emitting = false
	if crate_type == &"tnt":
		_restart(_tnt_sparks)


func reset() -> void:
	visible = false
	for emitter: GPUParticles3D in [
		_shards,
		_dust,
		_tnt_sparks,
	]:
		emitter.emitting = false


func _restart(emitter: GPUParticles3D) -> void:
	emitter.emitting = true
	emitter.restart()
