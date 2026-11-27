# Animation and ADDA backlog

A working list, not a plan. Nothing here is scheduled; the owner (Pedro) decides order. Each item says where it came from, so you can tell what was said, what was measured and what is only an idea.

Sources: **[P]** Pedro said it. **[M]** ADDA measured it (evidence in `docs/claude/adda/`). **[I]** an idea, not measured or asked for.

## 1. Movement that looks wrong now

| # | Item | Source | Notes |
|---|---|---|---|
| 1.1 | Sideways movement on stairs gives very small steps | P | Start with an ADDA run of the stairs scenario with lateral input; the stairs bench is a treadmill, so judge steps by foot-to-foothold error and step length, not world position. Possible new finding: step length versus tread depth. |
| 1.2 | Arms do not swing yet | P | Needs a measurable target first: hand swing amplitude per gait cycle, and its phase against the opposite leg. Without a number there is nothing to compare before and after. |
| 1.3 | Cover-entry foot snap | M (R3) | Many bones move at once on entering cover. `--disable=CoverCrouch` does not remove it, so that hypothesis is refuted. Untested: a clip transition that is not cross-faded. |
| 1.4 | Ladder knee pole jumps in the same frame as the knee pop | M (R1) | Written in `traversal_pose_modifier.gd` from `LadderKneePlanner.at_turn`. Cause unknown. |
| 1.5 | Rescue: hand claims full weight while the target is 42 to 50 cm out of reach | M (R2) | `--set=.carry_contacts_enabled=false` removes those findings. Decide whether the claim or the target is wrong. |
| 1.6 | Stairs: small lateral drift (up to 5.5 mm per span) | M (R4) | Probably not a defect; recorded so nobody re-investigates it from scratch. |
| 1.7 | "Lots of animations to fix" | P | Make this list longer as they are found; add each as an ADDA scenario when it is reproducible. |

## 2. Features Pedro described

| # | Item | Source | Notes |
|---|---|---|---|
| 2.1 | Lean and crouch follow cover height | P | Exists in the cover bench. Extend: measure the crouch depth against cover height as a curve, so a regression shows. |
| 2.2 | Hit reaction: the body moves just enough to be hit, so it reads as "tried to peek and was hit" | P | Needs a hit point and a stage that moves the exposed body part toward it. ADDA check: the hit bone ends inside the hit volume, and the rest of the pose changes by less than a limit. |
| 2.3 | Shoot after peeking from a corner | P | Partly present (cover and authorised attack scenario). |
| 2.4 | Ragdoll on takedown: the character falls and reacts to the impact | P | Physics is not bit-exact the way the headless fixed-step runs are. Decide how to measure it (settle time, final resting pose, no limb through the floor) before building. Transition from animation to ragdoll is the risky part. |
| 2.5 | Same procedural approach for exploration mode and base-living mode | P | Each mode becomes a scenario family in the Workbench. |
| 2.6 | Graphics: semi-realistic, cheap tricks by default, heavier effects as an option | P | Future. Godot offers Forward+, Mobile and Compatibility renderers; a quality-tier setting on one set of art is the usual route. Measure per-tier frame cost the way ADDA's overhead tiers do. |
| 2.7 | Roster: mixed-size androids, embedded-weapon frames later | P (earlier) | Thresholds in ADDA were set on two bodies; revisit with each new frame. |

## 3. ADDA: known limits and next steps

| # | Item | Source | Notes |
|---|---|---|---|
| 3.1 | Independent blind attempts at CH07 and CH08 (Pixie/Codex, a human, or both) | M | Open, no deadline. Nobody except the author has run the challenges. |
| 3.2 | A human usability session of the Workbench | M | Open, no deadline. Section 3 of `11-human-workflows.md` lists what to try. The first real use found an editor problem (item 6.1), not an ADDA one. |
| 3.9 | ADDA does not recognise incorrect behaviour, only numerical anomalies (see section 5) | P (review criticism) | State it in the final report's limits. |
| 3.10 | Workbench: events not clickable, no backward step or seek, replay HUD shows PAUSED while advancing, stale findings after a scenario change, grip overlay overlapping panels, camera controls buried, first-screen guidance (G1 to G12 in `adda/13-independent-evaluation.md`) | I (outside evaluator) | Reproduce G2 to G5 first: they could show something untrue. The evaluators' priority order is in section 2 of that document. |
| 3.3 | Mesh sampling is ladder-only | M | Extend to stairs, cover geometry and the weapon. Each needs its own negative control. |
| 3.4 | A persistent offset of a bone with no target is not noticed unprompted | M (CH05) | Known blind spot; found only when asked about the head. A cheap idea: report bones whose pose differs from the animation-only pose all the time. |
| 3.5 | New scenarios: sideways stairs, arm swing, hit reaction, ragdoll | I | Each needs a metric, a threshold and a control before it is a check. |
| 3.6 | Replay is exact only for fixed-step runs | M | Fine for tests; note it for anything physics-based. |
| 3.7 | Workbench status label can show stale values (it refreshes on events, not every frame) | I | Seen as "pace 1.2" next to a speed of 0.0. Cosmetic. |
| 3.8 | The inherited ladder capsule test failures (`ladder_climb_test`, `ladder_landing_test`) | M | Deliberate and documented in `01-baseline`; revisit when the ladder defects are decided. |

## 4. Visual defects (recorded whether or not ADDA finds numbers)

These are judged by looking, not by a threshold. A row here stays open until someone looks at the result and says it is right, even if every ADDA check is green. ADDA's evidence, when there is any, is a pointer, not a verdict.

| # | Defect | Source | ADDA evidence | Status |
|---|---|---|---|---|
| V1 | The climbing cycle continues while the character walks onto a platform (top-out). Every bone moves smoothly; the action is wrong. | P (review criticism) | None expected: no snap, no target error. Not reproduced by me; reported. | open |
| V2 | The Idle button left the character walking in place (state `move` at speed 0, cadence 0.35). | P (seen in the Workbench) | Would not have been found: no discontinuity, no contact error. Fixed in `32477c6`; the check is a state test, not an ADDA finding. | fixed, needs a look |
| V4 | Stair entry: the first steps glide into a bent-knee pose (outside reviewer) | P (via review) | None near the moment except a 30 mm LOW settle. A probe of the foot against the TREAD measured 0.84 m of slide while planted (`tools/quality/stair_tread_probe.gd`). | Workbench part fixed (the bench started the walk 0.83 m early with the idle clip): 840 to 214 mm. Remaining 214 mm is the game's own entry ramp; open. See `adda_reports/20261124-092555-contacts-stair-entry-the-first-steps/INVESTIGATION.md`. Needs a look |
| V3 | The cover wall, ladder and stairs stood together, and the body stayed turned 45 degrees after leaving cover. | P (seen in the Workbench) | None: bench scene state, not a pose. Fixed in `32477c6`. | fixed, needs a look |

## 5. The gap behind them (ADDA)

ADDA detects pose discontinuities and numerical anomalies. It does not recognise **incorrect behaviour**: whether the character performed the action its situation calls for. V1 and V2 are both cases where the numbers are fine and the animation is wrong. This is a limit of what ADDA is, not a defect in a measurement, and it should be stated in the reports, not hidden by a clean result.

Ideas for narrowing it, none built, none a replacement for looking:

| # | Idea | What it would and would not tell you |
|---|---|---|
| 5.1 | **Action-consistency findings:** compare the clip or state that is playing with what the character is doing (supported by a ladder or on the floor, moving or not, height changing or not). Examples: a climb state while standing on a deck; `move` at zero speed. | Flags a mismatch as an observation with the evidence. Cannot say which side is wrong. Needs a declared table of which states belong to which situations. |
| 5.2 | **Keep the reference visible:** for each scenario record a short clip or frame strip next to the report, so a reviewer can look. | Makes the visual check cheap and repeatable. Is still a human judgment. |
| 5.4 | **A planted foot against the surface under it** (tread, deck, floor), not only against the plan | The stair-entry report shows ADDA missing a 0.84 m glide because the plan itself was where the foot was pulled to. Justified by a real report; not built: the owner decides. |
| 5.3 | **Reviewer checklist per scenario:** "does it do the right thing?" questions (does the climb end when the feet leave the ladder?) listed in the scenario, answered by a person, kept in the report. | Records the verdict and who gave it. Replaces nothing automatic. |

## 6. Project housekeeping

| # | Item | Source | Notes |
|---|---|---|---|
| 6.1 | `TacticalCharacterAdapter` is `@tool` but `CharacterAnimationController` is not, so any open unit-visual scene floods the editor with errors | M | An `Engine.is_editor_hint()` guard in `get_presentation_state` would stop it. One line in animation code; not applied. |
| 6.2 | Add "run the Workbench from the command line, not from an editor tab" to the human workflow | I | Same cause as 6.1. |
| 6.3 | Merge order: `review/claude-animation` first, then `review/claude-adda` | M | Pedro decides when; nothing has been merged. |
| 6.4 | The committed ladder close-up still does not reproduce from its own commit | M | Documented; the still is left in place. |

## Suggested order, if useful

1. Sideways stairs (1.1) as the first new ADDA scenario: it is visible, Pedro can already reproduce it, and it exercises the foot findings.
2. Arm swing (1.2): define the metric, then compare.
3. Decide R1 to R3 (1.3 to 1.5): each has a named next experiment.
4. Hit reaction (2.2) and ragdoll (2.4): design the measurement first.

## 7. Issue round of 2026-11-24 (uncommitted at the time of writing)

Fixed, each with a regression test and a negative control: **#62** cover entry (the legs hand over from the clip to the crouch over 0.2 s; worst one-frame step 33 to 9 cm, `cover_crouch_takeover_test`), **#67** interrupted climb (the climbing pose eases out over 0.25 s; pelvis step 27 cm to 1 cm in the test, `ladder_interrupt_test`), **#72** compare reports a regrouped snap as CHANGED, **#73** workflow warning (mistake 11), **#75** tab titles fit, **#64** (the 30 fps grip-count part only: a duration, not a frame count).

Found on the way, fixed: the ladder knee turn rate ran on the engine's frame time, not the simulation's, so the ladder was not repeatable in fixed-step runs (hidden until #67 removed the 44 cm snap that masked it).

Not done: **#63, #66** need someone to look at the animation (no number says whether a top-out looks right); **#65** needs a tactical stair scenario; **#68, #55, #69, #70, #71** are open (#71 is an owner decision); **#64** still has the 122 mm capsule-versus-mesh disagreement (owner decision). **#74**: animation tier 85 pass, 1 fail (that capsule check); the overhead probe reads a flat 6.90 ms for every tier, so it cannot see small overheads.

Known flaky at the baseline: `ladder_climb_test` (fails about 3 runs in 4 on the untouched baseline; its leg limit is borderline).

### Handoff status (phase closed by the owner, 2026-11-24)

* `ladder_landing_test`: a known limitation, not a regression. On the untouched baseline (`0963f95`) it fails 5 checks (four at 121 to 122 mm, legs against the capsule volumes, and the 30 fps grip count); on this branch it fails the same four (122.1 to 122.2 mm) and the grip count is fixed. The 122 mm is the capsule-versus-mesh disagreement in `docs/claude/adda/01-baseline-and-architecture.md`; the thresholds were not loosened. Owner decision.
* `adda_workflow_test`: it was a real regression of this branch, now fixed (8 of 8 runs; passes in the full tier). Two of my changes had put real frame time into a fixed-step run; both now run on the simulation clock.
* `ladder_climb_test`: flaky on the baseline, not fixed (issue 78).
* Follow-ups logged as issues 76 to 80 (simulation-clock rule, shared hand-over, flaky ladder test, overhead probe, worst-step masking). Open animation issues 55, 63, 65, 66, 68, 69, 70, 71 are untouched.
* Final verification: animation tier 85 pass, 1 fail (`ladder_landing_test`, above). The overhead probe is not informative (issue 79).
* Not verified by eye: cover entry (0.2 s hand-over) and the interrupted-climb ease-out (0.25 s). Headless numbers do not establish that they look right.


### Carry and loaded ladder (2026-11-27, `review/claude-carry-ladder`)

* New: Small→Regular loaded climb, right toe tip reads −0.9 cm against the conservative rail envelope at 1.4 s (transfer); look at it by eye.
* New: passenger arms hang limp at the deck lip; no purposeful passenger hand pose.
* Not done: tactical adoption (adapter flag, transfer-time budget, Guard timing); owner decision. See `carry-ladder-report-2026-11-27.md`.
* Unchanged: #64 (≈118–122 mm), #68, carrier chest steps at the landing (13–28 cm, inherited).
