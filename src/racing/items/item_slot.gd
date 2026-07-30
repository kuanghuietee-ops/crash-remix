class_name ItemSlot
extends RefCounted

## Pure per-kart item-roulette state machine (R4 Task 3, CTR item loop).
## Poll model, no signals -- mirrors drift_state_machine.gd's/lap_validator.
## gd's idiom: a caller pushes an edge (start_roll), calls tick(delta_s)
## once per physics frame, and reads state back through getters.
##
## STATES (StringName, read via state()): &"empty" -- no roll in progress,
## nothing held; &"rolling" -- the roulette animation is running toward a
## held item; &"held" -- an item is ready, waiting for use(). There is no
## separate "using" state: use() is a single atomic call (returns the held
## item and clears back to &"empty" in the same call), not something that
## ticks over multiple frames -- Task 4 owns whatever multi-frame effect an
## item spawns after use() hands it the name.
##
## RNG INJECTION. start_roll(rng_value: float) takes the random draw as a
## parameter instead of calling RandomNumberGenerator itself, for the same
## reason every other pure-logic class in src/racing/** takes delta_s/
## steer/rng as parameters rather than reading a live singleton or wall
## clock: headless determinism. A GUT test can feed an exact rng_value and
## get an exact, reproducible item -- no seeding a global RNG and hoping
## call order lines up. The CALLER owns the actual randomness source:
## RaceSession (race_session.gd) owns one seeded RandomNumberGenerator per
## race and calls start_roll(rng.randf()) once per box pickup, for both the
## player's and every AI kart's own slot (see race_session.gd's own class
## doc for the seeding contract -- that is this class's Task 3 wiring).
##
## FOUR-WAY MAPPING. rng_value is expected in [0, 1) (RandomNumberGenerator.
## randf()'s own documented range); ITEM_NAMES.size() (not a bare literal --
## this file's own no-bare-numeric-literal rule) items are mapped to
## uniformly-sized [i/n, (i+1)/n) buckets via floor(rng_value * n). A
## caller-supplied rng_value of exactly 1.0 (out of randf()'s own range, but
## this method stays a pure function of its input rather than validating
## it) would floor to exactly n, one past the last valid index -- clamped
## back to the last item instead of indexing out of bounds; a negative
## rng_value clamps symmetrically to the first item.
##
## start_roll() is a no-op unless the slot is currently &"empty" -- a second
## box pickup while already rolling or holding must not restart the
## roulette or overwrite an already-decided item.

const ITEM_NAMES: Array[StringName] = [&"missile", &"shield", &"turbo", &"beaker"]

var _tuning: ItemTuning
var _state: StringName = &"empty"
var _elapsed_s: float
var _held_item: StringName = &"none"


func configure(item_tuning: ItemTuning) -> void:
	_tuning = item_tuning


func state() -> StringName:
	return _state


## See the class doc's RNG INJECTION and FOUR-WAY MAPPING sections. Ignored
## (no-op) unless the slot is currently &"empty".
func start_roll(rng_value: float) -> void:
	if _state != &"empty":
		return
	_held_item = _item_for_rng(rng_value)
	_state = &"rolling"
	_elapsed_s = 0.0


## Advances a &"rolling" slot toward &"held" once roulette_duration_s has
## elapsed. A no-op in every other state (&"empty" has nothing to advance;
## &"held" is already done and waits on use()) and while unconfigured (no
## tuning to measure the duration against).
func tick(delta_s: float) -> void:
	if _state != &"rolling":
		return
	_elapsed_s += delta_s
	if _tuning != null and _elapsed_s >= _tuning.roulette_duration_s:
		_state = &"held"


## The item the roulette HUD should flicker to right now, while &"rolling"
## -- cycles through every ITEM_NAMES entry every roulette_tick_s, purely as
## a function of _elapsed_s (the same "derived from accumulated tick time,
## not a live wall clock" determinism every other tick() consumer in this
## repo relies on). &"none" outside &"rolling": there is nothing to flicker
## once the roll has landed on &"held" (held_item() takes over from there)
## or before it has started (&"empty").
func rolling_display_item() -> StringName:
	if _state != &"rolling":
		return &"none"
	if _tuning == null or _tuning.roulette_tick_s <= 0.0:
		return ITEM_NAMES[0]
	var tick_index := int(_elapsed_s / _tuning.roulette_tick_s)
	return ITEM_NAMES[tick_index % ITEM_NAMES.size()]


## &"missile"/&"shield"/&"turbo"/&"beaker" once the roll has landed;
## &"none" in every other state (still rolling, or already used and back to
## &"empty").
func held_item() -> StringName:
	return _held_item if _state == &"held" else &"none"


## Returns-and-clears: hands back the held item and resets to &"empty" in
## the same call, so a second use() (or a use() while &"empty"/&"rolling")
## always reads &"none" rather than handing out the same item twice.
func use() -> StringName:
	if _state != &"held":
		return &"none"
	var item := _held_item
	_held_item = &"none"
	_state = &"empty"
	return item


func _item_for_rng(rng_value: float) -> StringName:
	var count := ITEM_NAMES.size()
	var index := int(floor(rng_value * float(count)))
	index = clampi(index, 0, count - 1)
	return ITEM_NAMES[index]
