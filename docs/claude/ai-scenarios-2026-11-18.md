# AI controlled decision scenarios — 2026-11-18

Milestone 05 step 3. Starting commit: `e78f1d5`. These are fixed setups with the legal options listed from the shared queries and a stated expectation for a reasonable decision. They are automated evidence (E2); they do not prove the AI plays well. They retain the existing AI tests and add `tests/ai_decision_scenarios_test.gd` plus its helper `tests/support/ai_scenario_fixture.gd`.

## How the scenarios work

- **Fixture** (`tests/support/ai_scenario_fixture.gd`): builds the real battle scene, places units on exact cells, adds real cover or walls, lists the legal options from the same queries the player and AI use (`query_attack`, `query_move`), and runs a real AI activation through the authoritative action service. Placing a unit on a solid or occupied cell is an error, so a broken setup cannot pass silently.
- **Two maps.** Target and ammo scenarios use the flat fixture map, reset to open ground so the only cover is what the scenario adds. Movement scenarios use the **Tactical Test Range**, because the AI's route-to-hostile movement only runs on surface-placement maps like the current sites (see limits).
- **One activation.** The fixture sets `debug_player_ai` directly rather than through its setter: the setter makes every AI controller start its own activation, which would run alongside the one under test.
- **HARD difficulty.** It has no seeded lapses, so preference scenarios are deterministic. Legality rules do not depend on the tier. The scenarios gave identical traces on repeated runs.
- **Assertions.** Every decision must obey hard rules: no rejected action, AP within budget, ammo not negative, a legal cell it alone occupies, and an explanation. Preferences are properties ("the chosen target is no worse than the best legal expected damage"), never one exact tile. Behavior the AI does not have yet is documented below instead of being asserted.

## Scenarios

| # | Decision | Setup and legal options | Reasonable behavior | What the AI does today |
|---|---|---|---|---|
| S1 | Cover | Two equal hostiles, one behind low cover. Both shots legal; the covered one has a lower chance. | Shoot the better shot. | Chooses the exposed one, shoots with all 3 AP. **Asserted.** |
| S1b | Flanking | One hostile behind low cover facing the shooter; a reachable flank tile gives a better shot. | Either shoot now or move to a better tile, legally. | Shoots 3 times from the frontal tile at 80% and never moves, although a reachable tile gives 100%. With 3 AP staying is still better (about 60 expected damage against about 50 for move then 2 shots), so this is reasonable. Legality asserted; the move-then-attack comparison is step 6. |
| S2 | Wounded | One hostile can be defeated by a single hit. | Take the finisher. | Chooses it. **Asserted.** |
| S3 | Shielded | One hostile holds Shield Stance toward the shooter (hits deal 9, not 25). | Prefer the unshielded target at equal range and health. | Chooses the unshielded one. **Asserted.** |
| S4 | Height | Two targets at equal 3D distance, one standing one level lower (height modifier +5). | No worse than the best legal expected damage. | **Asserted** (property check). |
| S5 | Ammo | No Supply Points, a clear shot, 2 AP; no attack is legal. | Reload first, then shoot. | Reload, then Attack. **Asserted.** |
| S6 | Crowded corridor | One-cell corridor with an ally standing in it, hostile beyond. No path exists. | Hold or reposition legally, with a reason. | Holds 7 cells from the corridor mouth and waits ("no reachable legal destination"). Legality asserted; see observation 1. |
| S6b | Free corridor | The same corridor with the ally gone. | Advance toward the hostile. | Three moves, through the corridor, using all 3 AP. **Asserted** (progress). |
| S7 | Extraction | Standing in the exit zone with AP. | Extract. | Extracts. **Asserted.** |
| S7b | Extraction en route | Exit zone 9 cells away, no hostile in range. | Move closer; do not wander. | Three moves, then Extract, in one activation. **Asserted** (progress). |
| S8 | Rescue | Carrier next to the casualty, exit nearby, hostile far away. | Pick up, then stop shooting and head for the exit. | Rescue, two moves, Extract in one activation. **Asserted.** |

Existing tests retained and still relevant to these decisions: `ai_target_scoring_smoke`, `ai_position_scoring_smoke`, `ai_attack_plan_test` (Aim vs shooting), `ai_wounded_recovery_test`, `rescue_carrier_support_smoke`, `protect_rescue_ai_smoke`, `objective_ai_navigation_smoke`, `ai_second_advance_smoke`, `survive_ai_smoke`, `ai_carrier_reservation_test`.

## Observations (not asserted as passes)

1. **The Wait reason is wrong when a blocked path is the cause.** In S6 the unit holds with "no reachable legal destination", yet legal destinations exist: the path to the hostile is blocked by the ally. The reason never names the blocker, and the unit does not move up to the corridor mouth to be ready.
2. **Correction (2026-11-18, later).** An earlier version of this document, and issue #43, reported that a unit en route to an exit or corridor leaves AP unspent after one move. That was an artifact of the scenario fixture, which started a second background activation alongside the one it was observing. With the fixture fixed, S6b and S7b use all their AP. The baseline's wait counts are real data but are not evidence of lost AP. #43 was closed as not reproduced.
3. **No Move-then-Attack comparison yet** (S1b). Fine in the cases seen; it matters when AP is short or a frontal shot is poor. This is step 6.
4. **Flat legacy maps never run route-to-hostile movement.** Without surface placement the AI looks for a path to the hostile's own, occupied cell and finds none, so it waits even on open ground. Current content is unaffected, but fixtures created with `generated_map = false` cannot test approach behavior.

## Not covered yet

Flank-movement preference (step 6), several allies yielding in a corridor and blocked-exit recovery (step 9), movement over stairs and ramps, difficulty and commander differences (step 10), and a human playtest of any of it.

## Run

`godot_console --headless --path . --script res://tests/ai_decision_scenarios_test.gd` (also part of `.\tools\run_tests.ps1 subsystem -Subsystem ai`). Each scenario prints a `[Scenario]` trace line with the start and end cell, the actions taken and the final explanation.
