# Milestone 06.10A — Checkpoint-aware passenger release

## Baseline and reproduction

The reproduction ran on integrated main `49f71b41f83c5fbd56c66a8f1bc2265bbbc4d8ca`. This includes the Milestone 06.01 audit in PR #99 and the combat setup defaults in PR #100. The work was isolated from the owner's existing checkout changes. Godot 4.7.2 Stable ran the tests on Windows. The rendered pass used OpenGL Compatibility, 1280 × 720, and an RTX 5060.

The authored prototype Rescue fixture uses seed 1 and regular MIRA Alpha. The production Rescue action picks up the VIP. Fixture setup clears tactical cover metadata and controls Guard range and the first hit roll. A real Move from `(13, 4, 1)` toward `(13, 4, 3)` then takes lethal Guard damage at `(13, 4, 2)`. The baseline regression exited 1 with two failed assertions. The authoritative Move stopped at `(13, 4, 2)` and the VIP occupied `(13, 4, 1)`. The initial implementation passed all 11 checks in the same repro. The expanded regression checks rerescue, fallback, multiple watchers, the no-placement policy and playback.

## Transaction and ownership

1. [TacticalActionService](../../systems/actions/runtime/tactical_action_service.gd) validates the expected revision and move request, re-queries the route, acquires the action window and spends one AP. The receipt starts with the requested route.
2. Guard evaluates each logical checkpoint. Damage emits defeat synchronously, before the Move has truncated its route. [BattleController](../../systems/battle_controller.gd) publishes defeat, releases squad claims, unregisters the carrier from the origin and removes it from the turn roster. The old callback also released the VIP from that registered origin. For lethal Guard during Move, the service now owns this one release. Stationary and other defeat paths still use the registered cell.
3. The reaction receipt captures the checkpoint and stops later watchers. Move truncates the path and settles passenger placement at the resulting target. [ObjectiveManager](../../systems/objectives/objective_manager.gd) checks the passenger against the existing occupancy and standing rules and reopens Rescue. The carrier releases ownership. Move increments the state revision once, evaluates the mission outcome and publishes a single [Move receipt](../../systems/actions/runtime/move_action_result.gd) with the reaction and release outcomes. The recorder captures the settled occupancy and objective state.
4. [TacticalActionPresenter](../../presentation/tactical/tactical_action_presenter.gd) walks the already-committed shortened path. At lethal impact it removes the carry model and reveals the real VIP at the placed transform. Suppressed playback and an unavailable visual actor settle the visual handoff directly. Presentation never selects a cell or registers a unit. The action window closes when presentation finishes.

Publishing intermediate positions would change occupancy, selection, reaction and movement callbacks on a path traversed inside a single transaction. This correction keeps the logical checkpoints inside that transaction and reuses the existing placement and ownership APIs. The timed animation only changes reveal and attachment visibility.

## Placement and compatibility

- The checkpoint has first priority. Fallback checks same-layer Chebyshev rings through radius three, then nearest Euclidean distance within the first usable ring. Equal distances keep the first candidate in coordinate iteration order. The existing check requires a walkable, stoppable cell and rejects occupied cells and overlapping bodies where continuous body clearance applies. Surface maps use their canonical standing points. The legacy authored map uses its existing cell standing flags.
- Intermediates may be traversable without being legal stops. The controlled fallback case marks the checkpoint as transit-only, keeps two equally distant legal candidates, and occupies a third. It picks the origin as a legitimate fallback in that case. If no stop exists, the original loss policy fails the VIP extraction objective. The deferred visual release leaves the lost VIP hidden and off-grid.
- Route hazard cells apply conditions. Condition damage is settled at the tactical beat, using the actor's registered cell. The current implementation has no separate lethal hazard hit during a Move checkpoint. Direct attacks and Guard retaliation against an attacker also use registered-cell defeat handling.
- [BattleReplayRecording](../../systems/replay/battle_replay_recording.gd) persists a narrow checkpoint-release capability on new recordings. Old files lacking it retain registered-origin release during playback. A corrected Move receipt records the passenger ID and actual release cell, or an empty cell array if lost. Playback compares this field as well as the unchanged transaction, revision and state fingerprint checks. The archived-path test round-trips a recording with the flag omitted and verifies its old outcome. An older build may reject the additional receipt field when playing a new affected recording.

## Verification and reproduction

Run from the review checkout with Godot 4.7.2 on PATH.

```powershell
.\tools\run_tests.ps1 check
.\tools\run_tests.ps1 select -Test reactive_passenger_release_test,rescue_carrier_loss_test,overwatch_reactions_test -Import
$out = Join-Path (Get-Location) 'artifacts/0610a/rendered'
godot_console --path . --rendering-method gl_compatibility --resolution 1280x720 --script tests/reactive_passenger_release_test.gd -- capture $out
```

The [durable regression](../../tests/reactive_passenger_release_test.gd) records the actual Rescue, Move and subsequent Rescue receipts where applicable. The test reconstructs controlled fixture placements and RNG before playback, then uses the regular BattleReplayPlayer and its verification. This is a regression fixture with controlled initial state. It is run through the test script and is independent of Match Setup's replay picker.

| Case | Verified outcome |
| --- | --- |
| Legal checkpoint, two potential watchers | First lethal hit at `(13, 4, 2)`. Only one reaction consumes supply. AP and revision each change once. One passenger is placed, ownership clears, route and receipt truncate. Bravo successfully performs Rescue again. Playback verifies all three actions on repeated runs. |
| Transit-only checkpoint, occupied candidate and two legal alternatives | Existing deterministic tie-break settles at `(13, 4, 1)`. A round-tripped replay verifies both actions and final state. |
| No available stop | No active passenger remains on the board. The VIP extraction objective and mission fail through the existing loss path. |
| Nonlethal reactions | Move completes to `(13, 4, 3)` with both hits resolved and passenger ownership intact. |
| Historical configuration with no checkpoint-release flag | Replay restores the old drop at `(13, 4, 1)` and verifies both transactions. |
| Stationary, pickup-time or noncarrier defeat and mission completion | Covered by the existing Rescue loss and playback suites. |

### Results

- Catalog validation passed with 309 catalogued scripts. Editor import and project parse passed. The targeted Ironclad run selected 18 tests and finished with 17 passes, one inherited failure, zero timeouts and zero unexecuted selections. The new regression reported 127 checks and zero failures. The original audit probe independently reported the VIP at `(13, 4, 2)`. A separate `tactical_conditions_test` run passed.
- Passing coverage included Rescue loss, Rescue replay and pickup handles, Guard reactions, the action service, surface navigation, loaded traversal, ladder interruption, AI reservations and scene lifetime, mission terminals, battle and defensive-action replay, traversal replay determinism, and presentation authority and lifecycle.
- `ladder_landing_test` reproduced the four inherited assertions for armed and unarmed regular MIRA descent on posts and rails. Its measured overlaps were 112.7–122.4 mm. The test ran as written. The selected run's `results.json` and logs are under `artifacts/0610a/ironclad/20261127-123742050-8f9c785c-select`. Ironclad left 254 ordinary scripts and 37 explicit-only scripts outside this local selection. The separate condition run and hosted smoke covered additional cases. The ordinary full tier was outside this targeted verification.
- The rendered sequence reported 27 checks and zero failures. [Hosted Ironclad smoke passed on the production change in PR #101](https://github.com/Melo9002/fusefire-proving-grounds/actions/runs/46026927907).

### Rendered observations

The normal-speed fixture used the production Move presenter, Guard reaction, Combat Only action camera and objective HUD. Alpha carried the visible model while moving. The actual passenger became visible at the checkpoint when the lethal impact was presented. The carry model was removed, the incapacitated VIP settled at the registered position, and Bravo picked them up on the next action. The committed Guard log and objective HUD update before the cosmetic walk and shot finish. One impact frame can include both the defeated carrier and the released VIP at the checkpoint. The existing incapacitation transition takes several frames to settle. The capture verifies the sequence on this authored platform. It does not certify animation quality on ladders, uneven terrain or every camera angle.

[Moving with the passenger](evidence/movement-0610a/02-moving.jpg) · [Guard impact](evidence/movement-0610a/03-impact.jpg) · [Settled VIP and reopened Rescue](evidence/movement-0610a/04-settled.jpg) · [Bravo carries the recovered VIP](evidence/movement-0610a/05-recovered.jpg)

## Remaining work

Keep inherited ladder descent issue [#64](https://github.com/Melo9002/fusefire-proving-grounds/issues/64) outside this correction. The fallback does not search other floors, and the unresolved placement candidate search identified in 06.01 remains Step 06.02. The existing timing split between committed log/objective feedback and animation belongs to later 06.10 presentation review. Loaded traversal design and new hazard interruption behavior also remain separate. Proceed to Step 06.02 after owner acceptance of this bounded correction.
