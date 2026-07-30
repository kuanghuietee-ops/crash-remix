extends GutTest

# Task 6 (CTR racing mode): CheckpointGate is a passive Area3D data carrier
# (gate_index only) -- Task 7's race session owns connecting body_entered
# and forwarding crossings to a LapValidator, the same way camera_region.gd
# stays passive and lets camera_rail_controller.gd own the wiring. This
# suite only covers what the script itself is responsible for: carrying the
# index and forcing sane monitoring defaults (see checkpoint_gate.gd's
# class doc) -- not the Task 7 session wiring, which doesn't exist yet.

const GATE_PATH := "res://src/racing/track/checkpoint_gate.gd"


func test_gate_index_round_trips_through_the_export() -> void:
	var gate: Area3D = load(GATE_PATH).new()
	gate.set(&"gate_index", 3)
	add_child_autofree(gate)

	assert_eq(gate.get(&"gate_index"), 3)


func test_gate_forces_monitoring_on_and_monitorable_off() -> void:
	# A checkpoint only ever needs to detect the kart passing through it --
	# never to be detected BY another Area3D -- so _ready() must force
	# these regardless of whatever a scene author leaves them set to.
	var gate: Area3D = load(GATE_PATH).new()
	gate.monitoring = false
	gate.monitorable = true
	add_child_autofree(gate)

	assert_true(gate.monitoring, "_ready() must force monitoring on")
	assert_false(gate.monitorable, "_ready() must force monitorable off")
