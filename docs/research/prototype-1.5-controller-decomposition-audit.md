# Prototype 1.5 Controller Decomposition Audit

Task 01.9 began from `9f67cfd` on `p2-foundation`. This audit traces current callers before deletion or consolidation.

## Findings

| Finding | Classification | Evidence and decision |
| --- | --- | --- |
| `BattleController.is_action_in_progress` mirrors `TacticalActionService.is_busy` and is manually toggled around every submission | Duplicated; consolidate | The service already owns the complete accepted-action lifecycle through blocking presentation. Expose that state through a service signal and keep the controller property as a read-only compatibility/view adapter. |
| `tactical_action_committed` relays `action_service.action_committed` without consumers | Obsolete; remove | Repository-wide call-site search finds only its declaration, connection, and emit. Recorder and tests listen to the service directly. |
| `replay_action_committed` and `record_replay_action()` relay only the `depart` command from `ObjectiveManager` | Wrong-direction compatibility bridge; remove | The replay recorder already receives `ObjectiveManager`. Give that authoritative command owner a plainly named command signal and connect the recorder directly. |
| Extraction state commitment calls back into `BattleController.extract_unit()` | Duplicated/wrong ownership; consolidate | `ObjectiveManager.complete_extraction()` is already the authoritative domain commit and owns both `TurnManager` and `GridManager`. It can remove occupancy/roster directly. Visual cleanup belongs to `TacticalActionPresenter`. |
| Attack/Move/Wait/Defend/mission `try_*` entry points repeat request/source/submission ceremony | Legitimate explicit orchestration with small cleanup | They are discoverable adapters for player and AI and preserve action-specific UI behavior. Keep explicit methods; remove duplicated busy mutation and share source selection. Do not add a generic dispatcher. |
| `can_attack()` / `evaluate_attack()` expose `CombatRules` to tests and hypothetical consumers | Legitimate read-only preview | They do not authorize or commit an action. Keep while current cover/elevation fixtures use them. |
| `_query_move_data()` and `_build_movement_path()` supply pathfinding and presentation data to the service | Legitimate controller composition, with a presentation coupling to review later | `Pathfinder` and `GridManager` still own the algorithms/state. Moving these methods now would relocate rather than reduce responsibility. |
| `_on_unit_defeated()` coordinates grid, roster, objective notification, and visual teardown for defeat from any source | Legitimate battle lifecycle orchestration | It does not calculate damage or determine defeat. Keep as the shared cross-manager consequence until conditions/hazards reveal a concrete unit-lifecycle service need. |
| AP exhaustion and AI completion can both advance selection/turns | Sensitive compatibility behavior; retain and test | `TurnManager._advance_selection_if_needed()` waits on the action-service barrier and returns when the active unit changed. `AIController` clears its execution guard, then calls `advance_automated_player()` or `end_current_turn()` only if it still controls the same unit. Extraction's explicit null-active guard remains necessary. |
| Automatic Reach/Rescue listens to committed movement | Legitimate objective consequence | It runs once inside the parent Move commit and is captured by that result/replay record. No nested action or second controller consequence exists. |
| Legacy Defend submission | Compatibility behavior still required | Current gameplay does not author Defend; schema-2 replay can still submit it through the explicit controller/service path. |

## Ownership after cleanup

- `BattleController`: input modes, previews, explicit submission adapters, service/presenter composition, battle unit lifecycle coordination, and debug control.
- `TacticalActionService`: the single action-busy state, validation, deterministic resolution, cost/state commit, revisions, transactions, and typed results.
- `ObjectiveManager`: mission rules, mission-state commits, extraction occupancy/roster consequences, and Depart command publication.
- `TacticalActionPresenter`: cameras, animations, feedback, transform synchronization, and final extracted visual disposal.
- `TurnManager`: selection, queues, phase/round advancement, and the presentation completion barrier.
- `BattleReplayRecorder`: direct observer of action, turn, and objective command owners.

XCOM's ability architecture remains useful here for the boundary rather than its class volume: committed game state is produced before visualization, and battle history observes authoritative state producers. FuseFire keeps explicit Godot collaborators instead of recreating the ability template/history framework.
