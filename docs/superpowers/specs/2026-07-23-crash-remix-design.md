# CRASH BANDICOOT: N. SANITY REMIX — a trilogy greatest-hits rebuild for Android
### Concept draft v0.2 — 2026-07-23 (supersedes v0.1, archived alongside)
**Status: draft to be argued with, not a spec.** Godot 4, sideloaded APK, solo dev + AI coding agent.

**Framing, stated once:** this is a **personal fan game** — Crash Bandicoot is Activision's IP; this build is for the operator and friends, sideloaded, never publicly distributed, and that assumption underpins every decision below. Two design facts follow and are not revisited: **every asset is built by the operator from scratch** (no extraction from the PS1 discs or N. Sane Trilogy — his models, his textures, his animations, made from video reference), and **all audio is original, composed in the style of Josh Mancell's trilogy score** (in-style originals, not covers of the actual melodies — a cover still reproduces the composition; §10 defines the style precisely enough to brief a composer or an AI music tool).

---

## 1. Executive summary

**The pitch.** Twenty-five of the best levels from Crash Bandicoot 1, 2 and 3, rebuilt from memory and video reference as one game on a 2026 Android phone — running the full Crash 4 moveset, with the trilogy's one real flaw (depth perception) actually solved, a retry loop measured in seconds, and controls designed for thumbs from day one. Not a restoration: a **remix**. The level you remember, tuned for the kit you have now.

**The three pillars** (unchanged from v0.1 — they survived the pivot because they're about the formula, not the fiction):

1. **Never guess depth.** Every jump is answerable from what's on screen: hard drop-shadow, predicted landing ring, camera authored so landing zones always read. Extended in this revision to hold during wall-runs and rail grinds (§5.6).
2. **Forgive the thumb, not the level.** Input forgiveness maximal and tuned in milliseconds; level challenge undiluted. You lose to the level, never to the glass.
3. **Three-minute mastery.** Short dense levels, instant retry, gems/relics as the replay engine, two taps from icon to gameplay.

---

## 2. What the trilogy got right / wrong (the study — carried from v0.1, still the foundation)

### 2.1 Why the corridor worked, and why it's kept

Naughty Dog's corridor came from PS1 constraints — a narrow frustum let them stream dense geometry and author every camera frame — but the constraint bought durable design properties: **guaranteed framing** (the camera never fights you and never needs a second stick), **readable depth** (one depth question at a time), **density** (every meter authored; challenge-per-second nearer a rhythm game than its 3D peers), and **pacing control** (the designer owns the tempo like a shmup author).

Kept deliberately, and *stronger* on mobile than on PS1: touch has no right stick, so an authored camera deletes the camera problem instead of solving it badly; the tight streaming window is a perf gift; short dense ribbons fit phone sessions. Discarded as era scar tissue: strict track width (levels may widen into rooms), walking backward against the camera (all branches rejoin forward), invisible walls (a 2026 phone renders a living vista beyond the ribbon), and load-time-driven design.

**New this revision:** the Crash 4 kit (wall-run, rail grind) stresses this premise hard. §5.5 resolves it — the short version is that these verbs become *authored segment types with their own camera archetypes*, exactly as Crash 4 itself treats them, and the corridor survives intact.

### 2.2 The moveset lesson

Crash 1 shipped with two verbs and wrung a game from them. Spin is the genius verb — a 360° no-aim attack, always safe to press, always useful: exactly the property a touch button needs. Slide-jump was the emergent tech ceiling. What the trilogy lacked: mid-air correction (making depth errors fatal), and verb consistency (C3's powers were half filler — the bazooka is an aiming verb and dies on touch anyway). This build takes the full Crash 4 kit (§4) — the trilogy's endpoint moveset — with double jump from the start as the depth-correction eraser.

### 2.3 Depth perception — the real flaw

Into-the-screen jumps were the series' one genuine design failure: low camera pitch, foreshortening, a load-bearing but under-guaranteed shadow, no air correction. Fixed as Pillar 1 (§5.4): authored minimum camera depression on required jumps, a constant hard blob shadow, ballistic landing-ring prediction, double jump, optional soft assist. Depth death should be near-extinct.

### 2.4 The crate economy

The best system in the trilogy — one object family doing four jobs: **metronome** (box rhythm sets tempo and marks the line), **breadcrumb** (a trail bending off-path is the secret signpost), **micro risk/reward** (TNT fuses, Nitro adjacency, bounce chains — optional skill bets every few seconds), **completion metric** (the gem). Kept wholesale and by name: standard, TNT (3s fuse, spin forbidden), Nitro (never touch; green `!` detonator pays off restraint), `!` outline, bounce, checkpoint, iron, Aku Aku, plus time crates in relic mode. The one flaw — the compound all-crates-no-death gem — is fixed in §7: crates persist across deaths; the gem is a sweep, not a hidden-object exam with permadeath. Purists get their no-death challenge as a separate flag.

### 2.5 Difficulty, lives, death

Preserved: one-hit death (with Aku Aku's graduated failure) — remove it and the game goes weightless. Deleted: finite lives (an arcade tax that ejects the player who most needs practice), sparse checkpoints, load-time retry cost. Naughty Dog's own hidden dynamic difficulty (extra masks and checkpoint mercy for struggling players) becomes an honest, visible mercy system (§7.5). Crash 4's "modern mode" made the same calls; this is not heresy, it's the series' own trajectory.

### 2.6–2.8 Structure, bosses, the honest bad list

Warp room hub: kept (instant access, legible progression, 5+boss per room). Chase levels: kept — they're the series' best variety. Vehicle levels (jetski, plane, bike, sub): **cut** — each is a new controller, camera and art set; a second game's worth of work to reach mediocre. Animal rides (hog, bear) are *not* vehicles in this sense — they're forced-run chase levels on the existing controller, and they stay. Bosses were the trilogy's weakest part (flat arenas, three-pattern wait-your-turn loops, difficulty below the surrounding levels); §8 rebuilds the canon roster with a gauntlet philosophy. The full flaw→answer table from v0.1 (hitbox inconsistency → global 70–75%/120% ratios; hidden crates → per-gong sweep counters and ghost markers; difficulty via distance-since-checkpoint → never) carries unchanged.

---

## 3. The game

**Working title:** *Crash Bandicoot: N. Sanity Remix*. **Cast:** Crash (playable), Coco (playable skin sharing Crash's rig and clips — the cheap, correct way), Aku Aku (mask/shield), Cortex (villain, final boss), bosses Papu Papu, Dingodile, Ripper Roo, Tiny Tiger; Uka Uka and N. Gin in cameo/framing roles only. **Premise, one sentence of fiction and no more:** Cortex's broken time machine has smashed the three islands' eras together, and Crash replays the mangled greatest hits to put them back — which licenses mixed-era warp rooms and the quantum phase rifts (§4.4) without further explanation.

**The unification problem, position taken.** Three games, three art directions, three difficulty philosophies, three movesets. The promise is **memory-faithful, not survey-faithful** — "the level you remember," not the level as surveyed. Concretely:

- **One moveset everywhere.** The full C4 kit is always available; no per-level verb removal (mode-switched movesets punish muscle memory and feel broken). Consequence accepted: C1 levels' base lines get easier — slide-jump alone breaks half of Crash 1's gap math, and double jump deletes Road to Nowhere's turtle-hop precision as designed.
- **Geometry is re-tuned, not copied.** Every level keeps its *identity beats* — the set-pieces you actually remember (the first rope-gap on Road to Nowhere, Slippery Climb's rain-slick lifts, Cold Hard Crash's death route) — but gaps, spacing and hazard cadence are re-authored to this game's movement metrics. This is forced anyway: no ripped geometry means the operator rebuilds from video reference, so exact survey fidelity was never on the table. Re-tuning is free.
- **Where the old challenge went:** each level ships a re-tuned base line at unified "Crash 2 fair-brutal" difficulty, plus one **full-kit line** — an optional harder/faster route (colored-gem or death-route framed) that *requires* C4 tech: wall-runs, grind chains, slide-jump-double-spin extensions, phase toggles. Old levels stay interesting with the new kit because the mastery routes are built for it.
- **One art direction** (§9): unified stylized look across all 25 levels; Crash 1's gothic mood is preserved through lighting and palette (its castle levels stay dark, wet, saturated-grim), not through separate art philosophy. One game, five moods, one hand.
- **One difficulty philosophy:** Crash 2's — dense, fair, telegraphed — with v0.1's retry loop under it (no lives, gongs→checkpoint crates every 45–60s, ≤2s respawn). Crash 1's brutality survives where it was *earned* (Slippery Climb, Sunset Vista, Cold Hard Crash keep their teeth in re-tuned form) and dies where it was friction.

Purists would call all of this heresy. The operator is building for feel on a phone, not archaeology, and this document optimizes for that without apology.

---

## 4. Core loop and moveset — the full Crash 4 kit

### 4.1 The loop

Seconds: read the corridor → pick a line → execute through the crate cadence → checkpoint. Per level (2–4 min): clear → results (box count, relic time, flawless flag) → one-tap retry. Per session: a level or three, a relic attempt. Per game: warp rooms, gems, colored gems, relics, the bonus wing.

### 4.2 Verbs (rebuilt from scratch — spin replaces v0.1's dash)

Thirteen verbs; four buttons + stick. Numbers are initial values owned by the tuning system (§11.4) and the feel gate. Crash ≈ 1.1m tall; world authored on a 2m grid.

| Verb | Input | What it does | Numbers (initial) |
|---|---|---|---|
| **Run** | left stick | Player-controlled movement (no auto-run — §5.3) | 7.0 m/s; 0.08s to speed; near-instant stop |
| **Jump** | JUMP (variable) | Hold for height | 2.2m full / 0.9m tap; fall gravity 1.6× rise; 0.85× at apex |
| **Double jump** | JUMP in air | Second jump, full air steering — the depth-correction tool | +1.8m |
| **Spin** | SPIN | The do-something verb: 360° attack, crate break, projectile deflect; **does not move you**. Air-spin adds a brief stall (the C3/C4 descent-slow, once per airtime) | 1.2m radius; 0.45s active; hitbox 120% of visual; air stall = 0.4× gravity while active |
| **Crouch / crawl** | DOWN still (+stick) | Low profile; crawl tunnels | hurtbox 45% height |
| **High jump** | crouch → JUMP | The C2 vertical tech, kept | 2.9m |
| **Slide** | DOWN while running | Under obstacles; attacks low | 2.8m; 0.35s |
| **Slide-jump** | JUMP during slide | Long flat jump — the tech ceiling, preserved | ~5.5m at 1.4m height |
| **Body slam** | DOWN in air | Committed fast descent + shockwave; breaks iron-adjacent stacks; the "end this jump NOW" panic verb | 0.5m shockwave; 0.1s recovery; no cancel |
| **Wall-run** | contextual (§5.5) | Authored ridged strips only; auto-attach with forward input; JUMP detaches on an authored outward arc | attach cone ±25° of strip axis |
| **Rail grind** | contextual (§5.5) | Auto-attach on landing arc intersect; stick+JUMP hops between parallel rails; JUMP exits | attach snap 0.35m; hop window = jump buffer |
| **Rope swing** | contextual | Auto-catch; JUMP releases at current arc point | release arc telegraphed by landing ring |
| **Phase-shift** | PHASE | Quantum toggle: flips the blue/orange object sets (crates, platforms, hazards) in phase segments; usable in any state incl. mid-air | instant; 0.25s re-toggle cooldown |

**Cut from the C3/C4 kits, with reasons** (full reasoning in §13): the bazooka (an aiming verb; dies on touch), sprint shoes (a held-modifier tax on a busy thumb; speed lives in slide-jump tech instead), death tornado (subsumed by the air-spin stall), and the **other three Quantum Masks** — time-slow (feel-gate hazard stacked on touch latency), dark-matter spin (a superverb that trivializes crate logic), gravity-flip (a camera nightmare that doubles geometry cost). Phase-shift is the mask that matters and the only one that ships.

**What replaced dash.** v0.1's dash did three jobs; each is reassigned: *attack* → spin (strictly better: no aim, 360°); *horizontal air extension* → the slide-jump → double-jump → air-spin chain (~8m total reach — the "full extension," gating the best optional crates); *panic reposition* → body slam (vertical abort) + double jump (lateral abort). Net air mobility is slightly below the dash kit — accepted, because we own the geometry and re-tune to these metrics rather than inflating the verbs.

**Composition depth** (taught by level design, never by text): slide-jump for distance, crouch-jump for height, the full-extension chain for the greedy lines; slam ends any misjudged jump instantly; spin-stall is the micro-correction that pairs with the landing ring; grind-hop rhythm lines and wall-run detach arcs are the relic-run speed tech; and phase-toggle mid-jump is the new *brain* verb — committing to a route while airborne, which is the most Crash-4 feeling in the game and costs nothing on touch but one well-placed button.

**Health:** one-hit death; Aku Aku absorbs a hit, stacks to two; **third mask = ~20s invincibility** (canon, and it still feels great); 100 wumpa auto-summons a mask (replaces the extra life, which no longer exists).

---

## 5. Touch controls

Premise unchanged from v0.1 and restated because it's the make-or-break: **touch-first, gamepad first-class**, landscape only, two thumbs, feel gate passes on touch or the project dies cheap. Pure swipe (30–80ms gesture-disambiguation latency, no sustained steering), lane-based (deletes line-choice — the skill), and full auto-run (kills exploration, branches, and pacing ownership; levels stop being places) remain rejected; forced-run appears only where it's canon and correct — the chase and ride levels. Hybrid floating stick + buttons is the boring, correct answer; the wins are in tuning.

### 5.2 The concrete scheme — four buttons, and that's the ceiling

All sizes in physical millimeters via `DisplayServer.screen_get_dpi()`; all zones inside `DisplayServer.get_display_safe_area()`; every zone user-movable/scalable; mirrored layout for left-handers.

**Left thumb — floating stick** (unchanged from v0.1): spawns under the thumb in the left 42% of screen below the top 25%; 22mm ring / 11mm knob at ~35% opacity; 1.5mm dead zone, full run beyond 4mm deflection (direction-first, speed-coarse — analogue walking on glass is fiction); continuous 360°. **Rail magnet:** within ±15° of the corridor axis, heading eases toward the axis; beyond it, full authority instantly. Assistance in heading, never position. Tunable 0–1, initial 0.5, headline item at the feel gate.

**Right thumb — four buttons**, arced for the resting thumb, anchored bottom-right:

- **JUMP** — 14mm visual, ~12mm from right edge, ~12mm up. Invisible hit area is huge: any bottom-right touch not claimed by another button is JUMP. The verb that must never miss.
- **SPIN** — 12mm, left of JUMP (~26mm from edge). Second-most-pressed; the forgiving do-something button.
- **DOWN** — 12mm, above JUMP. Context verb: crouch still / slide running / slam airborne. One button, three moves, zero ambiguity — context is machine-readable.
- **PHASE** — 10mm, on the outer arc between SPIN and DOWN (up-left diagonal from JUMP). **Appears only once the mechanic unlocks** (Warp Room 4) — progressive UI keeps the early game at three buttons.

Four buttons is the hard ceiling for a right thumb under time pressure; this is why the traversal verbs *had* to be contextual (next section) and why the bazooka died. Buttons flash + 10ms haptic tick on press (`Input.vibrate_handheld`; toggle). Multitouch fully independent; a jump during a stick reposition must register. **Occlusion rule carried:** Crash composes slightly left of center, landing zones in the middle/upper 2/3; no required interaction in the bottom-right occlusion wedge — camera framing is a controls feature.

**The contextual/dedicated split, defended.** Wall-run, grind and swing auto-trigger from authored surfaces + state — which is how Crash 4 itself treats them (you cannot wall-run arbitrary walls there either; ridged strips and placed rails are the trigger). Auto-attach risk (unwanted attaches) is contained because the surfaces exist only in authored segments and attach requires matching input direction; the mitigation ladder if the feel gate disagrees is: raise the attach cone strictness → require JUMP held during approach → last resort, a settings toggle for manual attach. Phase-shift is the one new verb that is a *decision*, not a traversal state — decisions get buttons.

**Gamepad:** full BT support from Phase 0; stick move (magnet off above 0.6 magnitude), A jump, X spin, B/R1 DOWN, Y phase; prompts auto-swap; same forgiveness windows both inputs; assists default differently (landing assist 0 on pad). Feel gate runs on touch; pad is verified, never the gate.

### 5.3 Forgiveness windows — carried from v0.1, additions marked

Android's touch pipeline costs ~50–90ms before the game can react; windows are designed around it, not wished away.

| Forgiveness | Window | Why |
|---|---|---|
| Jump input buffer | **120ms** | ~100ms console norm + touch latency margin |
| Coyote time | **140ms** | Genre norm + margin; 3D edges are harder to see, depth ambiguity makes late jumps common |
| SPIN/DOWN buffer | 150ms | Queued verbs fire on landing — no dead landings |
| Variable jump | <90ms release = min hop; full ≥220ms | Distinguishable through latency jitter |
| Edge landing nudge | 0.12m | Foot-center ≤0.12m past a lip snaps up; landings only, never into hazards |
| Bounce timing (high) | ±100ms | Bounce chains are a joy engine |
| **Grind auto-attach** *(new)* | arc-intersect within 0.35m of rail | Landing ring turns rail-colored when the arc will attach — attach is telegraphed, not surprising |
| **Wall-run attach** *(new)* | contact + input within ±25° of strip axis | Wide enough for glass steering, narrow enough to stop accidents |
| **Wall/rail detach jump** *(new)* | same 120ms buffer | Detach is a jump; it inherits jump's forgiveness |
| **Phase re-toggle** *(new)* | 0.25s cooldown | Prevents flicker-spam solving phase puzzles by mashing |
| Hurtbox / attack | 70–75% / 120% of visuals | The felt-fair ratio, global not per-object |
| Respawn | ≤2.0s death→control | Retry cost is the real difficulty multiplier |

**Latency budget:** touch→response ≤100ms hard fail / 85ms target, 240fps slow-mo camera measured at the gate. Engine: physics 60Hz, `Input.set_use_accumulated_input(false)`, timestamped polling consumed next physics tick, 3D physics interpolation on.

### 5.4 The depth-aid stack (carried; amended for the new verbs)

1. **Authored camera rule:** any required jump's landing surface visible at ≥15° depression, enforced by an author-time lint. *(Suspended during wall-runs — replaced, see 5.6.)*
2. **Hard blob shadow, always** — constant size/opacity decal on every dynamic object, gameplay element not lighting. *(Projects onto wall-run surfaces too.)*
3. **Landing ring** — ballistic-arc prediction, green/red on landable/hazard. *(Extended: turns rail-orange predicting a grind attach; during swings, shows the current release arc's landing.)*
4. **Double jump + slam + spin-stall** as player-side corrections.
5. **Soft landing assist** (optional, default 0.5 touch / 0 pad): last 30% of a fall eases velocity toward a platform edge within 0.4m if the stick isn't fighting it. Never moves you to a platform you didn't aim at.

### 5.5 The camera vs. the Crash 4 kit — the most important section in this revision

The v0.1 corridor premise — authored camera regions, the ≥15° rule — was built for ground platforming, and v0.1 explicitly cut wall-jump as "fights the authored camera." Wall-run and grind are now mandatory. Resolution, stated plainly: **the corridor camera survives, because wall-run and grind enter the game as authored segment types in the existing grammar — never as globally available abilities — each bringing its own camera archetype.** This is not a dodge; it is how Crash 4 itself ships these verbs (ridged strips and placed rails, not free traversal), so the fan-game framing and the engineering answer agree.

- **Rail grind segments.** The rail *is* the corridor spine — a spline the camera rig already knows how to follow. Camera pulls back and side-biases along the rail, banking with it. Player input reduces to hop timing and lane choice between parallel rails; inter-rail hops are lateral (side-readable) or spline-along arcs where the landing ring stays valid. Depth ambiguity nearly vanishes on rails — you're on a 1D manifold. Grind is the *most* touch-friendly verb in the new kit, which is why grind segments are seeded from Warp Room 2 onward and carry big parts of the relic speed lines.
- **Wall-run segments.** Authored strips on walls; on attach, the camera swings to a **side-on to 3/4 view where the wall reads as a floor** — the run surface's tangent held horizontal on screen. This converts a 3D depth problem into 2.5D readability, which the game already knows how to author. The ≥15° depression rule is suspended and replaced by the **wall-run substitute rule: during a wall-run, the surface must read as ground (tangent horizontal on screen) and the detach target must be on screen before the detach window opens.** Wall-to-wall chains live in narrow authored canyons with the camera looking down the slot; the blob shadow projects onto the active surface; the landing ring draws on the detach target. The author-time lint gains these checks.

**Operator decision, 2026-07-23:** for wall-run the down-the-slot shot is authoritative. The side-on 3/4 wording describes the alternative considered and not taken. Readability for the slot shot is guaranteed by detach-target visibility, not by tangent-horizontal.

**Operator camera decision, 2026-07-23:** keep the down-the-slot position, but reject the wall-as-floor roll after device feedback found it disorienting. The wall-run camera keeps a stable world-up horizon through attach, run, and detach; a small authored bank remains optional only inside the camera comfort band.

- **Rope swings** get side-on cameras (they are 2D pendulums; filming them side-on is just correct) and exist mostly in chain set-pieces.
- **The grammar consequence.** v0.1's segment types (chase-behind, side-on 2.5D, toward-camera, room, branch loop, vertical shaft) gain three entries: *grind*, *wall-run*, *swing-chain*. A designer who wants a wall-run buys it with a camera region, the lint enforces readability, and everywhere else the original corridor rules hold untouched. If this hybrid had failed conceptually, the fallback would have been a Crash-4-style soft-follow camera with all its touch problems — it isn't needed, and I'd argue against it even if asked.

**Phase-shift and the camera:** none needed — phase changes object state, not player traversal. Its readability burden is handled by rendering the inactive set as constant ~30% ghost outlines (you always see both worlds; you never guess what a toggle will do). That's one extra outline pass, budgeted in §9.

### 5.6 What phase-shift really costs (honest accounting)

Phase-shift is not "a second copy of every level." In Crash 4 it toggles designated blue/orange *object sets* — crates, platforms, hazard emitters — not duplicate environments. Real costs: phase segments are authored roughly 1.4× (two interleaved object layouts that must both be fair, plus their intersection); testing on those segments doubles (both states × both lines); one global ghost-outline shader + material discipline (cheap, done once); both object sets stay loaded (props, not geometry — memory noise). Containment: **phase appears in Warp Rooms 4–5 and in earlier levels' full-kit lines only** — roughly 8 of 25 levels touch it. At that scope it's the best mechanic in the back half of the game for the price of ~2–3 levels' worth of extra authoring. Globally applied, it would be a scope bomb; scoped, it ships. (Fallback position in §13 if the schedule collapses.)

---

## 6. Level design system and THE LIST

### 6.1 Segment grammar (carried + extended)

Levels are spines of reusable authored segments (10–30s each) snapped to the 2m grid, each owning its camera region: chase-behind (default; ~30–35° depression, FOV ~55°), side-on 2.5D, toward-camera (chases only), room, branch loop (forward-rejoining), vertical shaft, **grind**, **wall-run**, **swing-chain**. A level = 6–10 segments, 2–3 checkpoint crates, intro→twist→combine→crescendo cadence, 2–4 min first clear. Crate rhythm: a beat every 2–4s on the intended line; a trail bending off-spine always means something.

### 6.2 The 25 — picks, justifications, and the warp-room curve

Selection criteria, in order: (1) the pacing/variety curve of the *combined* game, (2) mechanic coverage without redundancy, (3) **art-set economy** — with a solo self-modelling artist, every level pick is an art-budget decision, so each warp room is built around one or two environment kits and levels are chosen to share them. Crash 3 is where art sets explode (every level a new theme), which is why it's contained to one warp room and its Egypt and Arabia themes die entirely.

**Warp Room 1 — N. Sanity Island** *(C1; kits: jungle/beach + temple-ruins + rope-bridge sub-kit)*

| Level | Why it earns the slot |
|---|---|
| N. Sanity Beach (C1) | The most famous opening in platforming; the natural tutorial; establishes beach→jungle in one kit |
| Boulders (C1) | The toward-camera chase archetype, introduced early and cheap (one boulder, existing corridor) |
| Hog Wild (C1) | The ride archetype — forced-run steering on the existing controller; the game's first tempo spike |
| The Lost City (C1) | Peak C1 box-precision platforming; the wall-density level; natural home of a colored gem line |
| Road to Nowhere (C1) | The bridge level: iconic, and the showcase for the depth stack on into-screen rope gaps; its famous rope-walk skip becomes an *intended* expert line |

Boss: **Papu Papu** (jungle set). — Room difficulty: gentle→spiky; teaches every base verb plus ride and chase literacy.

**Warp Room 2 — Frozen Wastes** *(C2; kit: snow/ice)*

| Level | Why |
|---|---|
| Snow Go (C2) | Ice traction as a mechanic, introduced kindly; the infamous hidden red gem becomes an honest full-kit line |
| Snow Biz (C2) | Ice + Nitro cadence escalation; same kit, zero new art |
| Bear It (C2) | The bear ride — second ride archetype, faster than the hog; pure joy level |
| Un-Bearable (C2) | The reverse: chased *by* the bear toward camera; the trilogy's best chase gag (baby bear payoff kept) |
| Cold Hard Crash (C2) | The death-route monster; the room's mastery exam and the game's first brutal relic |

Boss: **Dingodile** (C3 — his crystal snowfield arena is canonically snow; the one C3 boss whose art set is free here). — Grind rails seed here (frozen pipelines) for relic lines.

**Warp Room 3 — Ruins & Rivers** *(C1+C2; kits: night-jungle variant + river + ruins)*

| Level | Why |
|---|---|
| Turtle Woods (C2) | Night-jungle mood shift (lighting variant, not a new kit); `!`-crate and burrow pacing; the breather opener |
| Air Crash (C2) | The river level; its jetboard hops are **rebuilt as rail-grind segments over water** — the remix earning its name; secret-warp tradition kept as a hidden branch |
| Road to Ruin (C2) | The definitive C2 ruins gauntlet; branch-loop showcase |
| Plant Food (C2) | The timed-race variant (beat the water, feed the plant) — a pacing shape no other pick covers |
| Sunset Vista (C1) | The vertical ruins marathon — the trilogy's grandest single level, re-tuned into this room's crescendo (its C1 length survives because checkpoints are humane now) |

Boss: **Ripper Roo** (C1/C2 — waterfall/TNT-lilypad arena shares the river kit; the fight is already a crate-logic puzzle, i.e., the only PS1 boss that matched the game's own systems). 

**Warp Room 4 — Cortex's Machine** *(C1+C2; kits: gothic castle + lab/space)* — **phase-shift unlocks here** (Cortex's quantum experiments; PHASE button appears).

| Level | Why |
|---|---|
| Slippery Climb (C1) | The best pure platforming level Naughty Dog built on PS1; rain-slick gothic vertical; keeps its teeth re-tuned |
| Lights Out (C1) | The Aku-Aku-as-light-timer level; darkness as pressure; shares the castle kit outright |
| The Lab (C1) | C1's closer aside from the Great Hall; electricity cadence + lab assistants; introduces the lab kit |
| Piston It Away (C2) | Machine-rhythm platforming at its purest; lab/space kit shared |
| Spaced Out (C2) | C2's finale remixed as this room's exam: machine rhythm + phase objects + full-kit lines |

Boss: **Tiny Tiger** (C2 space-station collapsing-floor fight — shares the space kit; already half a gauntlet, finished properly in §8).

**Warp Room 5 — Time Twister** *(C3; kits: medieval + future, prehistoric chase sub-kit)*

| Level | Why |
|---|---|
| Toad Village (C3) | The gentlest, most charming opener in the series — the calm before the finale; medieval kit intro |
| Gee Wiz (C3) | Medieval kit exhausted properly: wizards, catapult-crate cadence, the room's platforming spine |
| Bone Yard (C3) | The dino chase — the series' most iconic toward-camera terror; costs a prehistoric sub-kit + one triceratops model and is worth both |
| Future Frenzy (C3) | The future kit: conveyor/laser rhythm, the trilogy's best late-game corridor |
| Gone Tomorrow | Future kit part two; phase-shift's densest playground; the last ordinary level and the hardest |

Boss: **Cortex** (three-phase finale: a chase phase, a classic pattern phase, and a phase-shift duel that turns the game's own late mechanic into the final exam).

**Bonus wing** (unlocked by colored gems + relics; **zero new art by construction**): Stormy Ascent (the legendary cut C1 level — castle kit), The High Road (bridge kit; the rope-walk line now mandatory), Whole Hog (hog systems), Totally Bear (bear systems), Fumbling in the Dark (Lights Out kit). Five levels of endgame for free.

**Sacred cows cut, on the record:** Hang Eight and all jetski/plane/bike/sub levels (vehicles — see §2.6), Native Fortress and Ruination (redundant with stronger picks in their kits), the entire Egypt theme (Tomb Time, Sphynxinator, Tomb Wader — a full art kit for one room's worth of levels; Tomb Wader's rising-water idea is folded into Plant Food's timing DNA), the entire Arabia theme (High Time, Hang'em High — same reason), Orient Express/Hot Coco/Rings of Power (vehicles again), the sewer set (The Eel Deal, Sewer or Later — the machine rooms are better served by castle+lab), and Crash 2's jetpack levels (a sixth controller). Each cut is an art kit or a controller that no longer has to exist.

**Count:** 25 levels + 5 bosses + 5 bonus = 35 playable. First-clear runtime ≈ 4–5 hours; completion 12+.

### 6.3 Chases and rides

Toward-camera chases (Boulders, Un-Bearable, Bone Yard) keep the fix from v0.1: obstacles telegraphed by blob shadows and ground-edge highlights entering frame before the geometry does; wider corridors; binary left/right reads. Rides (Hog Wild, Bear It, Whole Hog, Totally Bear) are forced-run steering + jump on the standard controller — the one place auto-run is correct, and the accessibility-friendly "pure steering" levels.

### 6.4 Secrets

Canon grammar: hidden branches and peel-offs marked by crate trails; death routes (reach the platform deathless — the one *earned* no-death mechanic, kept as-is on Cold Hard Crash and Road to Ruin at minimum); colored gem lines = the full-kit routes (§3), one per warp room, five total; secret warps in Air Crash tradition. Butterfly tells from v0.1 are replaced by the canon signal: a suspicious crate where no crate should be.

---

## 7. Progression and metagame

**7.1 Hub.** The warp room, Crash 2 style: five chambers of five level portals + boss platform, unlocked by clears (any completion). Walkable trophy room — gems glitter on portals, relics on plinths — but never mandatory: a two-tap level list overlays from anywhere. Cold start <8s on the reference device; hub→level <3s via threaded loading.

**7.2 Per level, canon-mapped:** **Gem** = all crates, *deaths allowed, crates persist across deaths within the run* (the one deliberate canon divergence, stated once: the compound no-death gem was the trilogy's hostile mistake); checkpoint sweep counters show each segment's box count, and a missed crate's segment is shown on the results screen with a ghost marker on replay. **Relics** = time-trial mode with the canon stopwatch pickup and yellow time crates (−1/−2/−3s), sapphire/gold/platinum tiers — par times authored from the developer's own runs +10%, re-tuned after friends play, and living in tuning data not code. **Flawless flag** = no-death clear, tracked and displayed, gating nothing — the purist's medal. **Colored gems** (5) sit at the end of the full-kit lines. Bonus wing unlocks at colored-gem and relic thresholds; a true-finale Cortex phase at 20+ gold relics.

**7.3 Wumpa:** ~150–250 per level; 100 auto-summons an Aku Aku; lifetime total unlocks the gallery (concept art, i.e., the operator's own Blender progression — which by the end of this project will be genuinely worth exhibiting) and skins (Coco from the start; costume variants as art-track warmups).

**7.4 Difficulty: one difficulty + assist menu** (Celeste model, and Crash 4's modern mode in spirit): game speed 85/90/100%, start-with-mask, infinite-mask (results marked "assisted"), landing-assist strength, chase checkpoint density. No difficulty tiers — they triple tuning surface and dodge the question.

**7.5 Mercy, visible:** 3 deaths at one checkpoint → Aku Aku at respawn; 6 → offer skip to next checkpoint (run becomes gem/relic-void). This is Naughty Dog's hidden DDA made honest — hidden helper systems read as patronizing when friends compare notes, and they will.

---

## 8. Enemies and bosses

**8.1 Enemies.** Canon rule kept: placement is the puzzle — one-hit deaths, silhouette telegraphs, every enemy answerable by ≥2 verbs. Roster budgeted at **~13 rigged types + costume variants** (§9 counts them), leaning hard on Naughty Dog's own economy trick: the **lab assistant is a reusable rig re-costumed per world** (native, snow-parka, sewer-tech, castle, future — five looks, one skeleton, shared animations). Per room: WR1 crab, skink, native + plant; WR2 penguin, seal, spiked turtle; WR3 turtle (shared), sweeper plant, monkey; WR4 lab assistants ×2 costumes, rat-bot, shock drone; WR5 knight + wizard-frog (medieval), lab-bot (future, reskin), raptor (chase-adjacent). Composition escalates difficulty, never HP.

**8.2 Bosses — canon roster, gauntlet philosophy.** The PS1 fights were flat arenas below the surrounding levels' difficulty. Rule set from v0.1, applied to the real cast: each boss is a 3–4 minute **gauntlet** using only standard verbs, damage dealt by turning the arena against them, three phases each a real twist, checkpoint per phase, difficulty ≥ its warp room:

1. **Papu Papu** (WR1): the belly-bounce fight rebuilt as a collapsing-hut gauntlet — his slam shockwaves are the platforms' percussion; you climb the hut as he demolishes it.
2. **Dingodile** (WR2): flamethrower + crystal field kept, extended with an approach phase across melting ice while he snipes, then the canon crystal-shield arena, then a chase out.
3. **Ripper Roo** (WR3): the TNT/Nitro lily-pad puzzle kept nearly intact (it was always the best one), plus a phase-3 rhythm escalation on mixed TNT/Nitro timing.
4. **Tiny Tiger** (WR4): the collapsing space-floor fight finished properly — his leaps break the floor *behind you* into a rolling gauntlet; final phase adds phase-shift platforms.
5. **Cortex** (WR5): chase phase (fleeing through the collapsing Time Twister), pattern phase (canon mine-laying hover fight), then a phase-shift duel where his shots and your platforms occupy opposite quantum states. 20+ gold relics adds a true-finale coda.

---

## 9. Art — the operator models everything (rewritten from scratch)

No commissioning. The operator self-models every asset in Blender, learning as he goes. This section is a production plan, and it opens with the number that decides the project:

### 9.1 The character count

Rigged, animated characters this scope demands: **Crash** (the hardest asset in the game), **Coco** (shared rig + retarget, ~80% clip reuse), **Aku Aku** (a floating mask — trivial, no real rig), **5 bosses** (each unique rig + unique moveset animation — each is hero-grade work), **~13 enemies** (+5 lab-assistant costume variants on one rig), **3 rideables** (hog, adult+baby polar bear — quadruped rigs, the hardest rigging in the project — and the triceratops, animation-simple but big). **Total: ~23–24 rigged characters.** That is the load-bearing number in this document.

### 9.2 Learning order (sequenced so failures are cheap and skills compound)

1. **Blender bootcamp via the crate** (~30–40h incl. fundamentals): model, UV, hand-paint, and break-animate the standard crate family. The crate is the perfect first asset — it's the most-seen object in the game, it's a box, and its break *feel* matters more than any environment.
2. **First environment kit — jungle** (~40–60h, first-kit slow): 15–20 modular pieces + trim sheet. Modelling without rigging; immediate payoff in the Phase 1 slice.
3. **First character — a lab assistant, NOT Crash** (~30–40h): simple biped, low expectations, Rigify rig, first weight-painting, first walk cycle. Learning rigging on the mascot would poison the most important asset with first-timer mistakes.
4. **Crash himself** (~80–120h: model, rig, and the ~20-clip set): see 9.3.
5. **Enemy production line** (~12–20h each once fluent; Mixamo retarget for biped locomotion cuts animation time ~40%, with signature attacks hand-keyed).
6. **Rideables** (~20–30h each; quadruped rigs and gaits are genuinely hard — budget a throwaway practice quadruped first).
7. **Bosses last** (~30–50h each), when skill is at peak — they're the second-most-seen characters in the game.

### 9.3 Hitting Crash — the likeness problem

v0.1's original mascot could look however the operator's skill allowed. Crash cannot: **everyone can picture him, so every deviation reads as error.** This raises the character-art bar precisely where the artist is greenest. Mitigations: draw orthographic reference sheets from screenshots before modelling (front/side/top — an evening's work that saves twenty hours of eyeballing); target **PS1-era proportions with modern surfaces** — the chunky trilogy silhouette (oversized head and hands, tiny torso, big shoes), matte hand-painted textures, painted-on fur suggestion — and explicitly *not* the N. Sane Trilogy's detailed fur, which is both mobile-hostile (shells/cards) and skill-hostile. The PS1 proportions are *easier to model*, more readable at phone size, and more distinctive. Budget: ~10–12k tris, one 2048 texture.

**The likeness gate (hard, cheap, early):** before any level-art production begins, show three friends the untextured Crash model cold. **All three name him unprompted or the model iterates.** This is the art-track equivalent of the feel gate — it stops six months of environment work from being built around a mascot that reads as "off-brand orange thing."

**Animation set for Crash** (~20 clips, and these carry the game's personality): idle + bored-idle gag, run, jump, double jump, spin (ground/air), crouch, crawl, slide, slam, wall-run, grind (3 poses), swing, phase-flash, hit, win, and **4–6 death gags** — the trilogy's deaths were funny, which is half of why its difficulty was tolerable; they are not optional polish, they are the difficulty system's public face.

### 9.4 Environment kits and the budget

Kits demanded by §6.2's list: jungle/beach, temple-ruins, bridge (sub-kit), snow/ice, river, ruins (C2 flavor — shares DNA with temple), night-jungle (lighting/palette variant, not a kit), castle, lab/space, medieval, future, prehistoric (chase sub-kit). **≈8 full kits + 3 sub/variants**, at 20–40h each after the first.

Performance budget carried from v0.1 (reference device: SD 778G / Dimensity 900 class): 60fps target with 1% low ≥50 and a 30fps user cap; ≤120 draw calls typical/180 peak; ≤150k visible tris typical/250k peak; Crash 10–12k, enemies 3–6k, bosses 15–25k tris; 1–2×2048 atlases + trim sheet per kit, ASTC; **all lighting baked** (LightmapGI per segment) + blob-shadow decals doing double duty as the Pillar-1 aid; tonemap-only post **plus the phase ghost-outline pass** (budgeted: one extra low-cost pass on phased-out objects, WR4–5 only); pipeline pre-compilation/shader baker to kill Vulkan first-run stutter; 20-min thermal soak in every gate; dynamic resolution 1.0→0.7 before any frame drop; arm64-v8a only; APK estimate 150–250MB.

### 9.5 The honest hours

| Track | Hours |
|---|---|
| Bootcamp + crate family + props | 30–40 |
| Environment kits (8 + variants) | 240–340 |
| Lab assistant (first character) | 30–40 |
| Crash (model+rig+clips) | 80–120 |
| Coco (skin+retarget) + Aku Aku | 20–30 |
| Enemies (~13 + variants) | 160–260 |
| Rideables (3, quadruped) | 60–90 |
| Bosses (5) | 150–250 |
| VFX, UI art, gallery | 40–60 |
| **Art total** | **≈ 800–1,200h** (≈700–1,000 with aggressive Mixamo/base-mesh acceleration) |

Legitimate accelerators that keep "self-made" true: CC0 base meshes and kits for *graybox only* (final assets his), Mixamo retargeting for biped locomotion, texture-painting from photographed hand-painted swatches. Not legitimate: extracting anything from the PS1 discs or N. Sane Trilogy — restated once because the temptation will recur at hour 400.

At a realistic ~8 art-hours/week inside a 10–15h/week total budget, the art track alone is **100–150 weeks — two to three years — and it is the project's critical path.** Code (agent-driven) and design will idle waiting for assets, not the reverse. §12 and §13 are built around this fact.

---

## 10. Audio — original, in the Mancell style

**The style, defined for briefing a composer or an AI music tool.** Josh Mancell's trilogy scores (with Mutato Muzika) are: loop-based cues of ~1:30–2:30; groove-first and harmonically static (one or two chords per cue — the *percussion is the harmony*); dense layered hand percussion (congas, bongos, timbales, log drums, djembe, cowbell, shakers) under marimba/xylophone/steel-drum melodic leads; funky clavinet and organ stabs; tight bass ostinatos; near-total absence of pads and strings; playful cartoon "mickey-mousing" gestures; and one quirky signature instrument per theme (theremin-ish synths in labs, harpsichord in castles, didgeridoo-flavored drones on the islands, tuned pipes in ruins). Tempo ~100–130. One-line brief: *"60s–70s exotica-funk percussion ensemble meets Saturday-morning cartoon scoring: marimba lead, groove ostinato, no pads, one weird instrument per level."* Needed: ~12 cues (5 warp-room moods ×2 flavors is overkill — one per kit family ≈ 8 level cues, + boss, + warp room, + jingles).

**SFX carries platformer feel** — and the iconic ones (crate pop, wumpa slurp, Aku Aku's invocation, TNT tick, Nitro touch) must be **original soundalikes**, not rips: the crate pop is a layered wood-snap + pitch-up blip anyone can synthesize; Aku Aku's voice is the operator recording gibberish through formant shift, which is also canonically how such voices were made. Footsteps per surface (also a depth/position cue), landing thud scaled to fall height, distinct jump/double-jump pops. Pitch-randomize repeats ±5%. `AudioStreamInteractive` (4.3+) for chase-intensity layering. Assume muted play is common: every critical audio cue has a visual/haptic twin.

---

## 11. Technical architecture in Godot 4 (carried from v0.1; deltas marked)

**11.1 Version:** pin latest stable 4.x at start (4.7.1 as of this draft — verified; 4.6 Jan 2026, 4.7 June 2026); upgrade only at phase boundaries.

**11.2 Renderer: Mobile (Vulkan).** Forward+ is wasted on an all-baked game; Compatibility is the old-device fallback with worse fit. Min spec: Vulkan-capable Android ~10+ (2019-era). Unchanged.

**11.3 Language: GDScript, statically typed, enforced.** C# Android export has been export-capable since 4.2 but long experimental-labeled (arm64/x64, .NET 7+; could not verify the label's removal even in 4.7); GDScript keeps the hot-reload/on-device tuning loop frictionless, which is the whole anti-Reaper-Rush strategy; perf-critical work is engine-side C++ regardless; GDExtension is the escape hatch. Unchanged.

**11.4 The tuning system — first-class, live from day one.** Carried verbatim in intent; this is the anti-dead-wire architecture and the project's most important non-obvious system. Every gameplay number in typed custom `Resource`s (`MoveTuning`, `CameraTuning`, `InputTuning`, `EconomyTuning`, per-enemy and per-boss tuning, per-level `LevelMeta` with par times and box counts — now including per-verb resources for wall-run/grind/swing/phase). No numeric gameplay literals in scripts, enforced by pre-commit grep-lint. **Dead-wire tripwire:** debug builds dump every loaded tuning resource path + a fingerprint hash of all values to an on-screen HUD; change a value, redeploy, hash unchanged → dead-wired, caught in ten seconds. **On-device live panel:** sliders bound to the live shared resources; save writes `user://tuning/override.tres`; boot loads overrides under a red OVERRIDE ACTIVE watermark; `adb pull` returns blessed values to the repo. **Phase 0 acceptance test (blocks the feel gate):** repo-edit → redeploy → verify on device; on-device edit → restart → verify persistence; fingerprint moves both times. All three or the tuning system does not exist, whatever the code claims.

**11.5 Scene architecture** (delta: new segment types and the phase system):

```
game.tscn                  # root FSM (boot/warproom/level/pause), loader, save
  player.tscn              # CharacterBody3D + FSM + AnimationTree + blob shadow + landing ring
  camera_rig.tscn          # Path3D rail + CameraRegion volumes; new region archetypes: grind, wallrun, swing
  input_touch.tscn / input_pad.gd    # unified buffered InputIntent
  phase_state.gd (autoload)          # flips blue/orange sets: visibility+collision by group; drives ghost-outline shader
levels/wr1_road_to_nowhere.tscn      # spine of segment instances + LevelMeta.tres
segments/seg_bridge_gap_a.tscn       # geometry + lightmap + camera region + crate spawners (+ phase groups where used)
props/crate_*.tscn (inherit breakable.tscn)   # standard/TNT/Nitro/!/bounce/iron/checkpoint/aku/time
enemies/*.tscn (inherit enemy_base.tscn)      # lab_assistant.tscn + costume variant resources
data/tuning/*.tres         # single source of truth
```

Rails and wall-strips are `Path3D`-based nodes the author-time lint understands; the lint (headless) checks the ≥15° rule, the wall-run substitute rule (§5.5), detach-target visibility, checkpoint spacing ≤60s, and crate counts vs `LevelMeta`.

**11.6 Physics: Jolt** (built-in since 4.4; extension in maintenance — verified). `CharacterBody3D` + `move_and_slide`; hand-integrated arcs (designed curves, not simulation); 60Hz physics + 3D interpolation. Wall-run/grind implemented as spline-constrained states, not physics — the solver only resolves collision. Unchanged in substance.

**11.7 Save + lifecycle:** carried verbatim — schema-versioned JSON at `user://save/profile.json` (gems, colored gems, relic tiers, flawless flags, wumpa, settings), atomic temp+rename writes on level end and app-pause, `.bak` of last good; on `NOTIFICATION_APPLICATION_PAUSED`, auto-pause and snapshot for exact mid-run resume — interruption is the normal mobile case.

**11.8 Testing:** GUT for pure logic (FSM transitions, buffer/coyote simulated headless, relic math, save round-trip/migration, box counts, **phase-state invariants**: both sets never simultaneously solid, toggle cooldown honored); the literal grep-lint; the author lint. Feel remains untestable by machine — that's what §12's human gates are for.

---

## 12. Build roadmap (recomputed for maximum scope)

Assumes 10–15 operator-hours/week total, of which ~8 go to the art track once it starts (it starts week 1 and never stops — **art is the critical path**; the agent-driven code track idles for assets, not vice versa). Hard rule carried and non-negotiable: **the operator plays every build on device at least weekly; no agent self-certification, ever.**

**Phase 0 — Base-kit feel toybox (weeks 1–4).** Graybox gauntlet + stick/buttons (JUMP/SPIN/DOWN) + run/jump/double/spin/crouch/slide/slam + camera rail + blob shadow + landing ring + **the full tuning system and its acceptance test** + one-click deploy. Art track in parallel: bootcamp + crates.

> **GATE F — base feel gate (unskippable, human-only).** On a real mid-range phone, via touch: (1) touch→response ≤100ms, 240fps-camera measured; (2) 60fps through a 20-min thermal soak, dynamic res never below 0.7; (3) 10 consecutive into-screen jumps onto 1.25-character pads, ≥8/10 by attempt three; (4) slide-jump chain across 3 authored long gaps, clean by attempt five; (5) blind-transfer: one friend clears the tutorial strip with zero instruction; (6) operator plays ≥20min on 3 separate days and honestly wants to come back; (7) tuning acceptance test green. **The coding agent cannot certify this gate. Only the operator, on device, by thumb.** Fail → iterate or kill the project at week-4 cost. This clause is the Reaper Rush lesson and must survive every future simplification.

**Phase 0.5 — Traversal toybox (weeks 5–8).** Wall-run, grind, swing, PHASE button + phase objects, in graybox segments. **GATE F2:** wall-run attach→detach onto a pad ≥4/5; a 3-rail hop sequence clean by attempt five; phase-toggle mid-jump gauntlet ≥8/10; camera never disorients the blind-transfer friend during a wall-run (asked, not assumed). Art track: jungle kit, lab assistant.

**Phase 1 — "Island Cut" slice (months 3–8).** N. Sanity Beach, Boulders, Hog Wild fully built; crates/gems/relics/mercy loops; warp room v1; save; **Crash himself passes the likeness gate (§9.3) before level-art production**; hog + 3 enemies + Papu Papu. **Release: Island Cut** to friends — 4 playable pieces, the game's thesis proven or disproven. Realistic landing: **month 6–9** (Crash's 80–120 art hours dominate this phase).

**Phase 2 — Warp Room 1 complete (months 9–12).** The Lost City, Road to Nowhere, colored-gem line, bonus-wing scaffold. Release 0.1.

**Phase 3 — Warp Room 2 (months 13–17).** Snow kit, bear rig (the quadruped wall), Dingodile, grind lines. Release 0.2. → **DECISION POINT (see §13): re-read the verdict here with real velocity data.**

**Phase 4 — Warp Room 3 (months 17–21).** River + ruins kits, Ripper Roo, Sunset Vista (the re-tuning stress test).

**Phase 5 — Warp Room 4 (months 21–26).** Castle + lab kits, phase system in production, Tiny.

**Phase 6 — Warp Room 5 (months 26–32).** Two kits (medieval, future) + prehistoric chase + triceratops + Cortex finale — the most expensive room, placed last when skills peak.

**Phase 7 — Bonus wing + polish (months 32–35).** Stormy Ascent et al. (zero new art), assist menu completion, perf/battery pass on every friend device, gallery.

**Honest total: ≈ 32–40 months. Call it three years, part-time.**

---

## 13. Risks and honest assessment

**Ranked by what actually kills it:**

1. **The 24-character art wall (the new #1, by a distance).** ~800–1,200 self-taught art hours, of which ~500 are rigged characters, learned from zero, at 8h/week. This is not a risk *in* the plan; it nearly *is* the plan — every other track waits on it. Mitigations are structural: the learning order (§9.2) makes early failures cheap, the likeness gate stops sunk-cost disasters, the lab-assistant costume trick and Coco-as-skin cut the count, bosses come last when skill peaks, and the level list itself was chosen to minimize kits. But no mitigation changes the arithmetic — only the scope cut ladder below does.
2. **The content wall.** 25 levels is where solo platformers die even *with* purchased art. Same mitigation as v0.1: shippable increments (Island Cut at month ~6–9, then per-room releases), plus the segment kit maturing over time.
3. **Touch feel never converging.** Retired (or project killed) by week 4 at Gate F — the single best trade in this plan, unchanged.
4. **The likeness bar.** Matching a character everyone can picture, as a first-time character artist. Contained by the likeness gate and the PS1-proportions target; residual risk: Crash reads "off" in motion even when the model reads right — animation polish on the ~20-clip set is where this bites, and the weekly on-device play is the tripwire.
5. **Agent-built ≠ played** — the Reaper Rush failure mode. Answered structurally (human-only gates, weekly play, tuning fingerprint, literal-lint); the residual risk is process discipline: the rules only work if never waived "just this once."
6. **Engine churn.** Three minor Godot releases in ~16 months; pin per phase, upgrade at boundaries only.

**The cut ladder, in order:** bonus wing → Warp Room 5 shrinks to one kit (drop medieval; Toad Village/Gee Wiz die, future carries the finale) → **phase-shift** (the most cuttable mechanic: it multiplies authoring and arrives latest; cutting it reduces WR4–5 to standard corridor work and deletes a button) → Warp Room 5 entirely (20-level game, Tiny becomes the final boss with a Cortex chase epilogue) → Warp Rooms 4–5 both (**the 15-level "Trilogy Sampler," which is a complete, honest game**). **Never cut:** the feel gate, the likeness gate, the depth stack, crate persistence across deaths, respawn speed. Those are the game.

**The blunt verdict.** The operator has taken the maximum-scope option on all three forks — 25 rebuilt levels, the largest moveset in the series' history, and self-taught solo character art — and the honest recompute is **~3 years part-time, roughly double v0.1's estimate**, with the art track as sole critical path. The base rate for a solo, three-year, learn-art-as-you-go fan project reaching level 25 is low — I'd put it under one in five, and I'd be doing the operator a disservice to dress that up. The plan therefore delivers the full 25 as asked, but is *shaped* so that three smaller games fall out of it whole: **Island Cut** (month ~6–9; 4 pieces; proves the thesis), **Warp Rooms 1–2** (month ~17; 10 levels + 2 bosses; a real game), and the **15-level Trilogy Sampler** (month ~21; my recommended true target). Build to the end of Warp Room 2, hand it to friends, and let their faces — and the measured velocity of Phases 1–3 against this schedule — decide whether rooms 3–5 exist. That decision point is where this paragraph gets re-read, with data.

---

## 14. Open questions for the operator

1. **Level list sign-off.** The 25 + 5 bosses + 5 bonus in §6.2 — specifically the cuts: all vehicles (Orient Express, Hot Coco, Rings of Power, Hang Eight), all of Egypt and Arabia, and the sewer set. Losing Orient Express and Sphynxinator will hurt if they were personal favorites. **Rec: hold the line — every reinstated theme is a full art kit (~30h+) plus level authoring on the critical path; trade one-for-one against a listed level if it must happen.**
2. **Contextual-verb split sign-off.** Wall-run/grind/swing auto-attach with no dedicated buttons; phase gets the fourth button. **Rec: as specced; the mitigation ladder in §5.2 exists if Gate F2 disagrees.**
3. **Phase-shift: scoped or cut?** WR4–5 + full-kit lines only, ~8 levels. **Rec: keep scoped — it's the best back-half mechanic per authoring hour; it's also rung 3 of the cut ladder and dies without ceremony if velocity says so.**
4. **Other Quantum Masks confirmed dead** (time-slow, dark-spin, gravity-flip)? **Rec: cut, per §4.2 — each is either a feel hazard on touch or a scope bomb.**
5. **Art interpretation:** PS1-proportions-modern-surfaces vs chasing the N. Sane look. **Rec: PS1 proportions, emphatically — easier, more readable at phone size, mobile-friendly, and more charming.**
6. **Art learning sequence:** agree Crash is model #4, not #1, and the likeness gate blocks level-art production? **Rec: yes on both; this is the cheapest insurance in the plan.**
7. **Coco:** playable skin (shared rig/clips) vs distinct moveset. **Rec: skin — a second moveset re-opens every tuning and level-validation question for ~zero design win at this scope.**
8. **Boss roster:** Papu Papu / Dingodile / Ripper Roo / Tiny / Cortex, with Pinstripe and N. Gin absent. **Rec: as listed (arena art sets come free with their rooms); Pinstripe is the one worth re-adding as a bonus-wing arena if you miss him — his fight is cheap (one room, one rig).**
9. **"Remix not restoration" accepted?** Re-tuned geometry, unified difficulty, full kit everywhere, challenge relocated to full-kit lines (§3). **Rec: yes; the alternative — surveyed geometry with per-level verb locks — is both unbuildable (no ripped assets) and worse-feeling.**
10. **Target floor:** Vulkan-capable ~2019+ confirmed against the actual friend-device list? **Rec: Vulkan-only; revisit only if a real device misses.**
11. **True target:** privately commit to the 15-level Sampler with rooms 4–5 as stretch, or hold the full 25 as the plan of record? **Rec: Sampler as the real target, full plan as the map — but this is a motivation question only the operator can answer, and the month-17 decision point exists either way.**

---

*Verification notes: Godot version line (4.6 Jan 2026, 4.7 June 2026, 4.7.1 current), built-in Jolt status (4.4, experimental label, extension in maintenance), C# Android export status (since 4.2, experimental, arm64/x64, .NET 7+), and Mobile-vs-Compatibility renderer guidance verified by web search (this and prior session). Not independently verified: C# experimental-label status in 4.6/4.7, exact shader-baker naming, Crash 4's precise wall-run/grind trigger implementation details (asserted from design analysis of gameplay, not source), and all hour estimates — which are engineering estimates, not measurements. Trilogy level rosters, moveset history, and the Mancell style description are from stable historical knowledge; level picks were made from design memory of the originals, and the operator should veto any pick that doesn't match his own memory of why a level was good.*
