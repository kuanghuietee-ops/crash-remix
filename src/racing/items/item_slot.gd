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
## item and clears back to &"empty" in the same call, EXCEPT for a charge-
## bearing item -- see the CHARGES section below), not something that ticks
## over multiple frames -- Task 4 owns whatever multi-frame effect an item
## spawns after use() hands it the name.
##
## RNG INJECTION. start_roll(rng_value: float, position_ratio: float = -1.0)
## takes the random draw as a parameter instead of calling
## RandomNumberGenerator itself, for the same reason every other pure-logic
## class in src/racing/** takes delta_s/steer/rng as parameters rather than
## reading a live singleton or wall clock: headless determinism. A GUT test
## can feed an exact rng_value (and, since CTR R6 Task 5, an exact
## position_ratio) and get an exact, reproducible item -- no seeding a global
## RNG and hoping call order lines up. The CALLER owns the actual randomness
## source: RaceSession (race_session.gd) owns one seeded
## RandomNumberGenerator per race and calls start_roll(rng.randf(), ratio)
## once per box pickup, for both the player's and every AI kart's own slot
## (see race_session.gd's own class doc for the seeding contract, and its
## _position_ratio_for() doc for where the ratio argument comes from).
##
## N-WAY UNIFORM MAPPING (position_ratio omitted or negative -- the default).
## rng_value is expected in [0, 1) (RandomNumberGenerator.randf()'s own
## documented range); ITEM_NAMES.size() (not a bare literal -- this file's
## own no-bare-numeric-literal rule) items are mapped to uniformly-sized
## [i/n, (i+1)/n) buckets via floor(rng_value * n). A caller-supplied
## rng_value of exactly 1.0 (out of randf()'s own range, but this method
## stays a pure function of its input rather than validating it) would floor
## to exactly n, one past the last valid index -- clamped back to the last
## item instead of indexing out of bounds; a negative rng_value clamps
## symmetrically to the first item. This is the ONLY mapping every pre-Task-5
## caller (and every test in this suite that never passes a ratio) ever sees,
## unchanged in SHAPE from R4 Task 3's own four-way version -- only n itself
## grew (four items then, seven now that bomb/tnt_stick/triple_turbo exist),
## so the exact rng-to-item boundaries shifted; see test_item_slot.gd's own
## updated boundary tests.
##
## WEIGHTED MAPPING (CTR R6 Task 5, position_ratio in [0.0, 1.0]). Per-item
## weights replace the uniform 1/n buckets: ItemTuning carries one (front,
## back) pair per ITEM_NAMES entry, named weight_front_<item_name>/
## weight_back_<item_name> exactly (see item_tuning.gd's own ROULETTE
## WEIGHTS doc) -- looked up generically here via Object.get() rather than a
## hardcoded per-item match, so a future ITEM_NAMES entry only ever needs its
## two tuning fields added, never a matching branch in this file. This
## kart's own live blended weight is
## `(1.0 - position_ratio) * weight_front + position_ratio * weight_back`
## (0.0 = the race leader, pure front; 1.0 = last place, pure back; anything
## in between a straight linear blend). The roll itself is a cumulative-
## table lookup: bucket boundaries are each item's own running weight total
## (not equal 1/n slices), and rng_value * total_weight is compared against
## them the same "first bucket whose cumulative total exceeds the target
## wins" way the uniform path's own floor() division is EQUIVALENT to (see
## _item_for_rng()'s own doc for the proof) -- one shared algorithm serves
## both mappings, uniform weights [1.0, 1.0, ...] for the N-WAY case above
## and tuning-derived weights for this one.
##
## start_roll() is a no-op unless the slot is currently &"empty" -- a second
## box pickup while already rolling or holding must not restart the
## roulette or overwrite an already-decided item.
##
## CHARGES (CTR R6 Task 5). Every item defaults to exactly one charge
## (single-use, R4's original shape, unchanged): use() hands back the held
## item and clears the slot to &"empty" in the same call. &"triple_turbo" is
## the one exception -- held_item() keeps reporting &"triple_turbo" across
## up to ItemTuning.triple_turbo_charges consecutive use() calls (one turbo
## boost dispatched per call, see race_session.gd's own dispatch_item_use()
## doc), only clearing back to &"empty" once the LAST charge is consumed.
## charges_remaining() exposes the count still left on the currently-held
## item (0 outside &"held", mirroring held_item()'s own state-gated
## contract) -- a caller like RaceHUD reads this to show "TRIPLE TURBO x2"
## instead of just "TRIPLE TURBO" with no indication more than one use
## remains. The charge count is decided at the SAME instant the item itself
## is (start_roll(), not tick() landing or use()) -- consistent with
## _held_item's own "decided at the rng draw, merely hidden until &"held""
## timing (see held_item()'s own doc) -- so a charge-bearing item's full
## remaining-uses count is already fixed the moment the roulette starts,
## exactly like which item it is.

const ITEM_NAMES: Array[StringName] = [
	&"missile",
	&"shield",
	&"turbo",
	&"beaker",
	&"bomb",
	&"tnt_stick",
	&"triple_turbo",
]

## The one item name that carries more than a single charge -- see the class
## doc's own CHARGES section. Every other name in ITEM_NAMES gets exactly
## ONE charge, unconditionally.
const CHARGE_ITEM_NAME := &"triple_turbo"

var _tuning: ItemTuning
var _state: StringName = &"empty"
var _elapsed_s: float
var _held_item: StringName = &"none"
var _charges_remaining: int = 0


func configure(item_tuning: ItemTuning) -> void:
	_tuning = item_tuning


func state() -> StringName:
	return _state


## See the class doc's RNG INJECTION, N-WAY UNIFORM MAPPING, and WEIGHTED
## MAPPING sections. Ignored (no-op) unless the slot is currently &"empty".
## position_ratio defaults to -1.0 (out of the valid [0.0, 1.0] range) --
## the sentinel meaning "no live position known, use the plain uniform
## mapping" every pre-Task-5 caller (and every test that never passes one)
## relies on; RaceSession's own real box-pickup path always supplies a real
## ratio (see its own _position_ratio_for() doc) once a race actually has a
## field to rank within.
func start_roll(rng_value: float, position_ratio: float = -1.0) -> void:
	if _state != &"empty":
		return
	_held_item = _item_for_rng(rng_value, position_ratio)
	_charges_remaining = (
		roundi(_tuning.triple_turbo_charges)
		if _tuning != null and _held_item == CHARGE_ITEM_NAME
		else 1
	)
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


## Any ITEM_NAMES entry once the roll has landed; &"none" in every other
## state (still rolling, or already used down to zero charges and back to
## &"empty").
func held_item() -> StringName:
	return _held_item if _state == &"held" else &"none"


## See the class doc's CHARGES section. 0 outside &"held" (mirrors held_
## item()'s own state-gated contract) -- otherwise the held item's own
## remaining-use count, 1 for every ordinary single-use item and up to
## ItemTuning.triple_turbo_charges for &"triple_turbo".
func charges_remaining() -> int:
	return _charges_remaining if _state == &"held" else 0


## Returns-and-clears for an ordinary (one-charge) item: hands back the held
## item and resets to &"empty" in the same call, so a second use() (or a
## use() while &"empty"/&"rolling") always reads &"none" rather than handing
## out the same item twice. For CHARGE_ITEM_NAME specifically (see the class
## doc's CHARGES section), this instead decrements _charges_remaining by
## exactly one and keeps reporting &"held"/&"triple_turbo" until that
## decrement reaches zero -- only THEN does the slot clear to &"empty" the
## same way every other item's very first use() already does. Every call
## still returns the item name itself (never &"none") as long as a charge
## was actually consumed, so the CALLER (race_session.gd's dispatch_item_
## use()) applies one turbo boost per call regardless of which charge this
## was -- the multi-charge bookkeeping is entirely internal to this slot.
func use() -> StringName:
	if _state != &"held":
		return &"none"
	var item := _held_item
	if item == CHARGE_ITEM_NAME and _charges_remaining > 1:
		_charges_remaining -= 1
		return item
	_held_item = &"none"
	_state = &"empty"
	_charges_remaining = 0
	return item


## Shared cumulative-weighted-table lookup for BOTH the N-WAY UNIFORM and
## WEIGHTED mappings (see the class doc's own sections for the exact
## formulas) -- built once here rather than as two separate code paths, so
## the boundary-clamp behavior (rng_value >= 1.0 clamps to the last item,
## rng_value < 0.0 clamps to the first) only has to be proven correct once.
## PROOF OF EQUIVALENCE to the old bare floor(rng_value * n) formula when
## every weight is equal (the N-WAY case): with n equal weights w, the total
## is n*w and item i's own cumulative upper bound is (i+1)*w = ((i+1)/n) *
## total: the loop below picks the first i where
## rng_value*total < (i+1)*w, i.e. rng_value*n < i+1, i.e. i > rng_value*n -
## 1, i.e. the smallest integer i satisfying that is floor(rng_value*n) --
## the exact prior formula, so every pre-Task-5 boundary contract (negative
## clamps to first, exactly 1.0 clamps to last) still holds under this one
## shared algorithm.
func _item_for_rng(rng_value: float, position_ratio: float = -1.0) -> StringName:
	var weights := _weights_for_ratio(position_ratio)
	var total_weight := 0.0
	for weight: float in weights:
		total_weight += weight
	var target := rng_value * total_weight
	var cumulative := 0.0
	for index in range(weights.size()):
		cumulative += weights[index]
		if target < cumulative:
			return ITEM_NAMES[index]
	# rng_value >= 1.0 (or a degenerate all-zero weight table, which
	# validated tuning never produces -- see tuning_service.gd's own
	# catalog_is_usable() weight checks) falls through every bucket; clamp
	# to the last item rather than a crash or an out-of-bounds read, mirroring
	# the old formula's own exact-1.0 boundary contract.
	return ITEM_NAMES[ITEM_NAMES.size() - 1]


## See the class doc's N-WAY UNIFORM MAPPING / WEIGHTED MAPPING sections.
## position_ratio < 0.0 (the start_roll() sentinel default) OR an
## unconfigured slot (_tuning == null, nothing to read weight fields from)
## both fall back to uniform weights of 1.0 per item -- mathematically
## equivalent to the old plain floor() division (see _item_for_rng()'s own
## PROOF OF EQUIVALENCE). Otherwise, each ITEM_NAMES entry's own weight_
## front_<name>/weight_back_<name> pair is read off _tuning via Object.get()
## and linearly blended by position_ratio -- see item_tuning.gd's own
## ROULETTE WEIGHTS doc for the exact field-naming contract this depends on.
func _weights_for_ratio(position_ratio: float) -> Array[float]:
	var weights: Array[float] = []
	var use_uniform := _tuning == null or position_ratio < 0.0
	for item_name: StringName in ITEM_NAMES:
		if use_uniform:
			weights.append(1.0)
			continue
		var front_weight: float = float(_tuning.get("weight_front_" + String(item_name)))
		var back_weight: float = float(_tuning.get("weight_back_" + String(item_name)))
		weights.append(
			front_weight * (1.0 - position_ratio) + back_weight * position_ratio
		)
	return weights
