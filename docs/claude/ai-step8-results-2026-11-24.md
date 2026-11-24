# AI step 8 results: squad commitments and expiry — 2026-11-24

Plan: [AI 2.0 plan](../ai-2-plan.md), step 8. Starting point: `main` at merge commit `8cebf02`, branch `review/claude-ai-step08`. Evidence is automated (E2): focused tests, the 48-match fixed-seed baseline and the Ironclad changed-files tier. No human playtest and no rendered check.

## What already existed, and was kept

The audit and steps 4 to 7 had already built most of the machinery, so this step did not rebuild it. Kept as it was:

* stable tactical IDs for every owner and target (names only for unregistered fixtures);
* one context per side (player and allies share one), rebuilt each round, with each unit's own claims released when it next activates;
* a replaced destination releasing the old one, an owner that moved off its reserved cell releasing it, and a dead owner or target being pruned at the next squad lookup;
* hard commitments (an ally's exact cell, a carrier's lane) kept apart from the soft preferences (crowding, focus), with named owners in every veto;
* authoritative legality: a squad claim never makes an illegal cell legal (a test now says so directly).

## What was actually missing

Found by reading the code and confirmed with tests that failed or could not be written against the old behaviour.

| # | Gap | Evidence |
| --- | --- | --- |
| 1 | **A carrier's lane was never revalidated inside a round.** It was computed at the first activation of the round (and again when the carrier itself activated) and kept. Cells the carrier had already passed stayed forbidden to its escorts. A carrier that took a different step than the planned line left a stale lane behind. A moved extraction zone did not end it either. | One of the 48 baseline matches, `service_depot-RESCUE-16`, decision 94: the escort never even considered (24,0,12) because a lane the carrier was not using still held it. See the behavioural difference below. |
| 2 | **Releases on death were lazy.** A defeated owner's destination and lane, and fire aimed at a defeated target, waited for the next squad lookup. | Mutation test: with the eager release removed, five checks fail. |
| 3 | **The focus penalty ignored finishing.** Every ally already on a target cost 15 points, even when the shot would likely kill it. | A near-tie the old rule loses: a certain kill (183.4 points) against an 80% kill on a fresh target (170.2); the old penalty put the certain kill at 162.4, so the AI skipped it. |
| 4 | **Objective-handler claims did not end when their objective did.** They lasted until the round ended. | `release_objective` and a real completion signal now end them; a test emits one. |
| 5 | **A carrier's cached route outlived the map it was planned on.** A cell closing on it (a wall, a collapse) did not make the carrier plan again. | The pathfinder's graph revision only changes on static map edits, never on unit movement; a test closes a route cell and checks the new route avoids it. |
| 6 | **Nothing recorded why a commitment ended.** | There was no record to read. |

Smaller things found on the way: a failed lane plan left an owner token with an empty lane; `reserve_objective` counted the asker as another handler on a repeat call; releasing the claims aimed at a defeated target must not release the shooter's other claims (this was a bug in the first version of the fix, caught by a test).

## What changed

| File | Change |
| --- | --- |
| `systems/ai/squad_context.gd` | `revalidate(actors, extraction_cells)` replaces the roster-only prune (which stays as a thin wrapper). It releases owners and targets that are gone, destinations the owner left, a lane whose carrier is no longer carrying, has left it, or whose end is no longer in the extraction zone, and gives back the cells of the lane the carrier has passed. `release_unit(id, reason)` is the eager version for a defeat. `release_objective(id)` ends an objective's handlers. `focus_count` and a kill-chance-aware `target_adjustment`. A bounded `expiry_log` of `{round, kind, owner, reason}` (32 entries). Explicit `LIFETIME_ROUNDS` and `FOCUS_PENALTY` constants. |
| `systems/battle_controller.gd` | Passes the extraction zone into the check; releases both sides' claims when a unit is defeated and when an objective completes or fails. |
| `systems/ai/ai_target_scorer.gd` | Passes the kill chance it already computes to the focus term. The score record's `focus_count` is now the real count. |
| `units/ai_controller.gd`, `systems/grid/pathfinder.gd` | A carrier's committed route remembers the graph revision it was planned on and is planned again when it changes. `Pathfinder.graph_revision()` is a read-only getter. |

No change to legality, to the combat rules, to difficulty or commander weights, to the movement profiles, to saved replays, or to any random draw. Everything above is a function of the same state, so a fixed seed repeats exactly.

## Tests

| Test | Checks | What it proves |
| --- | --- | --- |
| `squad_commitment_expiry_test` (new, unit level) | 49 | One-round lifetimes; defeat, vanished target and moved owner; objective release; the lane (trimmed, abandoned, retargeted, killed, put down, failed plan); the finishing-aware focus term; the bounded record; determinism. Every release has a control that shows the commitment is kept while its basis holds. |
| `squad_commitment_scenarios_test` (new, real battle) | 39 | A real defeat releases at once (and only the right claims); a certain finisher is taken despite allies on it, and a healthy target is still spread away from; a carrier walking its lane gives cells back, a moved exit or a displaced carrier ends it, a defeated carrier's lane goes at once; a committed route is replanned when the map changes and kept when only units move; an ended objective drops its handlers; a squad reservation never changes what the shared Move query allows. |
| `squad_context_smoke`, `ai_target_scoring_smoke`, `ai_carrier_reservation_test`, `debug_inspection_test` | unchanged | Pass without edits: the established contracts hold. |

**The new tests can fail.** Each behaviour was broken on purpose and the test went red: no eager release on defeat (5 checks fail), the exit never passed into the check (1), the kill chance dropped from the focus term (3, including the decision itself), the route graph check removed (2). The lane trimming and the off-lane release were switched off together on the baseline match described below, and the decision returned to the old one.

## Baseline comparison

The harness is `tests/ai_baseline_report.gd`: 3 sites by 8 mission kinds by seeds 16 and 17, Normal difficulty, three against three (extra ally and VIP where the mission uses them). Compared with `tools/quality/ai_baseline_compare.py`, which diffs the decision sequence and final state signature, not wall times. The baseline was run on a separate worktree at `8cebf02`; the one match that differs was rerun there and reproduced exactly, so the difference is not run-to-run noise.

| | Before (`8cebf02`) | After |
| --- | --- | --- |
| Matches | 48 completed | 48 completed |
| Results | 36 Victory, 12 Defeat | 36 Victory, 12 Defeat |
| Decisions | 3,329 | 3,329 |
| Rejected actions | 0 | 0 |
| Identical to before | | **47 of 48** |

**The one difference: `service_depot-RESCUE-16`.** Same result (Victory), same round count (10), same decision count (134). At decision 94 the escort moves to (24,0,12) instead of (24,0,11). The baseline never considered (24,0,12): a lane reserved earlier in the round, from where the carrier then stood, still held it, and the carrier had gone a different way. With the lane following the carrier it is a candidate again, and it scores higher (progress +25 against +20). Switching the lane trimming off alone did not restore the old decision; switching the trimming and the off-lane release off together returned the match to the baseline exactly, so the cause is the lane following the carrier and nothing else. This is the intended behaviour.

**What the baseline does not show.** The focus change decided nothing in these 48 matches. In the controlled scenarios the focus term matters only in near-ties (a few points either way in totals of 100 to 180), which is how it should be for a preference, but it means the matrix gives no evidence of benefit; only the scenario tests do.

## Behavioural differences, in plain words

1. An escort can use cells the carrier has passed, and cells of a lane the carrier is no longer using, instead of being held out of them for the rest of the round.
2. When the carrier's exit moves, the old lane stops blocking at once, and the escort's route reads the new one.
3. A defeated actor's destination, lane and fire are gone the instant it falls, for both sides.
4. A shot that will probably finish a target is no longer discouraged because allies already fired at it. Healthy targets still spread fire.
5. A carrier plans a new route when the map changes under the one it committed to.

## Known limits

* Target claims are recorded after a shot is taken, so "focus" means fire already delivered this round, not a plan. That is unchanged and is why the penalty cannot waste a decision on an obsolete plan: there is none to be obsolete.
* Objective-handler counts still only annotate the decision; they do not assign exclusive roles.
* A carrier that steps off the planned line drops its lane until the next unit's activation re-reserves it from the carrier's current cell. Inside one escort activation the carrier does not move, so this left no gap in the checked cases, but the lane is not re-reserved mid-activation.
* Corridor yielding, blocked or crowded exits, defeated handlers and endless position swapping are step 9. Nothing here changes how an escort clears a lane.
* F3 does not show `expiry_log` yet (step 11). It is read-only evidence for tests and a later view.
* One difficulty, one squad size, seeds 16 and 17, default commanders. Hard difficulty, larger squads and other seeds were not run. Planning time was not measured for this step.
* The `changed` tier also flagged `resource_references_test`. It was red on `main` because of a placeholder path (`res://x.tres`) in a Workbench test from an earlier phase of this project; fixed in its own commit.

## Reproduce

```powershell
.\tools\run_tests.ps1 select -Test squad_commitment_expiry_test,squad_commitment_scenarios_test,squad_context_smoke
godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- tag=step8-after profile-ai
python tools/quality/ai_baseline_compare.py artifacts/ai-baseline/<before> artifacts/ai-baseline/step8-after
```
