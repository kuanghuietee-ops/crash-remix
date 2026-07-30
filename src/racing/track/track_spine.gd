class_name TrackSpine
extends Path3D

## Closed-loop rail for a race circuit (Task 6). Builds its Curve3D from
## Marker3D children via the shared RailCurveBuilder (see rail_curve_
## builder.gd) with closed=true, so the baked curve actually returns to its
## start instead of dead-ending at the last marker.
##
## TUNING. RailCurveBuilder's shaping needs a bake interval and a handle-
## length factor -- the same two knobs CameraTuning already carries for the
## platformer's rails (rail_bake_interval_m, rail_handle_length_factor).
## Racing has no equivalent of the platformer's tuning-catalog autoload (see
## camera_rail_controller.gd/traversal_rail.gd): every racing node instead
## gets its tuning handed to it explicitly by whatever session owns it (see
## kart_camera.gd, kart_controller.gd's configure() calls). TrackSpine
## follows that same shape: configure(camera_tuning) is how Task 7's race
## session hands it real values. Until that happens -- including the very
## first _ready() frame, which always runs before a session has had a
## chance to call configure() -- it falls back to bake_interval_m=0.0,
## handle_length_factor=0.0 (RailCurveBuilder's own "no shaping" values),
## which bakes a plain straight-line polyline through the authored markers
## instead of leaving the curve unbuilt.
##
## Mirrors camera_rail_controller.gd's _ensure_curve_from_markers guard: the
## curve is only rebuilt when the tuning-derived bake interval or handle
## factor actually changed, so a live tuning edit reshapes the spine without
## redoing the work every single frame.

const RailCurveBuilderType := preload(
	"res://src/gameplay/common/rail_curve_builder.gd"
)

var _camera_tuning: CameraTuning
var _curve_built: bool
var _curve_bake_interval_m := -1.0
var _curve_handle_length_factor := -1.0


func _ready() -> void:
	_ensure_curve()


func configure(camera_tuning: CameraTuning) -> void:
	_camera_tuning = camera_tuning
	_ensure_curve()


func length_m() -> float:
	_ensure_curve()
	return curve.get_baked_length() if curve != null else 0.0


## Closest offset along the spine to a world-space position -- the standard
## "how far around the lap is this point" projection every caller (HUD
## progress, wrong-way checks, AI) needs.
func progress_for_position(global_pos: Vector3) -> float:
	_ensure_curve()
	if curve == null or curve.point_count < 1:
		return 0.0
	return curve.get_closest_offset(to_local(global_pos))


## World-space forward direction of travel at a given distance along the
## spine, via a small forward/backward finite difference -- the same
## approach traversal_rail.gd/wall_run_strip.gd use for their own tangents,
## stepped by the curve's own bake interval so the sample spacing always
## matches how finely the curve was actually baked.
func tangent_at_progress(progress_m: float) -> Vector3:
	_ensure_curve()
	if curve == null or curve.point_count < 1:
		return Vector3.ZERO
	var length := curve.get_baked_length()
	if length <= 0.0:
		return Vector3.ZERO
	var clamped := clampf(progress_m, 0.0, length)
	var step := curve.bake_interval
	if step <= 0.0:
		step = length
	var before := maxf(clamped - step, 0.0)
	var after := minf(clamped + step, length)
	var local_tangent := curve.sample_baked(after) - curve.sample_baked(before)
	if local_tangent.is_zero_approx():
		return Vector3.ZERO
	return (global_basis * local_tangent).normalized()


## True when velocity points backward along the spine at this progress --
## an instantaneous, stateless check. The caller (Task 7's race session)
## owns sustaining this across wrong_way_grace_s before raising the HUD
## warning; TrackSpine only ever answers "right now, which way".
func is_wrong_way(velocity: Vector3, progress_m: float) -> bool:
	var tangent := tangent_at_progress(progress_m)
	if tangent.is_zero_approx():
		return false
	return velocity.dot(tangent) < 0.0


func _ensure_curve() -> void:
	var has_markers := false
	for child: Node in get_children():
		if child is Marker3D:
			has_markers = true
			break
	if not has_markers:
		# A marker-less spine carries a scene-authored curve (or none at
		# all) -- there is nothing here for the builder to rebuild from.
		return
	var bake_interval_m := 0.0
	var handle_length_factor := 0.0
	if _camera_tuning != null:
		bake_interval_m = _camera_tuning.rail_bake_interval_m
		handle_length_factor = _camera_tuning.rail_handle_length_factor
	if (
		_curve_built
		and curve != null
		and curve.point_count > 0
		and is_equal_approx(bake_interval_m, _curve_bake_interval_m)
		and is_equal_approx(
			handle_length_factor,
			_curve_handle_length_factor
		)
	):
		# Already built from these exact tuning-derived params -- rebuilding
		# again would be wasted work, not a correctness fix.
		return
	curve = RailCurveBuilderType.curve_from_markers(
		self,
		bake_interval_m,
		handle_length_factor,
		true
	)
	_curve_built = true
	_curve_bake_interval_m = bake_interval_m
	_curve_handle_length_factor = handle_length_factor
