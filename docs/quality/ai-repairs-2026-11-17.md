# AI audit repairs — 2026-11-17

Starting commit: `745d3eb`. This batch addresses the audit's concrete defects and a bounded scoring-policy correction. It does not implement the rest of milestone 05 or claim a general planner-performance fix.

## Changes and protected contracts

- Carrier selection rejects hard-reserved/non-finite scores before reading components. The regression reproduces the old script error, then proves rejection and an unreserved forward alternative through real movement. Existing physical/body/route checks are unchanged.
- Squad destination replacement releases the old cell; cleanup is idempotent. Stable tactical IDs survive node renames. Live-roster pruning releases dead/removed owners and targets; corridors also clear when their owner stops carrying. Objective changes release old handler claims. Lifetime is explicitly bounded by activation/round boundaries; no new reservation framework.
- F3 uses a read-only team-aware lookup, so allies see the shared player context without creating/resetting it. Hostile target filtering now also excludes friendly inventory entries.
- Simulator classification gives terminal outcomes priority over simultaneous round/stall/timeout conditions and clears stale reasons. Focused pure checks retain real ongoing-limit failures; no timeout or round limit was raised.
- Target finishing priority uses predicted on-hit damage, including Shield/edited damage, rather than 25 HP. HP-capped expected damage contributes with an editable policy weight. Threat finishers and the compatibility policy helper also stop assuming 25 damage.
- Aim compares short same-target shot sequences using current AP/ammo, actual chance, capped damage and kill probability. Its bonus applies only to the next shot. The AP window is capped by `MAX_ATTACK_PLAN_AP = 3`; ties prefer immediate Attack. Enemy reactions, movement plans and all future responses are not simulated. Combat formulas and player action rules are unchanged.
- Early movement selection remains available for heatmaps. A separate authoritative outcome signal exposes committed/rejected movement, decision ID, transaction and revisions; all AI commits are counted separately from explanations. Unlinked non-movement outcomes have decision ID 0 rather than inventing a link. No random rolls are consumed by diagnostics.
- VIP following chooses the nearest eligible player with stable-ID tie breaking. A carrier's cached route is rebuilt if its endpoint no longer belongs to extraction.

The existing simulation/replay version remains appropriate: action execution rules and replay evidence have not changed. AI choices can change intentionally; saved replay submits its recorded choices instead of rerunning AI planning.

## Verification

Final serial runs after all code changes below, one at a time (2026-11-17, evidence level E2: automated verification, not a playtest):

| Suite | Result | Logs |
| --- | --- | --- |
| Smoke | 11 passed, 0 failed, 0 skipped | `artifacts/test-results/20261117-232214-smoke/` |
| Combat | 37 passed, **1 failed**, 1 explicit-only skipped; the failure was fixed (below) and the test passes in isolation | `artifacts/test-results/20261117-232314-subsystem-combat/` |
| Movement | 23 passed, 0 failed, 0 skipped | `artifacts/test-results/20261117-232740-subsystem-movement/` |
| Replay | 17 passed, 0 failed, 0 skipped | `artifacts/test-results/20261117-232957-subsystem-replay/` |
| AI | 27 passed, 0 failed, 1 explicit-only skipped (`ai_match_simulation_smoke`), including the extraction case | `artifacts/test-results/20261117-233703-subsystem-ai/` |

The full combat subsystem was not rerun after the fix below. `aim_tactical_state_test` was rerun alone (0 failures), and the AI subsystem covers the changed controller code. The UI subsystem was last run before the caching work and has not been rerun since.

**Combat failure, classified as a regression from this batch.** `aim_tactical_state_test` failed twice: `AIController._try_aim_for_attack` read `_policy` (null) when called on a controller that was never added to the scene tree, and the test expected the AI to Aim with full AP and ammo. Fixes: `_ensure_policy()` composes the policy lazily; the test now sets one round of ammo so Aim genuinely beats a single unaimed shot, and gains assertions that the AI declines Aim at full ammo and spends nothing. No original assertion was removed or weakened. This changes the test's contract intentionally, because the new Aim-versus-attack comparison is a deliberate policy change.

Earlier runs:

- UI subsystem: **26 passed, 0 failed, 1 explicit-only capture skipped** (`artifacts/test-results/20261117-212456-subsystem-ui/`), run before the caching work. Final outcome formatting was additionally checked in the rendered carrier regression.
- Replay subsystem: **17 passed, 0 failed, 0 skipped** (`artifacts/test-results/20261117-212456-subsystem-replay/`), also before the caching work. Includes six complete current-site battles and playback, 48 mission-start/action/replay cases, rescue/departure playback, local-parcel playback and supported-point replay. This is not a full autonomous completion matrix for every mission.
- Focused carrier/trace, shot-plan, classification, squad and allied F3 checks passed. A real rendered rejected move was captured and reviewed: the rejection/reason is visible first, above selected/historical detail (`artifacts/ai-repairs-review/f3-rejected-move.png`). This is a UI spot check, not a claim about every animation or camera.
- Initial broadened AI run, before the caching work: **24 passed, 2 failed, 1 skipped**; those failures are retained as history, and the final AI run above supersedes it.

Original red carrier reproduction emitted the missing `progress` script error and failed its explicit rejection assertion. A new Aim fixture initially used invalid tuning and later briefly had a duplicated declaration; both fixture mistakes were corrected while retaining the assertions. The extraction case failed its unchanged 35-second deadline, including in an AI-only run with no competing processes, so it was treated as a real performance regression and addressed below. The deadline was not raised.

## Planning performance caching

Added because the extraction case (`ai_stalemate_recovery_smoke`) kept missing its unchanged 35-second deadline. Profiling showed hundreds of milliseconds per decision in candidate route evaluation, against roughly 3-5 ms for position scoring. Mission rules, body-clearance checks and the deadline are unchanged.

- **Swept-body clearance reuse** (`systems/grid/pathfinder.gd`, `units/ai_controller.gd`): `calculate_path_with_occupancy` accepts a scratch dictionary and reuses edge clearance results while a signature is unchanged. The signature covers the graph revision, grid and map-data identity, body radius/height/clearance, surface settings, the ignored actor, and every occupant's identity, cell and world position. The AI clears the scratch above 16,384 entries and abandons planning if the state revision or occupancy changes mid-plan. Exact-point cell lookup (`_point_cells`) replaces `get_closest_point`.
- **Reverse cost field** (`Pathfinder.planning_costs_to_goal`): one Dijkstra pass from the route end replaces a hypothetical route search per candidate on the ordinary bidirectional surface graph. It is skipped when custom traversal links exist, so those keep the old path. Full swept-body clearance still runs on edges near an occupant, and cells far from any body are skipped by a triangle-inequality bound.
- **Guard coverage cache** (`BattleController._legal_shot_cells`, `_shot_cell_cache`): keyed per attacker by map-data identity and `los_revision`, pathfinder graph revision, attacker cell/world position/height/range/carrying state, tile size, elevation step, and the heights of occupants that differ from the shooter's. Capped at 32 entries.
- **`MapData.los_revision`** is bumped by `add_cell`, `rebuild_los_index`, `add_shot_obstacle` and `clear`. It is presentation-query invalidation only, not simulation state or replay evidence.

Measured: a representative route batch went from 532 ms to 240 ms with clearance reuse; Guard-coverage Wait observer work from 227 ms to 8 ms; the extraction case passes in 24.58 s with normal presentation (before the reverse cost field and the final suite, so treat as a point measurement), and `ai_stalemate_recovery_smoke` passed in the final AI run (41.45 s for its two matches).

New tests: `tests/ai_planning_clearance_cache_test.gd` (reuse is invalidated by a moved blocker, changed body profile, a different ignored actor, a removed blocker and a graph rebuild; the goal field matches occupancy-aware route cost) and `tests/combat_guard_coverage_cache_test.gd`.

Known limits and review items: `ai_extraction_profile` and the `profile-ai` timing output (`[AIPlan]`, `[AIPlanGoal]` in `units/ai_controller.gd`) are diagnostic only and print nothing unless `profile-ai` is passed. Cache invalidation relies on the revisions above; any new code that mutates the graph or LOS geometry outside `Pathfinder`/`MapData` methods must bump them.
