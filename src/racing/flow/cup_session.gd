class_name CupSession
extends RefCounted

## Task 5 (CTR R7): a 2-race championship -- Sanity Shores then Temple
## Twilight -- orchestrated across a real GameRoot scene swap. Pure logic
## only (no Node, no scene tree), the same "state that outlives a single
## race scene" role SessionSnapshot plays for a resumed platformer level,
## but held live in memory rather than round-tripped through disk.
##
## OWNERSHIP. RaceSession (race_session.gd) is torn down and rebuilt fresh
## between the two races -- GameRoot's _render_state() racing branch
## instantiates a brand-new race scene every time flow.active_level_id
## changes (see game_root.gd's own class doc on that branch), the exact same
## "retry frees the whole scene, GameRoot re-selects the level" round-trip
## retry_requested already established. Nothing owned BY a race scene can
## therefore survive into the next one. GameRoot itself is the one node that
## stays alive across that swap (it IS the scene tree root -- see race_
## session.gd's own retry_requested doc), so GameRoot holds the ONE
## CupSession instance for a cup in progress (a new `_cup_session` var, null
## whenever no cup is active) and is the only thing that ever calls into it.
## Race scenes never see, own, or reference a CupSession at all -- they stay
## exactly as ignorant of "is this race part of a cup" as they were before
## this task, reporting results the SAME way an ordinary standalone race
## always has: through the existing race_finished signal (total_s, lap_times)
## plus the existing standings() query GameRoot already reads for its own
## purposes on every race finish (see race_session.gd's own standings() doc).
## GameRoot is the one place that decides those two things mean "score a cup
## race" instead of (or alongside) "maybe persist a new time-trial best".
##
## THE FLOW. GameRoot creates a CupSession and calls configure() once, when
## the player picks the CUP menu entry (a brand-new debug entry, see level_
## list_overlay.gd's own cup_requested row). It then drives race 1 exactly
## the same way any ordinary "RACE — SANITY SHORES" menu pick already does
## (_select_level() into the SAME registered race scene -- RacingTrackRegistry's
## rows are reused verbatim, not duplicated), and remembers which of THIS
## session's race indices that launch corresponds to in its own `_cup_active_
## race_index` field (game_root.gd's own doc on that field explains why this
## is tracked independently rather than re-derived from next_race_index() at
## finish time -- next_race_index() answers "what has CupSession never
## recorded a result for", which is the WRONG question once a RETRY is in
## play: it would already point PAST a race being replayed). When that race's
## race_finished signal fires, GameRoot -- already listening for its own
## save-comparison purposes -- also asks: is a cup active, and does THAT
## remembered race index's own track_id match the track_id that just
## finished? If so, it reads that race's own standings() (the exact same live
## query the finish panel itself already renders) and hands it, together with
## that same race index, to record_race_result(). This session then owns
## everything about turning a placement into cup state: whether the cup is
## now complete, and what the running standings are -- it never needs to know
## WHICH physical race scene is currently loaded, only what index GameRoot
## says just reported in.
##
## STABLE PARTICIPANT IDENTITY, FOR FREE. A cup's two races are two entirely
## separate RaceSession instances with two entirely separate kart node
## trees -- nothing about a Node identity survives between them. What DOES
## survive is each participant's own SLOT: RaceSession.standings() labels a
## kart "YOU" for the player or "CPU n" for the AI kart at index n-1 in
## _ai_karts (see race_session.gd's own _standings_label() doc), and _ai_
## karts is built by iterating GridSlot1..GridSlot(opponent_count) in a
## fixed order every single configure() call (see _spawn_ai_karts()'s own
## GRID SLOTS doc) -- both real tracks author exactly 5 such markers,
## matching AiTuning.opponent_count's own default. "CPU 3" in race 1 and
## "CPU 3" in race 2 are therefore not merely labeled the same; they ARE the
## same participant by construction, with IDENTICAL continuity for free:
## - Character/tint: _spawn_ai_karts() always mounts the lab-assistant model
##   and calls kart_tuning.tint_for_slot(slot_index) -- a pure function of
##   the 1-based grid slot number alone (see kart_tuning.gd's own tint_for_
##   slot() doc), nothing randomized, nothing session-specific.
## - Driving personality: AiDriver.configure() receives that same slot_index
##   and every personality-shaped term it derives (aggression offset, skill-
##   jitter confidence) is either a direct function of slot_index and tuning,
##   or a DETERMINISTIC hash of (slot_index, tick_index) -- see ai_driver.gd's
##   own class doc, "purely a function of slot_index and tuning... NOT a
##   random-number source". No RandomNumberGenerator seeds a kart's identity
##   anywhere in this path.
## This CupSession therefore never needs to carry an AI roster, tint table,
## or personality seed of its own across races -- there is nothing to carry.
## record_race_result() keys every race's placements by the SAME "YOU"/
## "CPU n" label RaceSession.standings() already produces (see that method's
## own STANDINGS class doc on race_session.gd for the exact label contract
## this session's LABEL_PLAYER constant below stays coupled to), and totals
## simply accumulate under those labels across however many races have
## actually been recorded so far.
##
## RETRY SEMANTICS INSIDE A CUP. record_race_result(race_index, standings)
## OVERWRITES whatever was previously recorded for that race_index -- it is
## not additive. A cup's running/final standings are always derived fresh
## from _results, never from an append-only log, so "retry race 1" needs no
## special handling anywhere in this class at all: retrying re-renders a
## fresh race scene (see the class doc's own OWNERSHIP section) and plays it
## again from scratch, and race_finished only ever fires once that SECOND
## attempt actually finishes -- nothing calls into this session while a
## retried race is still in progress, so "cup totals unaffected until
## finish" is true by construction, not by any explicit guard here. Once
## that retried attempt DOES finish, GameRoot calls record_race_result() for
## the SAME race_index again, and this session simply replaces the earlier
## entry -- "retry race 1 = restart race 1" reads exactly as "whichever
## attempt actually finished is the one this cup counts", the same way a
## retried level's own best-time/relic comparison only ever sees the run
## that actually completed.
##
## TIE-BREAK RULE (pinned, not incidental): standings() sorts by total points
## DESCENDING first. A tie is broken by each participant's own placement in
## race index 1 (Temple Twilight, the SECOND race) ASCENDING -- a better
## (lower-numbered) second-race finish wins the tie. This mirrors real kart-
## racer convention (the closer/decider race breaks a tie, not the opener)
## and needs no THIRD tiebreak beyond it in practice (two participants tied
## on total points AND on race-2 placement would need to have swapped
## placements between the two races in a way that nets the identical points
## sum on both axes -- not something the 6-entry, 6-point-value shape this
## cup ships with can actually produce, but the sort is still a total order:
## stable-by-input-order is the final fallback, same as RaceRanking's own
## documented tier-6 stability). Before race index 1 has been recorded at
## all (the BETWEEN-race interstitial after race 1 alone), every
## participant's race-2 placement reads as "no data yet" and the tiebreak
## degrades to that same input-order stability -- which, since standings()
## builds its label list by first-seen order walking race_index 0 upward,
## is exactly race 1's own finishing order. That is a deliberately sane
## interim display, not a bug: there is no race 2 result to break a tie with
## yet.

## Task 5 (CTR R7): identifies this cup for SaveModel.cup_record()/
## improved_cup_record() (see save_model.gd's own "cups" section doc) --
## the one cup this build ships, so a single constant rather than a
## per-instance field.
const CUP_ID: StringName = &"island_cup"

## Order matters: index 0 is always played first. Track ids match
## RacingTrackRegistry.TRACKS verbatim (src/racing/track/track_registry.gd)
## -- this session never invents its own scene/level wiring, only the ORDER
## a cup plays two of the registry's existing rows in.
const TRACK_IDS: Array[StringName] = [
	&"sanity_shores",
	&"temple_twilight",
]

## See race_session.gd's own _standings_label() doc -- this session's whole
## "stable participant identity for free" design (see this class's own
## OWNERSHIP doc) depends on this string matching that method's player
## branch EXACTLY. Grepped and cross-referenced deliberately, not
## re-derived, so the two can never silently drift apart.
const LABEL_PLAYER: String = "YOU"

## place1..place6, read once at configure() time -- see RaceTuning's own
## Cup category doc for why these are 6 scalar fields rather than one array
## field.
var _points_table: Array[float] = []

## One Dictionary per race index: label (String) -> 1-based finish position
## (int) for that race, as recorded by record_race_result(). Empty ({})
## means "not yet played" -- has_result()/next_race_index()/is_complete()
## all read this shape directly rather than a separate bookkeeping flag, so
## there is exactly one source of truth for "how much of the cup has
## actually been played".
var _results: Array[Dictionary] = []


func configure(race_tuning: RaceTuning) -> void:
	_points_table = [
		race_tuning.cup_points_place1,
		race_tuning.cup_points_place2,
		race_tuning.cup_points_place3,
		race_tuning.cup_points_place4,
		race_tuning.cup_points_place5,
		race_tuning.cup_points_place6,
	]
	_results.clear()
	for _race_index: int in range(TRACK_IDS.size()):
		_results.append({})


func race_count() -> int:
	return TRACK_IDS.size()


## -1 if race_index is out of range -- the same "not a valid index" sentinel
## track_id_for_race() and every other index-taking getter on this class use,
## never an empty StringName that could be confused with a genuinely missing
## registry entry.
func track_id_for_race(race_index: int) -> StringName:
	if race_index < 0 or race_index >= TRACK_IDS.size():
		return &""
	return TRACK_IDS[race_index]


## The lowest race_index with no recorded result yet, or -1 once every race
## has one (the cup is complete -- see is_complete() below, a thin wrapper
## on this same scan). GameRoot's own _advance_cup() reads this directly to
## decide which race to launch NEXT. It is deliberately NOT what GameRoot
## reads to decide whether a just-finished race scores into this cup --
## that uses GameRoot's own _cup_active_race_index instead (see that field's
## own doc for why: next_race_index() already points PAST a race that has a
## RETRY in flight, since the original attempt's result is still recorded
## here until the retry's own finish overwrites it).
func next_race_index() -> int:
	for race_index: int in range(_results.size()):
		if _results[race_index].is_empty():
			return race_index
	return -1


func has_result(race_index: int) -> bool:
	return (
		race_index >= 0
		and race_index < _results.size()
		and not _results[race_index].is_empty()
	)


func is_complete() -> bool:
	return next_race_index() < 0


## See the class doc's RETRY SEMANTICS section -- OVERWRITES race_index's
## previous entry wholesale, never merges or accumulates into it. `standings`
## is the exact Array RaceSession.standings() returns (one Dictionary per
## kart currently in the race, each carrying at least "label": String and
## "position": int -- see that method's own doc); any entry missing either
## key, or whose position is not a positive integer, is skipped rather than
## recorded with a garbage placement, the same fail-closed-per-entry shape
## RaceRanking's own entry-reading already uses throughout this codebase. A
## race_index outside [0, race_count()) is a no-op -- defensive only, since
## GameRoot's own next_race_index()-gated call site (see that method's own
## doc) never produces one through the real flow.
func record_race_result(race_index: int, standings: Array) -> void:
	if race_index < 0 or race_index >= _results.size():
		return
	var placements: Dictionary = {}
	for entry: Variant in standings:
		if not entry is Dictionary:
			continue
		var row: Dictionary = entry
		var label := String(row.get("label", ""))
		var position_value: Variant = row.get("position")
		if label.is_empty() or not _is_positive_integer(position_value):
			continue
		placements[label] = int(position_value)
	_results[race_index] = placements


## place is 1-based (1 = first). 0.0 for anything outside the configured
## table (place <= 0, or beyond however many places this cup's points table
## covers) -- a finisher outside the scored field earns no points rather
## than an out-of-bounds error, the same fail-closed shape record_race_
## result() already uses per-entry one section up.
func points_for_placement(place: int) -> float:
	var index := place - 1
	if index < 0 or index >= _points_table.size():
		return 0.0
	return _points_table[index]


## Cumulative standings across every race recorded SO FAR -- called both for
## the between-race interstitial (only race index 0 recorded) and the final
## podium (every race recorded, is_complete() true); the caller tells those
## two apart via is_complete(), not via anything returned here. One
## Dictionary per participant who has appeared in at least one recorded
## race, ordered 1..N by this session's own tie-break rule (see the class
## doc's TIE-BREAK RULE section for the full sort and its rationale):
## - position: int, 1-based cup standing.
## - label: String, "YOU" or "CPU n" -- see record_race_result()'s own doc
##   for where this comes from.
## - total_points: float, points_for_placement() summed across every race
##   index that has actually recorded a placement for this label.
## - is_player: bool, label == LABEL_PLAYER -- the caller's own "highlight
##   this row" flag, read straight off rather than re-deriving it from the
##   label string, the same convenience RaceSession.standings() already
##   offers its own callers.
func standings() -> Array:
	var totals: Dictionary = {}
	var order: Array[String] = []
	for race_index: int in range(_results.size()):
		var placements: Dictionary = _results[race_index]
		for label: String in placements.keys():
			if not totals.has(label):
				totals[label] = 0.0
				order.append(label)
			totals[label] += points_for_placement(placements[label])

	# See the class doc's TIE-BREAK RULE: race index 1 (the second, deciding
	# race) breaks a total-points tie, ascending (better placement wins).
	# Empty ({}) before race index 1 has been recorded at all, which reads
	# every label as having "no race-two data" and so degrades the tie-break
	# to stable input order -- see that section's own doc for why that is
	# the correct interim display, not a bug. An explicit has-data flag per
	# entry (rather than an out-of-range sentinel placement value) keeps
	# every literal in this comparison inside the src/racing/** lint's
	# allowed 0/1/-1 set.
	var race_two_placements: Dictionary = (
		_results[1] if _results.size() > 1 else {}
	)

	var decorated: Array = []
	for input_index: int in range(order.size()):
		var label: String = order[input_index]
		decorated.append({
			"label": label,
			"total_points": float(totals[label]),
			"is_player": label == LABEL_PLAYER,
			"_has_race_two_result": race_two_placements.has(label),
			"_race_two_placement": int(race_two_placements.get(label, 0)),
			"_input_index": input_index,
		})

	decorated.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a["total_points"] != b["total_points"]:
				return a["total_points"] > b["total_points"]
			if a["_has_race_two_result"] != b["_has_race_two_result"]:
				# Defensive only (see record_race_result()'s own doc -- every
				# real cup race records a placement for every participant it
				# lists): whichever entry actually HAS a race-two result
				# outranks one that inexplicably does not, rather than an
				# unspecified ordering between a real int and the 0 filler.
				return a["_has_race_two_result"]
			if (
				a["_has_race_two_result"]
				and a["_race_two_placement"] != b["_race_two_placement"]
			):
				return a["_race_two_placement"] < b["_race_two_placement"]
			return a["_input_index"] < b["_input_index"]
	)

	var result: Array = []
	var position := 1
	for entry: Dictionary in decorated:
		result.append({
			"position": position,
			"label": entry["label"],
			"total_points": entry["total_points"],
			"is_player": entry["is_player"],
		})
		position += 1
	return result


func _is_positive_integer(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var numeric_value: float = value
	return (
		is_finite(numeric_value)
		and numeric_value == floor(numeric_value)
		and numeric_value >= 1.0
	)
