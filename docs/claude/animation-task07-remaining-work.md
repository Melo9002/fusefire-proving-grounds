# Task 07: remaining work and completion assessment

Written 2026-11-21 against the repository as it is now. Evidence is code, call paths and tests that were read or run; nothing here is carried over from an earlier report without a check. No production file was changed to write it. **Updated after Packages 7 to 10** (rows and batches below carry their current status; the evidence for each package is in `animation-presenter-foundation-2026-11-20.md`, sections "Package 7" to "Package 10"). The text of section 4 is the original plan and is kept as history; its batches are all done.

## 1. Status in one paragraph

Task 07's migration is complete pending the owner's review. Packages 1 to 6 finished the behavioural half (one presenter per character owns time, locomotion intent, posture arbitration, the attack lifecycle, the aim hold, timed states, defeat and the rescue clock; modifiers take typed inputs; pose ownership is declared; rescue, attack, hit and defeat settle `ActionHandle`s). Package 7 moved facing, the committed aim and the pending pickup into the presenter; Package 8 extracted route construction into `TacticalRouteBuilder` and typed the traversal state; Package 9 made the rig profile drive configuration, equipment optional and the foot-point convention part of the composition; Package 10 replaced inheritance with composition, split the cover policy, removed the superseded code, reorganised the modules and ran the final validation. Nothing in the original structural half remains open; see "Package 10 outcome" at the end for the final status.

**Git state.** Packages 1 to 9 are committed (Package 9 is `5da29b0`). Package 10 is committed as separate, individually validated checkpoints (listed under "Package 10 outcome"), not pushed.

## 2. Requirements and their status

Sources: the Task 04 migration table (M0 to M9), the reconciled Task 06 sequence (S0 to S15, `animation-module-organization` section 18), and the owner decisions of 2026-11-20 (facing, unarmed, base occupancy).

| # | Requirement | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Safety nets, selector fix, boundary and update-order tests (S0, M0) | **DONE** | `animation_module_boundaries_test` (778 checks), `presentation_frame_driver_test`, `pose_trace.gd`, catalog check; the changed-file selector ran 112 tests in Package 6 |
| 2 | `class_name CharacterRig` (S1) | **DONE** | `class_name CharacterRig` is the rig; the tactical adapter and the workbench no longer extend it (requirement 24) |
| 3 | One driver, `CharacterPresenter` over the rig, idempotent setters and snapshot (S6, M2, M3) | **DONE** | `character_presenter.gd`: `tick`, `apply_posture`, `advance_actions`, `intent()`; both hosts call it (`presentation_frame_driver_test`) |
| 4 | Source-keyed posture arbitration, all writers routed (M3) | **DONE** | `posture_arbiter.gd`; cover (CONTEXT), rescue (ACTION), workbench sources; rig writes only in `apply_posture_target` (ratchet) |
| 5 | Typed modifier inputs, supported callback, declared ownership (S5, M1) | **DONE** | 0 string lookups into the rig, 5 of 5 `_process_modification_with_delta`, `PoseOwnership.validate()`. The Package 5 residue is resolved: `CoverCrouchModifier.setup(target, bones: RigBones, forward)`, `LocomotionPoseModifier.setup(target, bones: RigBones, axes: RigAxes)` and `HandGripModifier.setup(target, bones: RigBones)` are typed (Package 9, ratcheted); `crouch_pose` survives only as a local result of the modifier's own pure solver, not as an interface |
| 6 | Attack, aim, hit, defeat lifecycles and handles (S7, M4, M6) | **DONE** | `attack_sequence.gd`, `aim_hold.gd`, `begin_hold`, `begin_defeat`; `combat_presentation_lifecycle_test` (49 checks); the tactical wait observes `handle.shot` |
| 7 | Rescue lifecycle, posture and handles | **DONE** | `rescue_presentation_handle_test` (47); clock advanced by the presenter for both hosts |
| 8 | Movement and traversal completion as handles (M6 for moves) | **DECIDED: no handle** | The owner decision of Package 7 keeps the authoritative movement-completion contract (`TacticalActionPresenter._wait_for_movement` observing `is_moving`) unless a real lifecycle need appears; none has. Not a remaining requirement |
| 9 | Facing owned by the presenter, authority honoured (owner decision 1, M3) | **DONE** | `CharacterPresenter.face_point/face_yaw/face_authoritative/turn_toward_yaw/turn_root_toward/hold_facing`; the rig's `apply_facing_yaw/apply_root_yaw/absorb_facing_change` are the only yaw writers (ratchet: 5 in the rig, 1 in the presenter, 0 in the adapter, workbench, `TacticalUnit`, tactical presenter); `presenter_facing_test` (32 checks); the Shield stance's committed `shield_facing` is shown through `face_authoritative` and equals the old threat-facing within 0.01 degrees on five production placements; 31 of 31 trace scenarios identical |
| 10 | Committed Aim reaches presentation as typed input | **DONE** | `presenter.aim_committed` (set by the adapter from `tactical_state.is_aiming`), `AimHold` progressed in `presenter.tick`, `aim_hold_changed`; the presenter reads no tactical type (ratchet); `adapter_boundary_test`, `aim_hold_presentation_test` |
| 11 | Route and traversal expansion out of `TacticalUnit` (S9, M5) | **DONE** | `presentation/tactical/tactical_route_builder.gd` (pure functions of explicit inputs); `TacticalUnit` 518 to 330 lines and executes the walk only; `route_trace.gd`: 853 routes x plain and refined, walked frame by frame, 0 discrete differences and an exact 0 float difference against the committed baseline; `tactical_route_builder_test` (24), the `traversal_*` family and the replay tests pass; ratchet in the boundary test |
| 12 | Traversal and stair state typed (`set_surface_run`) | **DONE** | `LadderClimb`/`LadderPose` and `StairWalk`/`StairPose` replace the four dictionaries; solvers unchanged (converted once); `traversal_state_test` (18); 36 of 36 pose-trace scenarios identical including five new traversal-transition scenarios; ratchet: no traversal or stair dictionary in the rig, adapter or workbench |
| 13 | Equipment state, unarmed humanoids, no rifle requirement (S11, M7, owner decision 2) | **DONE (Package 9, `5da29b0`)** | `weapon_scene` is null by default and chosen by the scene; `has_weapon()`/`equipment_state()`; unarmed arms hang via `apply_relaxed_hand_targets`; `unarmed_humanoid_test` (30 checks, real stack plus a production unarmed TacticalUnit); rendered `docs/claude/images/unarmed-sheet.png` |
| 14 | Rig profile drives configuration; no hard-coded skeleton (S2, S4, S5 role lookups, Task 09 enabler) | **DONE (Package 9, `5da29b0`)** | `RigBones` (typed roles from the profile) feeds the rig, clip builder, controller, three modifiers, passenger pose and pose ownership; no `mixamorig`/`J_Bip` in production code (ratcheted); pose trace 39/39 identical; `rig_bones_test` 17 checks incl. a differently named skeleton |
| 15 | Foot-point convention in the composition, not the scene (S13, M8) | **DONE (Package 9, `5da29b0`)** | scene offset removed; `TacticalUnit._place_visual` is the single composition point; `foot_point_problems()` checks scale and rotation; world-space positions identical (0.000000 m) in three unit-hosted scenarios |
| 16 | Cover profile split into motion numbers and selection policy (S10) | **DONE (Package 10)** | `CoverPostureProfile` (`motion/`) keeps the body-motion numbers; `CoverEdgePolicy` (`presentation/tactical/`) holds the edge-selection and target-aware thresholds, owned by the tactical host and read by `CoverEdgeSelector`; defaults unchanged; `cover_edge_selection_test` (28), `cover_target_aware_test` (41), ratchet |
| 17 | Module organisation: leaf moves, tactical module, workbench move (S3, S8, S12) | **DONE (Package 10)** | `presentation/characters/runtime/` is gone: presenter/, rig/, rig/modifiers/, motion/, equipment/ (shared, zero gameplay importers: the ratchet allowlist is empty); `presentation/tactical/` holds the adapter, action presenter, cover selector and policy, pose context and route builder; the workbench is in `tools/animation_workbench/`; scripts moved with their `.uid`; resource-reference audit and import clean |
| 18 | Shims removed, private-state tests converted (S14, M9) | **DONE for shims; private-state access left where it is a diagnostic** | the adapter overrides, the rig's virtual hooks (`_loaded_locomotion`, `_update_weapon_pose`, `_align_weapon_to_aim`) and the dead constants and methods are gone (`GRIP_OFFSET`, `sight_offset`, `clear_scripted_motion`); the weapon-target "legacy path" is documented as the editor-preview path. Low-level rig tests keep reading internal skeletal state through `host.rig` on purpose (no public API was added to satisfy a naming rule) |
| 19 | Renames to tactical names (S15) | **DONE for the adapter; `TacticalActionPresenter` kept** | `UnitVisualAdapter` is `TacticalCharacterAdapter`; `TacticalActionPresenter` keeps its name (the plan's `TacticalActionSequencer` was marked "later" and nothing needs it); `CoverPostureProfile` keeps its name because it holds cover-specific numbers |
| 20 | Replay independence | **DONE** | presentation never writes authority; replay tests pass; the one reverse read is gone: `battle_replay_player.gd` asks `TacticalUnit.get_presentation_facing()` (a read-only camera hint), ratchet and test `adapter_boundary_test` |
| 21 | Cleanup on defeat, removal, interruption | **DONE** | handles settle on teardown; `TacticalUnit.finish_defeat_presentation` waits on `presenter.removal_handle(1.25)` (defeat finished and the floor passed, INTERRUPTED on removal, 6 s deadline); one documented timer remains for a visual that does not process (ratchet); defeat is terminal and idempotent; `adapter_boundary_test` |
| 22 | Canonical docs, stale guide retired (S15 side) | **DONE (Package 10)** | `docs/animation.md` is the maintained guide; `presentation/characters/README.md`, `tools/animation_workbench/README.md`; the editing guide is a short current-path reference; the developer, where-to-go and procedural-layer reports carry a superseded banner |
| 23 | Interruption precedence reconciled with Task 04 section 14 | **DONE, two documented differences** | defeat terminal and refusing later requests; a hit ends an attack; a hit during a committed rescue lift is SKIPPED; a newer attack ends a running hit (reaction fire shows on time); persistent aim never blocks. The two differences from the contract table and their reasons are in the Package 7 section; `adapter_boundary_test` |
| 24 | Context host separated from the skeletal implementation: composition, not inheritance (owner resolution D1) | **DONE (Package 10)** | `TacticalCharacterAdapter` and the pose workbench are plain `Node3D` hosts of a `CharacterRig` child (`rig`) and its presenter, driving them once per frame; explicit hooks `rig.loaded_query`, `rig.aim_blend_follows_clips`, `rig.update_weapon_pose()` replace the overrides; ratchets (`extends`, no frame callback in the rig, scenes host a `Rig` child); pose trace 39 of 39 and route trace 853 of 853 identical to Package 9 |

**Composition (resolved).** The owner resolved in Package 7 that the inheritance would be removed in Package 10; it was (requirement 24).

## 3. Remaining legacy architecture and where it goes

**Status after Package 10:** every row below is done. Route construction and typed traversal state (Package 8); equipment, role lookups and foot-point (Package 9); the module moves (Package 10). `RigPoseTargets` was kept deliberately (it is the typed same-pass boundary, Package 9 decision), as were `preview_carrying` and the cosmetic effects (documented in `docs/animation.md`). Tests that read private rig members were not converted wholesale: low-level rig tests read internal skeletal state through `host.rig` on purpose, and the retired shims they depended on are gone. The table is the record of what was removed and is otherwise historical.

| Legacy item | Consumers | Removal or replacement | Batch |
| --- | --- | --- | --- |
| ~~`face_world_position`, cover yaw absorption, ladder yaw writes in the adapter~~ | `TacticalUnit.face_world_position`, `battle_controller.gd:383`, `tactical_action_presenter.gd:109`, the adapter itself | **Done in Package 7:** the presenter decides and the rig applies; the adapter only translates (`face_world_position`, `face_committed_direction`, `_facing_absorbed_by_cover`) | 1 |
| ~~Adapter read of `tactical_state.is_aiming` (`_aim_should_hold`)~~ | `_sync_aim_hold` | **Done in Package 7:** a typed `aim_committed` input; the progression is in `presenter.tick` | 1 |
| ~~Pending pickup (`_pending_pickup_world`, `_pending_lying_basis`, `_pending_handle`)~~ | `present_pickup`, `present_movement_end`, 3 tests | **Done in Package 7:** `PendingPickup` and `hold_pickup/arrive_pickup/cancel_pending_pickup` in the presenter; the adapter keeps `pickup_pending()` as a query | 1 |
| ~~`TacticalUnit.finish_defeat_presentation` timer~~ | `tactical_action_presenter.gd` (3 call sites), `present_attack_impact` | **Done in Package 7:** `removal_handle`; one timer remains for a non-processing visual | 1 |
| ~~Replay camera read of adapter facing~~ | `battle_replay_player.gd:218` | **Done in Package 7:** `TacticalUnit.get_presentation_facing()` | 1 |
| Route and traversal expansion in `TacticalUnit` (about 200 lines) | `move_along_path`, the `traversal_*` family, `traversal_timing_contract_test`, `traversal_replay_determinism_test` | move byte-for-byte to `presentation/tactical/tactical_route_builder.gd`; `TacticalUnit` keeps executing movement | 2 |
| Rig traversal and stair dictionaries | `animation_cleanup_test`, traversal and stair tests, workbench | typed surface-run state object; `begin_*`/`set_*_progress` set it; modifiers already read the typed input | 2 |
| `weapon_scene` required, rifle assumptions in the rig | rig, adapter, weapon pose modifier, rescue | optional equipment resource; unarmed is a normal configuration; weapon pose stage inactive without one | 3 |
| `mixamorig` literals, two dictionary-configured modifiers, MIRA constants | rig, clip builder, locomotion modifier, passenger pose | role lookups through `resolved_rig`; MIRA keeps explicit equal numbers | 3 |
| Foot-point offset in the scene and `standing_height` | `tactical_unit.gd` (4 sites), every test that instantiates the visual | compose the offset in the tactical host; presenter asserts a pure yaw basis and unit scale | 3 |
| Cosmetic tweens and timers outside the presenter | rig shot feedback (`_trigger_tween`, `_recoil_tween`, `create_timer(0.075)`, `character_rig.gd` about 1343 to 1354), controller `_visual_tween`, `present_boarding` tween, controller `play_sequence` demo timer | keep as visual-only effects (they change no pose timing the game waits on); record them in the ownership table. Only convert one if a test needs deterministic timing | 4 (document) |
| `RigPoseTargets` delegation, `preview_carrying` | rig | `preview_carrying` stays (genuine non-tactical capability); `RigPoseTargets` goes when equipment is data | 3 |
| ~~Workbench duplicate of the shot-state choice (`fire_cover_shot` mapping `shoot_left` and `shoot_right`)~~ | workbench, adapter `present_attack` | **Done in Package 7:** `CoverEdgeSelector.shot_state`, called by both hosts; the workbench's yaw writes also go through the presenter | 1 |
| 27-file `runtime/` directory, workbench under `art/`, 9 hard-coded paths | `battle_controller.gd`, 8 tests, scenes | move-only steps with reference rewrite | 4 |
| Tests on private members | 28 files | convert to public seams (the presenter's request API, `presenter.attack`, `presenter.aim`, a read-only posture report) as each owner changes, then remove the stragglers | each batch, finished in 4 |

**Deliberately kept:** every solver, clip builder, profile and tuned number; `RescueInteraction`; `WeaponReadiness`; `PoseOwnership`; the modifiers; and the cosmetic tweens above. None of it is obsolete architecture.

**Checked and clean:** no unreferenced production script (every `class_name` and path in `presentation/characters` has a consumer; the only unreferenced file is `research/animation_update_order_probe/update_order_probe.gd`, a deliberate probe); no independent action clock in `presentation/characters` other than the cosmetic ones listed; no direct crouch writer outside `apply_posture_target`.

## 4. The shortest safe completion sequence

Behaviour first, moves last: behaviour batches then work on the files where they are, and the move batch is move-only. Each batch ends with its own checkpoint.

### Batch 1 (Package 7): adapter boundary and persistent-state ownership: DONE (`58aa18e`)
- **Completes:** requirements 9, 10, 21 (owner), the pending pickup, the replay read, the workbench duplicate.
- **Affects:** `unit_visual_adapter.gd`, `character_presenter.gd`, `tactical_unit.gd` (`face_world_position`, `finish_defeat_presentation`), `tactical_action_presenter.gd`, `battle_replay_player.gd:218`, the workbench's facing and shot mapping.
- **Depends on:** the Package 6 commit (`d171913`).
- **Eliminates:** direct `rotation.y`/cover-yaw writes in the adapter, the adapter's read of `tactical_state`, `_pending_*` fields, the defeat timer in `TacticalUnit`, the workbench's duplicated shot mapping.
- **Tests:** new facing test (point, yaw, hold, velocity-follow, authority wins, idempotent repeat, teardown), `aim_hold_presentation_test`, `cover_*`, `presentation_frame_driver_test`, `tactical_pose_test`, rescue and combat lifecycle tests, replay tests, the pose trace (facing scenarios added), boundary ratchet.
- **Done when:** the adapter writes no facing, reads no tactical state for aim, and holds no lifecycle field; every hit or removal path settles its handles; the trace matches the baseline except for intentional changes recorded in the doc.

### Batch 2 (Package 8): route and traversal presentation: DONE (`7063b92`)
- **Completes:** requirements 8 (movement handle, if the timing contract allows it without changing deadlines), 11, 12.
- **Affects:** `units/tactical_unit.gd`, a new `presentation/tactical/tactical_route_builder.gd`, the rig's traversal and stair state, the workbench's ladder and stair demos.
- **Depends on:** Batch 1 (facing goes through the presenter before the route builder starts requesting it).
- **Eliminates:** about 200 lines of route code in `TacticalUnit`, the four rig dictionaries.
- **Tests:** the whole `traversal_*` family including `traversal_timing_contract_test` and `traversal_replay_determinism_test`, `surface_navigation_test`, `surface_placement_test`, stair and ladder gameplay tests, replay tests, a byte-for-byte route-output comparison (same inputs, same `presentation_path`, poses, kinds and speeds) before and after.
- **Done when:** the route builder's output equals the old output on every authored map and generated seed the existing tests use, and `TacticalUnit` only executes movement. This is the highest-risk batch: do it in two commits (extract unchanged, then typed state).

### Batch 3 (Package 9): rig independence (equipment, profile, foot-point): DONE (`5da29b0`). `RigPoseTargets` was reviewed and kept (it is the rig side of the typed same-pass boundary).
- **Completes:** requirements 13, 14, 15, 5 residue.
- **Affects:** `character_rig.gd`, `character_fallback_animation_builder.gd`, `locomotion_pose_modifier.gd`, `cover_crouch_modifier.gd`, `passive_passenger_pose.gd`, the weapon pose stage, `mira_0_unit_visual.tscn`, `tactical_unit.gd` (`standing_height`).
- **Depends on:** Batches 1 and 2 only to avoid editing the same rig regions at once.
- **Eliminates:** the `weapon_scene` assert and default coupling, about 40 skeleton-name literals, two dictionary `setup` APIs, `RigPoseTargets`, the scene's 1 m offset.
- **Tests:** a new unarmed-humanoid test (posture, locomotion, rescue as carrier and passenger, hit, defeat, with no weapon), the rig-profile tests, the pose trace on MIRA (identical numbers expected), every test that instantiates the visual, the playground test, ownership validation with the weapon stage inactive.
- **Done when:** MIRA runs from `resolved_rig` with numerically identical poses, a character with no equipment runs the full stack with a clean ownership report, and the only place the unit height appears is the tactical composition. It does **not** add a second humanoid (that is Task 09).

### Batch 4 (Package 10): composition, organisation, shims, docs and completion validation: DONE (see "Package 10 outcome" below; awaiting the owner\'s review)
- **Completes:** requirements 16, 17, 18, 19, 22, **and the owner's decision D1: remove `UnitVisualAdapter extends CharacterRig` as a dedicated, tested structural step BEFORE any file move** (the adapter becomes a tactical host that owns a rig; the workbench follows; 28 test files and the scene wiring are rewritten against public seams; the trace and the frame-driver test are the guards).
- **Affects:** file moves (leaf modules into `motion/`, `rig/modifiers/`, `equipment/`; the tactical module `presentation/tactical/`; the workbench to `tools/animation_workbench/`), renames, the cover profile split, remaining shim and private-state test cleanup, canonical docs.
- **Depends on:** Batches 1 to 3 (so no move chases a behaviour change).
- **Eliminates:** the `runtime/` directory as a mixed bag, the 28-file private-state dependence, stale guides.
- **Tests:** after every move step `--import`, the reference audit, the warning audit and `fast -Subsystem animation -Import`; then the full validation of section 5.
- **Done when:** section 5 is satisfied and the boundary test describes the final structure, not the transitional one.

## 5. Final validation and cleanup (Batch 4 end)

1. **Full regression run: once, after Batch 4**, not before: the code stops changing behaviour at the end of Batch 3 and Batch 4 only moves and renames, so one run at the end covers both. If Batch 2 changes route output unexpectedly, run the traversal and replay tiers at once instead of waiting. Plan for roughly the project's recorded full-tier time; run it unattended.
2. **Replay determinism:** the replay tests pass unchanged; no presentation read feeds authority (the boundary test scans for it).
3. **Pose equivalence:** `pose_trace.gd` before and after each behaviour batch, intentional differences listed with the reason; for Batch 3 the MIRA trace must match to the noise floor (0.064 degrees, 0.00005 m).
4. **Reference integrity:** `resource_references_test`, `--import` class-cache rebuild, the warning audit, every `res://` and `uid://` resolves after the moves.
5. **Lifecycle and cleanup:** the combat and rescue lifecycle tests plus a final cleanup-matrix check that no request, hold, handle, passenger or attachment survives teardown.
6. **Targeted visual inspection:** a few rendered captures (cover poses, aim, a hit, a rescue lift, a ladder, an unarmed character); the headless suites do not establish visual correctness.
7. **Performance:** the animation perf baseline (`tools/quality/animation_perf_baseline.gd`) before Batch 3 and after Batch 4; the Package 4 numbers (about 0.02 ms per character adapter, 0.01 ms modifier stack) are the reference.
8. **Deletion confirmed:** the ratchets name the retired state; add the batch-specific ones (no `tactical_state` read in the adapter, no route code in `TacticalUnit`, no skeleton literal outside the profile data, no `weapon_scene` requirement).
9. **Docs:** the canonical guide updated, the stale guides reconciled or retired, this file closed out with each requirement's final status.

**Known failures that are not regressions.** The warning audit prints parse errors from `artifacts/ai-audit-probe.gd` (gitignored, 17 Nov) and from `tools/quality/combat_current_audit.gd` (tracked, unchanged by Task 07); both come from an `evaluate()` argument type. Record the audit as "clean except these two pre-existing files". The two explicit-only render captures (`cover_target_aware_capture`, `pose_review_capture`) and `hand_contact_capture` are skipped by design and need a rendered run.

## 6. Open architectural decisions

- **D1. Composition: RESOLVED by the owner.** The tactical adapter and the rig are separated before Task 07 is complete: `UnitVisualAdapter extends CharacterRig` is removed in Package 10 as a dedicated, tested structural step before the file moves. Not done in Package 7.
- **D2. Facing authority input: RESOLVED and built.** The presenter honours a committed yaw; the Shield stance is wired through it with measured equivalence (no visible change). Locking the visual facing while a stance holds stays a mechanic decision, not Task 07.
- **D3. Movement completion as a handle: RESOLVED, not introduced.** The authoritative movement-completion contract is preserved.

## 7. Recommendation

**Task 07 is complete pending the owner's review.** Review the Package 10 evidence (`animation-presenter-foundation-2026-11-20.md`, "Package 10"), then close Task 07 and begin Task 08 only on the owner's instruction.

## Package 10 outcome (2026-11-21): final status

Checkpoints on `main` (not pushed): `e6c6748` composition, `ad0413e` cover split and dead-code removal, `dd848ca` runtime/ reorganisation, `9f28a94` workbench move, `5d14f66` adapter rename, `c5507b6` documentation, then the final evidence commit. Requirements 1 to 24 are DONE; none is BLOCKED; one is DECIDED (8: no handle for tactical movement). Nothing in this list was labelled deferred to declare completion. Items that remain are future animation work, not Task 07 requirements: an arm swing for unarmed walking, general body self-collision, the carry clip's dead upper-arm track (kept removed), a second humanoid (Task 09), the non-tactical demonstration (Task 08), broader capabilities and workbench diagnostics (Tasks 10 to 12). Task 07 is awaiting the owner's review; it is not declared closed here.

**Task 08 (2026-11-21, separate from Task 07, which stays closed).** The non-tactical context proof is implemented against issue #50; see "Task 08" in `animation-presenter-foundation-2026-11-20.md`. It needed no change to the shared rig or presenter.

