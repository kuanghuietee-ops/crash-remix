# CTR R7 — Temple Twilight, pads, contact, the Cup

Date: 2026-08-01. Operator-approved ("continue r7"). Extends the racing spec
+ R6 polish spec; all hard rules unchanged (every byte original, tuning
provably live, human-only gates, mobile budgets, seam ruling).

## A. Boost pads + jump pads (discharges debt #2)

Generic track-authored pads: **BoostPad** (Area3D strip on the racing line;
kart contact → `apply_boost(pad_boost_s)`, brief cooldown per kart so one
pad fires once per pass) and **JumpPad** (vertical impulse scaled from the
hop physics by `jump_pad_velocity_scale`; airborne trajectory clears an
authored hazard/gap). Tuning fields on RaceTuning (`pad_boost_s=1.0`,
`pad_refire_cooldown_s=1.5`, `jump_pad_velocity_scale=2.2`). Glowing pad
visuals from palette cells + a subtle fx pulse (reuse the fx section's
conventions; one new field only if needed). Lint: pads on-road, clear of
gates/boxes/origin. AI: pads are on the racing line — apex/slot targeting
picks them up naturally; no special AI logic in R7.

## B. Kart-to-kart contact

CharacterBody3D pairs don't push each other; R7 adds authored bump physics:
on move_and_slide collision with another kart, both karts receive a lateral
separation impulse — speed-scaled, symmetric, capped (`bump_impulse_scale`,
`bump_min_relative_speed_mps`, `bump_lateral_cap_mps` on KartTuning). No
damage/spin from plain contact (items stay the offense); bumping is for
line-fighting. Must not destabilize AI (the progress-window stuck detector
already tolerates jostling; verify under a 6-kart bump-heavy race).

## C. Temple Twilight (track 2)

Night temple circuit from the village/interior kit (carved stone, totems,
torch posts, thatch, braziers) under the firelit mood precedent (Papu
night + warp-room brazier work): tight corridors, torch-lit apexes,
~600-750 m, 10-14 gates, full grid/boxes/flags/arch, pads as signature
features (a boost-strip main straight, one jump-pad corner cut), item
boxes, dressed to racing density. Menu gains RACE + TIME TRIAL entries
(if the menu wiring is getting unwieldy at 3 tracks × 2 modes, refactor to
a small track-registry table — implementer judgment, keep it clean).
Sanity Shores + graybox get pads retrofitted sparingly (1-2 boost strips;
no jump pads outside Temple unless natural).

## D. The Cup

A 2-track championship: Sanity Shores → Temple Twilight, points by
placement per race (CTR-style table in tuning: `cup_points_by_place` —
authored as per-place fields or a small table resource; design cleanly),
cup standings shown between races and at the end (winner celebrated,
player highlighted). Cup result persisted: save schema v2→v3 with the SAME
migration rigor as v1→v2 (scratch-verified old-save survival; racing
section gains a `cups` record — best placement per cup id). Menu: CUP
entry. AI lineup identical across both races (continuity).

## E. Stretch: time-trial ghost

Record the player's best solo run per track (position/yaw keyframes,
compact), replay as a translucent ghost kart (no collision, no AI). Stored
OUTSIDE the profile save (per-track `user://ghosts/` files; corrupt/absent
ghost = silently no ghost — never blocks a run; a small version header for forward
compat). If the phase strains, defer with a recorded debt — the Cup ships
first.

**Status (Task 6, 2026-08-01): SHIPPED, not deferred.** The phase did not
strain — `GhostRecorder`/`GhostPlayer` landed complete with a full test
roster (round-trip, every corruption shape resolving to silent no-ghost,
best-time-gated persistence, interpolation math, no-collision proof,
solo-only contract) in the same task. See `docs/superpowers/sdd/
2026-08-01-ctr-r7-second-circuit/task-6-report.md` and this project's own
racing-spec Recorded Debts section (R7 polish-wave notes).

## Phases

T1 pads mechanics+lint → T2 kart contact → T3 Temple Twilight → T4 pad
retrofits + menu/registry → T5 Cup (+save v3) → T6 ghost (or defer) → T7
integration/verification → R7 APK. Feel gates the operator's throughout.

## Out of scope

Audio (its own future phase), more characters/final art, adventure,
multiplayer, new items.
