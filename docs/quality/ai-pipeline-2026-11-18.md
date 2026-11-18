# AI decision pipeline and F3 visualization — verification, 2026-11-18

Milestone 05 step 4. Starting commit: `e3d7893`. The design is in [AI decision pipeline](../ai-decision-pipeline.md); the F3 tools are in [F3 battle inspection](../debug-inspection.md). Evidence level: automated (E2) plus rendered review of four F3 captures (E3). No human playtest.

## What changed

- **Typed decision records** replace the loose dictionaries between the controller, the battle and the trace consumers: `AIPositionCandidate`, `AITargetCandidate`, `AIDecisionContext`, `AIDecisionRecord`. `BattleController.record_ai_decision` now takes an `AIDecisionRecord` instead of twelve positional parameters. Each record publishes exactly the established trace keys.
- **`AIPlanningSnapshot`** names the "discard stale plan" rule that `_move_along_goal_path` already applied with two loose locals.
- **Liveness guards.** Recording a decision, publishing a movement preview and ending a turn now do nothing once the unit, turn manager or battle has gone away. An audit of the controller's 58 `await`s found that the main activation loop already checked after every action, but several helper paths in `_try_mission_step` and the escort-follow path went on to record or query without checking. The guard is on the battle side, not the controller's own tree membership, because the controller is also used as an adapter outside the scene tree (existing tests do this).
- **F3 visualization:** a decision timeline, a route arrow, target lines, a squad-reservation overlay and score-component bars. See the F3 doc.
- No decision the AI makes changed.

## Proof that behavior did not change

The 48-match baseline (3 sites x 8 missions x seeds 16 and 17, 3v3, Normal) was rerun on the refactored code and compared with the original, decision by decision: every decision record including candidates, score components and context, every committed or rejected outcome, the per-round samples and the final state.

| Run | Code | Result |
| --- | --- | --- |
| Original | `e3d7893` | reference |
| After the typed records | records and snapshot | 48 of 48 identical |
| After everything (guards and all F3 changes) | the full step-4 code, with the first version of the guard | 48 of 48 identical |

The guard was narrowed afterwards (see failures below). It is strictly weaker than the version the second comparison passed under and only triggers when the battle side is gone, so that comparison was not repeated.

## Tests

- New: `tests/ai_decision_records_test.gd` (48 checks: record key sets, snapshot staleness, adapter recording, discarding work after the battle is freed) and `tests/ai_decision_visualization_test.gd` (25 checks rendered, 21 headless: timeline, route arrow, target lines, reservations, bounded history, read-only browsing, panel fit at 1280x720).
- One existing call site changed: `ai_commander_policy_smoke.gd` called the old five-argument `record_ai_decision`; it now builds an `AIDecisionRecord`. Its assertions are unchanged.
- AI subsystem, final: **30 passed, 0 failed, 2 explicit-only skipped** (`ai_baseline_report.gd`, `ai_match_simulation_smoke.gd`).
- Focused: `debug_inspection_test` (40 checks), `debug_tools_smoke`, `ai_scoring_overlay_smoke`, `aim_tactical_state_test`, `ai_scene_lifetime_test` all pass.
- UI subsystem, after the F3 changes: **26 passed, 0 failed, 1 explicit-only skipped** (`parcel_editor_capture.gd`).

## Failures found and how they were classified

1. **Regression from this change (fixed): the first liveness guard broke adapter use.** `ai_abilities_integration_test` failed in the AI subsystem run: the guard required the controller itself to be in the scene tree, but the controller is deliberately usable as an adapter outside it. Narrowed to the battle side (`_dependencies_alive`); the test passes unchanged. The guard test now covers both cases: records while the battle lives, nothing after it is freed.
2. **Defective fixture (fixed): the scenario fixture started a second, background AI activation.** The fixture set `debug_player_ai` through its setter, which makes every AI controller start its own activation, so each scenario ran two coroutines. Assertions still held and traces were deterministic, but two traces were wrong: S6b and S7b appeared to leave AP unspent. With one activation they use all AP. Issue #43, filed on that reading, was closed as not reproduced, and the scenarios document was corrected. S6 (the blocked corridor, #42) is unchanged.
3. **Environment/timing (fixed in the fixture): rendered runs were flaky.** Ending a unit's turn sets off deferred turn-manager transitions and unfinished presentation. The fixture now waits for the battle to go idle around each activation, and the visualization test drives its first decision through the AI's own move planning without ending the turn.
4. **Defective test (fixed):** a lambda counter (GDScript lambdas capture by value) and two near-vacuous assertions I had written; the latter were replaced by a real read-only check.

## Rendered review findings (fixed)

The first captures showed the route arrow and target lines invisible (back-face culling and too thin), a stale movement heatmap drawn for an attack, and truncated bar labels. Fixed: lines draw both faces and are wider, attacks hide the stale movement candidates (in the world and in the text panel), labels are full names. Re-captured: the arrow, thick chosen-target line, dim second-target line, the reservation squares and the timeline with `[committed]` tags and bars all read correctly. Four captures are in `artifacts/f3-viz-review/` (local, not committed). This is a spot check of one scenario, not a claim about every camera or map.

## Limits

- `_run_activation` is still one long loop that mixes the pipeline stages. Splitting it was left out on purpose.
- The scorers still return dictionaries.
- An Attack record still carries the last movement plan's candidates; F3 hides them rather than the controller clearing them, which would change the trace.
- The timeline keeps 80 decisions; it is not persisted.
- Reservation drawing is read from live squad contexts, so it shows claims at the moment it is refreshed (each decision and on toggle), not a history.
