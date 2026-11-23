# Ladder landing: generalization, workbench integration and clearance (follow-up to Codex's `2825402`)

Status: **implemented and measured; one decision needs the owner (section 9). Not committed, not pushed.** Baseline: `2825402` on `main` (Codex's supported exit, on top of my `d69eb11`). Codex's worktrees were not touched.

## 1. What was already working (and is kept)

* Codex's supported exit in the exploration sandbox: the hand-contact sequencing, the lead-foot placement, the weight transfer over the lip, reverse entry from the deck, the contact-specific grips, and `ladder_transfer_demo.gd`. All of its sandbox behaviour is preserved: `exploration_actions_test` (46 checks) and `hand_contact_test` (68) pass unchanged on the refactor.
* The ladder stabilization (`d69eb11`): one `LadderGeometry`, measured `LadderBody`, anatomy-derived windows, planned knees.
* The boundaries: gameplay untouched, presentation only.

## 2. Root causes found

1. **The landing was not independent of the sandbox.** `ladder_landing_pose` took a bare lip offset and a single symmetric "brace posts" vector, set through two loose parameters (`deck_from_rungs`, `brace_posts`). Nothing described the deck's size, which handholds exist, or that a ladder without posts is not a supported landing. Only the sandbox tower could feed it.
2. **The plan said hands held grips they could not reach.** The brace blend ran on a fixed phase schedule; the posts were 1.07 to 1.29 arm lengths from the shoulder during acquisition. The rig quietly lowered the claim weight when out of reach, so the *claimed* wrist always matched its target (error 0.000 m) while the planned grip was out of reach for 34 to 75 samples per run. A wrist-vs-claim measurement hid it.
3. **The knee planner did not know the deck.** It cleared rungs and rails only, so legs sank into the deck or its face (up to 88 mm on a descent before this work).
4. **The pelvis crossed the lip while the trailing foot was still on a rung**, so that leg had to cut through the deck's edge.
5. **The knee stabiliser was frame-rate dependent.** Its turn-rate limit was per second of real time, but a pose is a function of climbed height. A test that advances height per frame in an uncapped run outruns it by up to 100x: the *identical* ladder test gave a 33 mm thigh graze in one run and 37 mm in the next. The "37 mm vs 35 mm" reading that predated the transfer was this, plus a real graze.
6. **The pelvis sway followed a clock, not the feet** (`sin(climbed)`), so the raised leg's hip could be pushed toward its own rail.
7. **The planned shoulder ignored the 43 degree landing lean** in the reach flags. (The lean model itself is within 2 to 3 cm of the real shoulder on both bodies; a larger apparent error was a sampling artifact in my own test, fixed.)

## 3. Implementation

| Change | Files |
|---|---|
| **`LadderLanding`**: one typed description of the top of a ladder (deck lip, usable deck width and depth, genuine handholds as posts or the ladder's own extended rails, source). `unsupported_reason(geometry, body)` says why a landing is not usable (lip outside the reach budget, deck too small for the body, no handhold, a handhold on one side only). A deck with nothing to hold is a **fallback**, never posed as supported. | `presentation/characters/motion/ladder_landing.gd` (new) |
| Rig: `begin_traversal(kind, length, direction, landing)` accepts or refuses the landing and records `ladder.landing_status` ("supported (...)" or "fallback: reason"); host `begin_climb(length, landing, direction)`; the sandbox builds a `LadderLanding.with_posts` from its tower. | `character_rig.gd`, `ladder_climb.gd`, `traversal_pose_input.gd`, `exploration_character_host.gd`, `research/exploration_playground/*` |
| Solver: `ladder_landing_pose(profile, geometry, body, climbed, direction, landing, across)`; palm targets come from the landing's grips; hands are placed after the pelvis and a hand **holds only while its target is within 93% of the arm**; the pelvis stays behind the lip until the trailing foot is up; reach uses the leaned shoulder (`LadderBody.shoulder_leaned`); sway follows the feet (weight onto the lower foot). | `traversal_solver.gd`, `ladder_body.gd` |
| Knees: `LadderKneePlanner.plan/at_turn` take the landing and treat the deck and its face as an obstacle. The turn limit is `360 deg/s + 420 deg/m` of pose travel, so the stance follows the body at any frame rate. | `ladder_knee_planner.gd`, `traversal_pose_modifier.gd` |
| **Workbench** (below). | `tools/animation_workbench/` |

Rejected experiments (kept out of the code): a faster knee turn rate (no change in the numbers), and preferring the narrowest comfortable knee stance (it never found one: the width follows from the foot range and how far back the hands let the pelvis hang, not from stance selection).

## 4. Workbench integration

The workbench now reproduces the complete supported transfer on the **production solver, rig and hand contacts**; there is no demo-only pose.

* Scenario `D  Ladder landing (supported transfer)` (`--scenario=landing`): posts up and reverse, extended rails up and reverse, then two landings that must stay on the fallback (a deck with nothing to hold, a lip too far).
* Manual controls (Scenario tab, Ladder section): posts / rails up and down, deck only, lip too far, deck too small, across 0 / 0.5 / 1, hold at the lip, interrupt. Existing pause, single-frame step and reset apply.
* New **"Ladder landing (final pose)"** section on the Diagnostics tab (read-only): the rig's landing status, climbed height and landing phase, knee spread, and, for the ladder bars and for the deck, how many millimetres each of knee, thigh, shin, torso and sole is inside, naming the worst part and side.
* `LandingFixtures` (`tools/animation_workbench/landing_fixtures.gd`) builds each landing and its drawing from a name, so the same configurations reach the tests and the captures.
* Reproduce: `godot --path . res://tools/animation_workbench/pose_workbench.tscn -- --character=small_mira_0 --unarmed --scenario=landing` (and `--character=mira_0`, with or without `--unarmed`).

## 5. Diagnostics improved

`presentation/diagnostics/ladder_clearance.gd` (`LadderClearance`, moved from `tests/support/ladder_metrics.gd`, now read-only, no private rig access): final-pose joints, limb volumes against rungs, rails and the **deck solid** (knee, thigh, shin, soles from the ankle and toe bones), knee spread, wrist-vs-grip, and a readout that names the part, side, phase and landing status. The workbench panel and `ladder_climb_test` / `ladder_landing_test` use the same code. Lessons recorded as test design: measure the wrist against the **planned** grip, not the claim; read pose and joints from the **same** frame; drive progress by measured frame time, and run the same transfer at 30 fps and uncapped.

## 6. Shared architecture (evidence)

* One solver and one rig produce the pose in: the exploration sandbox (`exploration_actions_test`, 46 checks), the workbench (`workbench_landing_test`, 60 checks, both bodies, armed and unarmed), and the landing test's stand-in host (`ladder_landing_test`).
* The landing is plain data: the three hosts differ only in where the `LadderLanding` comes from. Boundary gates A to D pass (1500+ checks); the landing class sits in the neutral motion layer and imports nothing from gameplay.

## 7. Tactical status (distinguished, not implemented)

| Question | Answer |
|---|---|
| Missing shared capability? | **No.** The same rig call (`begin_traversal(..., landing)`) works from the tactical adapter. |
| Missing environmental metadata? | **Yes.** The authored ladders (`maintenance_ladder_3m/4m.tscn`) end at deck level: no posts, no rail extension, and no landing description on the parcels (`ladder_local_bottom/top` only). There is no trustworthy handhold geometry, and inventing one would be fabricating an invisible handhold. |
| Context-host integration gap? | **Yes.** `TacticalCharacterAdapter._tick_traversal` feeds `set_traversal_progress(climbed)` only. The route's horizontal segment after the vertical lane would have to drive `across` and the rung-plane shift, and `note_segment` would have to carry a landing. |
| Incompatible with tactical routing or authority? | **No.** Everything is visual: AP, legality, cells, routes and replay are untouched (route trace unchanged below). |
| What enables it | (1) an authored ladder variant whose rails run on above the deck (real geometry) plus node metadata describing the landing, compiled into `TraversalLinkData` as data; (2) the adapter passing that landing and the route's horizontal progress. Until then every tactical ladder keeps the previous exit, and nothing claims otherwise. |

## 8. Measurements

Ordinary climb (`ladder_climb_test`, 51 checks, passes; result is now identical run to run):

| | before this pass (Codex report) | now |
|---|---|---|
| MIRA ascent worst thigh | 29 mm (fixed 60 fps), **37 mm uncapped (fails 35 mm)** | **29 mm in every run** |
| MIRA mean knee spread, ascent / descent | 57.8 cm / | 56.3 cm / 51.2 cm |
| Small MIRA mean knee spread, ascent / descent | | 42.6 cm / 39.3 cm |
| hands in reach, wrist, planted ankle | | 96 to 100%, <= 2.6 cm, <= 1.2 cm |

The knee spread did **not** improve materially: MIRA's knees sit at the rails' limit (55 degrees of outward thigh turn) because the foot range and how far back the arms let the pelvis hang leave no narrower stance that clears the bars; this is a geometry limit of a 0.25 m pitch with these arms, not a stance-selection defect (the narrowest-comfortable-stance experiment found nothing narrower).

Supported transfer (`ladder_landing_test`, both bodies, armed and unarmed, posts and extended rails, up and down; final pose, same-frame sampling):

| | now |
|---|---|
| held grip, wrist vs the PLANNED grip | <= 4 mm (was unmeasurable: the claim hid up to 34 to 75 unreachable samples) |
| planned grip beyond the arm while held | 0 |
| planted deck foot vs foothold | <= 8 mm |
| sole into the deck (joint-based) | <= 12 mm |
| legs into the deck / its face | MIRA up 20 to 36 mm, down 39 to 46 mm; Small MIRA 23 to 28 mm (before: up to 88 mm) |
| legs into the ladder bars during the approach | MIRA up about 50 mm, down 80 to 103 mm (phase 0.54 to 0.67); Small MIRA about 46 mm |
| plan vs actual shoulder | <= 3.1 cm |
| same verdict at 30 fps | yes |
| fallback landings (deck only, lip too far, deck too small) | refused with a reason, pose exactly the height-only climb-out |
| interruption at acquisition and at the lip, armed and unarmed | traversal and contacts released; rifle back in the hands; hands back to the hang |

All limb measurements are **approximations** (capsules with proportional radii, soles from ankle and toe joints), not mesh clearance.

Replay and traces: **route trace re-run on this tree: 853 routes, zero discrete differences, zero float difference** (gameplay untouched). Regression batch, all passing on this tree: traversal solver 40, state 18, rig 14, hand contact 68, ladder geometry 45, ladder climb 51, exploration actions 46, workbench landing 60, workbench scenarios 132, workbench diagnostics 221, presentation authority 24, traversal replay determinism 6, module boundaries 1567, pose ownership 20, unarmed humanoid 30, humanoid portability 69, stair gait 49. The **pose trace was not re-run** (it is expected to differ in the ladder scenarios, which the pelvis sway and landing changes affect); that and the full tier are open.

## 9. What is not done, and the decision needed

* **The landing's clearance goals are not met, and `ladder_landing_test` is committed with the measured values as explicit regression RATCHETS (owner decision, 2026-11-23).** Its constants were first the strict targets (deck 20 mm, bars 35 mm, sole 12 mm) and failed; they are now 50 mm (deck), 110 mm (bars) and 15 mm (sole), just above what is measured, so any regression fails. MIRA's descent still reaches about 46 mm into the deck and about 100 mm into the ladder bars near the top, Small MIRA about 28 mm into the deck. Lowering the numbers is the follow-up (the approach, phase 0.54 to 0.67, where the legs fold between the last rungs and the lip, is the lead).
* **Owner feedback, same day: the free-standing posts "sticking out" were not wanted; the ladder's own rails should run on above the deck as its ending.** The sandbox tower now has exactly that (rails at the rail span and rung plane, 0.9 m above the deck, described by `LadderLanding.with_extended_rails`), and the workbench scenario leads with it; the free-standing posts remain only as a labelled alternative. Small MIRA holds the rail extension for fewer frames than MIRA (the rails are 0.35 m from the axis, farther than its arms like), so a rail grip chosen lower or nearer the shoulder is a follow-up.
* **Stair drift (about 45 mm planted-ankle drift in a lateral crossing)**: not investigated in this pass; no stair change was made.
* Normal-speed moving demonstrations and the matching before/after captures were not produced beyond the still sheets (`docs/claude/images/ladder55/landing-*.png`; use `tools/quality/ladder_transfer_demo.gd` for moving review).
* Top-out reads better with a supported landing, but the unsupported fallback keeps the abrupt exit documented in #55.
* Full tier not run.
