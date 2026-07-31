class_name RaceRanking
extends RefCounted

## Pure composite-sort live position ranking (R5 Task 2). rank() turns each
## kart's own per-tick snapshot -- already-tracked LapValidator/SpineFollower
## numbers, nothing recomputed here -- into a finishing-order-then-progress
## ordering of kart ids. This is the documented answer to spine_follower.gd's
## own class doc, which names this exact future consumer by name: "a
## progress bar, distance-based standings/ranking (future R5)... rank by
## (current_lap(), progress_gates())" plus total_progress_m as the final,
## continuous tiebreaker -- every field this class reads is one of those
## three seam-safe totals (or a finish-order integer), never a raw,
## seam-ambiguous spine offset. See race_session.gd's own class doc (LIVE
## RANKING section) for how the real per-tick snapshot is assembled from
## LapValidator/SpineFollower/AiKartAgent without any new closest-offset
## call -- this class only ever sorts numbers it is handed.
##
## ENTRY SHAPE, one Dictionary per kart in entries:
## - id: Variant, the kart's own identity -- returned in rank()'s own result
##   array untouched, never interpreted or compared by this class.
## - finished_order: int, -1 for a kart that has not yet finished, or the
##   order in which it crossed the finish line. Any monotonically
##   increasing scheme works -- race_session.gd's own producer uses
##   1st-place=1, 2nd=2, ... -- since this class only ever compares two
##   finished_order values against each other, never against a fixed
##   constant.
## - laps_complete: int, whole laps this kart has BANKED (NOT the lap
##   currently in progress -- see race_session.gd's own _rank_entry() doc
##   for the current_lap() - 1 derivation).
## - gates_this_lap: int, gates validated toward the lap in progress.
## - total_progress_m: float, the kart's own continuous SpineFollower total
##   -- never wraps, grows across laps, safe to compare cross-kart at any
##   seam position.
## Any entry missing a key reads that key's own documented default (-1 for
## finished_order, 0/0.0 for the rest) rather than erroring -- the same
## fail-closed-to-a-sane-default shape SpineFollower/LapValidator already
## use throughout this codebase.
##
## SORT (composite -- each tier is fully decisive; the next tier is never
## even consulted once one tier disagrees, per this task's own brief):
## 1. Finished before unfinished, unconditionally. A finished kart's own
##    total_progress_m keeps climbing after it crosses the line (race_
##    session.gd's own class doc: "an AI that finishes keeps driving") --
##    comparing it against a still-racing kart's total_progress_m would be
##    comparing two numbers that stopped meaning the same thing at
##    different instants, so tier 1 forecloses that comparison outright
##    rather than trying to make it fair.
## 2. Among finished karts: ascending finished_order (whoever crossed the
##    line first ranks first).
## 3. Among unfinished karts: descending laps_complete.
## 4. Then descending gates_this_lap.
## 5. Then descending total_progress_m.
## 6. STABLE beyond that (documented, not incidental): entries tying on
##    every field above keep their ORIGINAL relative order from the entries
##    array passed in. Godot's own Array.sort_custom() does not itself
##    promise a stable sort (unlike, say, Python's `sorted()`), so this
##    class decorates each entry with its own input index and carries that
##    through as the final comparison key rather than leaving a true tie's
##    order unspecified.
func rank(entries: Array[Dictionary]) -> Array:
	var decorated: Array = []
	var input_index := 0
	for entry: Dictionary in entries:
		decorated.append([entry, input_index])
		input_index += 1

	decorated.sort_custom(
		func(a: Array, b: Array) -> bool:
			return _before(a[0], b[0], a[1], b[1])
	)

	var result: Array = []
	for pair: Array in decorated:
		var entry: Dictionary = pair[0]
		result.append(entry.get("id"))
	return result


## True when entry_a must sort strictly BEFORE entry_b -- see the class
## doc's own SORT section for the full six-tier breakdown; index_a/index_b
## are each entry's own original position in the entries array passed to
## rank(), the tier-6 stability tiebreaker.
func _before(
	entry_a: Dictionary, entry_b: Dictionary, index_a: int, index_b: int
) -> bool:
	var finished_a := int(entry_a.get("finished_order", -1)) >= 0
	var finished_b := int(entry_b.get("finished_order", -1)) >= 0
	if finished_a != finished_b:
		return finished_a

	if finished_a and finished_b:
		var order_a := int(entry_a.get("finished_order", -1))
		var order_b := int(entry_b.get("finished_order", -1))
		if order_a != order_b:
			return order_a < order_b
		return index_a < index_b

	var laps_a := int(entry_a.get("laps_complete", 0))
	var laps_b := int(entry_b.get("laps_complete", 0))
	if laps_a != laps_b:
		return laps_a > laps_b

	var gates_a := int(entry_a.get("gates_this_lap", 0))
	var gates_b := int(entry_b.get("gates_this_lap", 0))
	if gates_a != gates_b:
		return gates_a > gates_b

	var progress_a := float(entry_a.get("total_progress_m", 0.0))
	var progress_b := float(entry_b.get("total_progress_m", 0.0))
	if progress_a != progress_b:
		return progress_a > progress_b

	return index_a < index_b
