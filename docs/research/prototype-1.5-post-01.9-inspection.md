# FuseFire Prototype 1.5 — Post-01.9 Architectural Inspection

**Operation:** Clearance Dorito  
**Inspection date:** 2026-10-10  
**Branch and starting HEAD:** `p2-foundation` at `9dc6b57` (`pixihex was here`)  
**Starting working tree:** clean

## A. Baseline

The expected checkpoint matched exactly. Commit `47f116b` removed the controller's duplicate busy state and obsolete signal/replay/extraction bridges, moved authoritative extraction removal to `ObjectiveManager`, moved visual extraction cleanup to `TacticalActionPresenter`, added the controller-decomposition audit and tests, and updated current ownership documentation. Commit `9dc6b57` changed only PixiHex's signature in `PIXI_WAS_HERE.txt`.

The inspection read the live implementations of `BattleController`, `TacticalActionService`, `TacticalActionPresenter`, `TurnManager`, `ObjectiveManager`, actor registry, replay recorder/player/schema/fingerprint tools, AI callers, HUD callers, action result contracts, and the relevant tests and documentation. Repository-wide reference searches included GDScript, scenes, export configuration, tests, and docs.

## B. Findings

### Medium — End Turn bypassed the blocking action lifecycle

- **Location:** `systems/turn_manager.gd`, `end_current_turn`; `ui/turn_hud_controller.gd`, End Turn state handling.
- **Evidence:** `TacticalActionService` kept `is_busy` true through presentation, but `TurnManager.end_current_turn()` checked only pause, battle result, and moving units. The separate Turn HUD did not observe `BattleController.action_state_changed`. During Attack presentation, or during Move's camera lead-in before `TacticalUnit.is_moving` became true, End Turn could remain clickable and advance the phase.
- **Reproduction:** force the integrated action barrier active, invoke `end_current_turn()`, and observe the phase and `turn_ended` signal. Before the fix, the command advanced; the new regression requires both to remain unchanged.
- **Impact:** authoritative phase/active-unit state could change before blocking presentation completed, creating replay ordering risk and rare double-progression behavior.
- **Action:** fixed. `TurnManager` rejects End Turn while its injected action barrier is active. `TurnHUDController` disables End Turn on the same lifecycle signal and restores phase-appropriate state on release.
- **Classification:** **Remove** the bypass; the barrier itself is **Keep**.

### Low — Current documentation described retired runtime paths

- **Location:** `docs/architecture.md` movement, attack, RNG, and replay sections; root `README.md`; `docs/architecture/tactical-action-migration-plan.md`; character roadmap/index; `export_presets.cfg`.
- **Evidence:** current guidance still said `BattleController` owned combat RNG, described runtime `AttackAction`/`MoveAction`/`RescueAction`/`ExtractAction` objects, called the authoritative replay journal future work, and retained an export exclusion for the deleted VRoid directory.
- **Impact:** a human developer could edit or search for retired APIs and misunderstand which system owns a rule. The stale export pattern was harmless but misleading.
- **Action:** corrected current architecture and README language, marked the migration and character roadmaps as historical, clarified the docs index, and removed the obsolete VRoid export filter.
- **Classification:** **Remove** stale current instructions; **Keep** explicitly labelled historical research.

### Informational — Explicit controller adapters are legitimate orchestration

- **Location:** `systems/battle_controller.gd`, `try_attack`, `try_move`, `try_end_unit_turn`, `try_defend`, and `try_mission_action`.
- **Evidence:** each adapter builds a typed request and delegates to `TacticalActionService`; none spends AP, rolls combat, commits occupancy, or mutates objectives. Player and AI call sites remain easy to trace.
- **Impact:** these methods improve Godot-facing discoverability without creating a second authority.
- **Recommended action:** retain them. Do not replace them with a registry or generic handler hierarchy merely to reduce branches.
- **Classification:** **Keep**.

### Informational — Mission callbacks preserve domain ownership

- **Location:** `BattleController._validate_mission_action` / `_commit_mission_action`; `ObjectiveManager.can_rescue`, `can_extract`, `complete_rescue`, and `complete_extraction`.
- **Evidence:** the action service owns transaction, revision, lifecycle, and typed result construction. The objective manager owns mission-specific legality and consequences. The injected callables cross that boundary without making presentation authoritative.
- **Impact:** ownership is explicit, though navigation requires following one plainly named callback from service setup.
- **Recommended action:** retain until several new interaction types demonstrate concrete duplication.
- **Classification:** **Keep**.

### Informational — Defeat cleanup remains battle orchestration

- **Location:** `BattleController._on_unit_defeated`.
- **Evidence:** damage is committed by the action service. The controller receives the unit's general defeated signal, emits the battle event used by objectives, removes grid/turn membership through their owners, clears selection modes, and requests visual defeat only when presentation was not deferred. This also supports defeat sources other than Attack.
- **Impact:** the method is broader lifecycle coordination rather than duplicate damage authority.
- **Recommended action:** retain; revisit only when conditions or hazards introduce a dedicated unit-lifecycle owner.
- **Classification:** **Defer** to the Goal 01 final audit.

### Informational — Legacy compatibility is isolated and explicit

- **Location:** `TacticalActionService.query_simple` / `submit_simple`; `BattleReplayPlayer._replay_simple`; `BattleReplayRecording.LEGACY_SCHEMA_VERSION`.
- **Evidence:** current gameplay authors Wait. Defend remains accepted for schema-2 recordings, and replay validation names schema 2 as the only supported legacy boundary.
- **Impact:** small, understandable compatibility cost with no competing production path.
- **Recommended action:** keep until the documented replay compatibility policy changes.
- **Classification:** **Keep**.

### Low — Presentation interruption recovery remains bounded rather than cancellable

- **Location:** `TacticalActionPresenter._wait_for_movement` and `_safe_delay`.
- **Evidence:** missing actors return with actionable `presentation_error`; movement watches actor lifetime and scene membership and has a 30-second timeout before snapping. Suppressed presentation synchronizes transforms immediately. The architecture does not yet expose an explicit cancellation token for scene replacement.
- **Impact:** no reproduced simulation lock in current battle teardown because the action service and presenter leave the tree together. A future persistent battle service or mid-action scene handoff would need a clearer cancellation contract.
- **Recommended action:** do not add speculative cancellation infrastructure now; include it in the final Goal 01 lifecycle audit if scene handoff requirements appear.
- **Classification:** **Defer**.

## C. Ownership verdict

The current implementation respects **Query → Validate → Resolve → Commit → Present**.

| Operation | Request / legality | Resolution and commit | Record | Presentation / progression |
| --- | --- | --- | --- | --- |
| Attack | Player/AI/replay request; service plus `CombatRules` | Service draws deterministic RNG and commits AP, damage, defeat consequences, revision | Service committed result | Presenter; TurnManager waits on barrier |
| Move | Player/AI/replay request; service plus Pathfinder/GridManager query | Service commits AP and occupancy, then emits parent Move consequences | One Move result, including automatic Reach/Rescue state | Presenter consumes committed path |
| Wait / Defend | Shared simple query and service validation | Service commits AP/defending state | One typed result | Presenter; selection deferred behind barrier |
| Rescue / Extract | Shared mission query; ObjectiveManager owns domain rules | Service transaction calls ObjectiveManager domain commit | One typed result | Presenter; Extract disposes visuals after boarding |
| End Turn | HUD/AI/replay command to TurnManager | TurnManager changes queue/phase and revision bridge observes it | TurnManager command record | Now rejected while action barrier is active |
| Depart | ObjectiveManager legality and command | ObjectiveManager/TurnManager commit mission result and revision | ObjectiveManager command signal | Mission UI |
| Defeat | Service commits damage; unit signal announces defeat | GridManager/TurnManager removal coordinated by controller; ObjectiveManager consumes battle event | Parent action result | Presenter consumes defeated result |

No duplicate writable AP, HP, occupancy, objective, action-busy, or combat-RNG authority was found. The remaining ambiguity is defeat lifecycle coordination in `BattleController`; it is justified today but should be reconsidered when non-attack conditions become real.

## D. Replay and lifecycle verdict

- Accepted unit actions emit one committed typed result. Rejected, stale, duplicate, and reentrant requests emit rejection only and consume no combat RNG.
- Busy transitions are one `true` and one `false` per accepted action. The controller's property is a computed view of the service, and its signal mirrors service transitions.
- Synchronous `action_committed` observers cannot submit nested work because the service remains busy.
- End Turn now observes the same barrier, closing the found premature-phase path. Existing active-unit checks prevent AP exhaustion and AI completion from advancing twice.
- Automatic Reach/Rescue remains captured in the parent Move result. It does not create a nested replay record.
- Extraction removes authoritative occupancy/roster state during commit but retains registry identity until presentation cleanup. Replay captures the result before cleanup and fingerprints authoritative grid/roster state.
- Schema 3 reconstructs requests through normal authority, compares transaction/revisions, typed resolved fields, and fingerprints. Schema 2 compatibility remains explicit, including Defend and legacy coalescing.
- Normal, suppressed, and headless paths use the same committed results. Presentation state is absent from fingerprints.

No remaining high-severity replay or lifecycle defect was reproduced.

## E. Human-editability verdict

Ownership is discoverable without a generic framework:

- Attack legality/accuracy: `systems/combat_rules.gd`; activation and cost: `TacticalActionService.query_attack`.
- Movement legality/path: `BattleController._query_move_data`, `Pathfinder`, and `GridManager`; transaction: `TacticalActionService.query_move` / `submit_move`.
- AP/action availability: plainly named action queries in `TacticalActionService`.
- Objectives/extraction: `systems/objectives/objective_manager.gd`.
- Turn progression: `systems/turn_manager.gd`.
- AI preference: `units/ai_controller.gd` and focused scorer scripts.
- Animation/cameras: `presentation/actions/tactical_action_presenter.gd`, `UnitVisualAdapter`, and `ActionCameraDirector`.
- Replay: the four plainly named files under `systems/replay/`.

The main human-editability defect was stale documentation, corrected in this inspection. The explicit controller entry points and mission callbacks should remain.

## F. Proposed fixes

### Must fix before 01.10

- **Completed:** block End Turn at the authoritative TurnManager boundary while an action is resolving/presenting.
- **Completed:** mirror that barrier in the End Turn HUD.

### Small safe cleanup

- **Completed:** correct stale current architecture and README text.
- **Completed:** label historical migration/VRoid plans as history.
- **Completed:** remove the obsolete VRoid export exclusion.

### Defer to Goal 01 final audit

- Reassess whether defeat lifecycle coordination deserves its own owner after conditions/hazards exist.
- Reassess explicit presentation cancellation only if persistent services or mid-action scene handoff become requirements.

### Defer to a future gameplay milestone

- Decide when schema-2 Defend compatibility may be retired.
- Revisit a shared interaction abstraction only after doors, terminals, or similar actions reveal actual repeated contracts.

## G. Test results

All commands were launched directly from the repository root with Godot 4.7.2:

| Command | Result |
| --- | --- |
| `godot_console --headless --path . --editor --quit` | Passed; no parse/import errors or warnings |
| `godot_console --headless --path . -s tests/tactical_action_service_test.gd` | 0 failures; includes stale/reentrant/duplicate requests, RNG safety, busy parity, consecutive Wait, single advancement, and blocked End Turn |
| `godot_console --headless --path . -s tests/tactical_action_presenter_test.gd` | 0 failures |
| `godot_console --headless --path . -s tests/core_objectives_smoke.gd` | 0 failures |
| `godot_console --headless --path . -s tests/battle_pause_menu_smoke.gd` | 0 failures |
| `godot_console --headless --path . -s tests/battle_replay_smoke.gd` | 39/39 records verified; 0 failures |
| `godot_console --headless --path . -s tests/rescue_battle_replay_smoke.gd` | 283/283 records verified; 0 failures |
| `godot_console --headless --path . -s tests/departure_replay_smoke.gd` | 12/12 records verified; 0 failures |
| `godot_console --headless --path . -s tests/replay_schema_test.gd` | 0 failures; schema 3 and schema 2 boundary passed |
| `godot_console --headless --path . -s tests/ai_match_determinism_smoke.gd` | Determinism passed |
| `godot_console --headless --path . -s tests/battle_dependency_isolation_test.gd` | 0 failures |
| `godot_console --headless --path . -s tests/prototype_1_milestone.gd` | 15/15 completed, 0 issues; 0 failures |

No test was skipped. Direct runs emitted no unexpected errors or warnings.

## H. Recommendation

FuseFire is ready for Task 01.10. The inspection found and closed one medium-severity phase-progression bypass, corrected misleading current documentation, and found no remaining critical or high-severity ownership, replay, determinism, or lifecycle defect. Goal 01 is not complete; the deferred lifecycle and compatibility questions belong in the planned final stabilization review.
