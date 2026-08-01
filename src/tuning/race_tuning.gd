class_name RaceTuning
extends Resource

@export_category("Race")
@export var lap_count: float
@export var countdown_step_s: float
@export var start_boost_window_s: float
@export var start_bog_penalty_s: float
@export var wrong_way_grace_s: float
@export var checkpoint_tolerance_m: float
@export var respawn_drop_height_m: float

@export_category("Camera")
@export var camera_trail_m: float
@export var camera_height_m: float
@export var camera_fov_base: float
@export var camera_fov_speed_gain: float
@export var camera_yaw_lag_s: float
@export var camera_drift_yaw_degrees: float
# Task 5 (CTR kart chase camera): KartCamera's look-at target is the kart
# position raised by this much, so the camera aims a little above the
# kart's origin (roughly cockpit/roof height) instead of dead-level into
# its base -- kept as its own field rather than reusing camera_height_m (a
# fraction of the camera's OWN mount height above ground has no reason to
# equal a good look-at height above the kart) so each stays independently
# tunable.
@export var camera_look_height_m: float

# Task 1 (CTR R7, discharges spec debt #2): track-authored BoostPad/JumpPad
# Area3D triggers (src/racing/track/boost_pad.gd, jump_pad.gd) read these
# three -- see race_session.gd's own PAD WIRING doc for how they reach a
# kart. pad_boost_s/pad_refire_cooldown_s feed BoostPad.configure() (the
# same "seconds" shape KartController.apply_boost() already takes);
# jump_pad_velocity_scale feeds JumpPad.configure() (KartMotor.launch()'s
# own scale multiplier on the hop kinematic identity -- see that method's
# doc for why a SCALE, not a raw m/s value, is the right shape here).
@export_category("Pads")
@export var pad_boost_s: float
@export var pad_refire_cooldown_s: float
@export var jump_pad_velocity_scale: float

# Task 5 (CTR R7, the Cup): points CupSession (src/racing/flow/cup_session.gd)
# awards for each of a race's 6 finishing placements -- 1st through 6th,
# matching the fixed field size a cup race always has (player + AiTuning.
# opponent_count == 5). Godot tuning fields are scalars by established
# precedent (no per-place array/table field exists anywhere else in this
# catalog), so this is 6 individually-registered fields rather than one
# Array[float] field -- see tuning_service.gd's own LEGACY_FIELD_GROUPS_BY_
# SECTION &"race" cohort for how all six migrate together as one unit.
# Defaults: 8/6/5/4/3/2, a standard top-6 kart-racer points table.
@export_category("Cup")
@export var cup_points_place1: float
@export var cup_points_place2: float
@export var cup_points_place3: float
@export var cup_points_place4: float
@export var cup_points_place5: float
@export var cup_points_place6: float

# Task 6 (CTR R7, stretch: time-trial ghost): ghost_recorder.gd samples the
# player kart's own global transform (position + a derived yaw -- see its
# own class doc) every ghost_keyframe_interval_s of real, pause-correct
# race-elapsed time (the same _elapsed_s clock RaceSession already ticks
# from GO, see race_session.gd's own TIMER section) during solo sessions
# only. A race is minutes long, not hours -- ghost_max_keyframes is a hard
# ceiling on how many keyframes a single .ghost file can ever hold (float,
# COUNT semantics, the same "float field, int use" shape lap_count already
# establishes -- see tuning_service.gd's own lap_count-below-one rejection
# for why a fractional count is dangerous, not just a zero one), so a
# pathologically long or stuck solo run cannot grow an unbounded recording
# or an unbounded .ghost file. 3600.0 at the authored 0.1s interval is
# exactly six minutes of keyframes -- comfortably above any real solo lap
# time this game authors.
@export_category("Ghost")
@export var ghost_keyframe_interval_s: float
@export var ghost_max_keyframes: float
