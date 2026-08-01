class_name SeatPoseTuning
extends Resource

## CTR R6 fix wave (operator device test): static seated-pose data for a
## mounted character model that has no seated-riding animation of its own --
## see kart_controller.gd's own SEAT_ANIMATION_CLIP doc: the lab assistant
## glb's only clip is A_lab_assistant_walk, an on-foot cycle, so mounting it
## left the model standing at its imported rest pose ("standing on the
## car"). kart_controller.gd's _apply_static_seat_pose() applies each field
## below directly via Skeleton3D.set_bone_pose_rotation() -- an ABSOLUTE
## pose target in the bone's own parent-relative space, the same space
## Godot's own animation rotation tracks write to, not a delta from rest.
##
## VALUES: both character rigs (SK_crash.glb, SK_lab_assistant.glb) share
## an identical bone hierarchy and identical rest-pose local rotations
## (confirmed by loading both headless and diffing their Skeleton3D dumps --
## only bone translations differ, matching each character's own height).
## That means Crash's own proven, art-directed A_crash_hog_ride clip already
## carries a correct seated pose in exactly the local-bone-space these
## fields need -- so every rotation below is that clip's own settled-frame
## value for the matching bone name, read once (Skeleton3D/AnimationPlayer,
## headless) and pinned here as a static table, never re-authored by hand
## and never touching the clip or either glb.
##
## This is visual rig data, not gameplay tuning -- kart_controller.gd reads
## it only to seat a non-animated character model, nothing here affects
## physics or scoring, so it deliberately sits outside GameplayTuning/
## TuningService's live-fingerprint catalog (no field here ever needs the
## "edit, redeploy, hash moves" proof CLAUDE.md's tuning-loop rule asks for
## from real gameplay numbers). Keeping the numeric literals in this .tres
## instead of a src/racing/** or src/gameplay/** constant is also what
## keeps scripts/lint_gameplay_numbers.py's numeric-literal ban from ever
## having to special-case a visual-only value -- this Resource class itself
## carries none.

@export_category("Hips")
@export var thigh_l_pose := Quaternion.IDENTITY
@export var thigh_r_pose := Quaternion.IDENTITY

@export_category("Knees")
@export var shin_l_pose := Quaternion.IDENTITY
@export var shin_r_pose := Quaternion.IDENTITY

@export_category("Arms")
@export var upper_arm_l_pose := Quaternion.IDENTITY
@export var upper_arm_r_pose := Quaternion.IDENTITY
@export var forearm_l_pose := Quaternion.IDENTITY
@export var forearm_r_pose := Quaternion.IDENTITY

@export_category("Seat Height")
## How far to lower the mounted character's own local Y position (SeatMount-
## relative) so the seated pose's pelvis sits down at the seat instead of
## floating at the character's full standing hip height -- see
## kart_controller.gd's own _apply_static_seat_pose() doc. Sized against the
## lab assistant rig's own standing pelvis height (its DEF-spine/DEF-pelvis.
## L/DEF-pelvis.R bones all share one rest origin, read the same headless
## way as the rotations above), leaving a small positive clearance so the
## pelvis reads as resting ON the seat, not sunk through it.
@export var pelvis_drop_m: float = 0.0
