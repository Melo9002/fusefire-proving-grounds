# Task 12: Animation workbench and visual diagnostics (report)

Maintained guides: [`docs/animation.md`](../animation.md) (architecture, diagrams, extension guide) and [`tools/animation_workbench/README.md`](../../tools/animation_workbench/README.md) (quick start, tabs, scenarios, diagnosing). This report is only what changed, what was observed, tests, limits and next steps. Baseline: `4f36e4d`, branch `main`.

## 1. Existing capabilities reused and improved

Reused as they were: locomotion, scripted gait transitions, turns, cover and authorised attack, ladder, stair and path benches, rescue carry, camera views and slow motion, `HandContactDiagnostics`, `PoseOwnership`, `RigResolver`, the presenter's holds and `ActionHandle`s. Every control and key still exists and does the same (`F1`, hide panel, is the only new key). The 305-line `LocomotionTestPanel` keeps its behaviour but is now grouped into folding sections inside the Scenario tab; the viewport no longer carries the long key list (it is in *Scenario > Keyboard shortcuts*), and the status line keeps its facts (`STATE`, `IK`, `hand diagnostics`, `pose`, `view`).

What was missing: an overview of the rig, any view of presentation state or history, any view of pose-stage ownership at runtime, contact error for anything but weapon grips, scenarios, pause or stepping, a way to explain an incompatible profile, a way to switch character and weapon state without editing the scene, and any test that exercised the workbench as a tool.

## 2. New diagnostics (all in `presentation/diagnostics/`, read-only, rig-only, opt-in)

| Class | Answers |
|---|---|
| `RigInspection` | identity, required and optional roles and their bones, measured proportions, capabilities and reasons, degraded stages, equipment; `check_profile` explains an incompatible profile without building a rig |
| `PoseStageReport` | the stages in the order the skeleton really runs them (checked against `PoseOwnership.STAGE_ORDER`), declared writes, live weights, "why is this bone moving", bones per stage |
| `PresentationMonitor` | live snapshot from public accessors and a bounded event history (state transitions, hold start, end and replacement with rank, contexts, posture, readiness, action outcomes via `watch(handle)`) |
| `ContactErrorDiagnostics` | per hand: target, final wrist, error, shoulder reach, margin, deficit, owner and weight, orientation vectors; per foot: stair or ladder plan against the final ankle; selectable layers; recording and summary |
| `MotionTrail`, `BoneHighlight` | root trail coloured by speed; bones of a role or stage marked on the body |

One small production addition: `CharacterPresenter.hold_report()` (a read-only view of the running hold). Nothing else in production changed.

## 3. Workflow

Four tabs for four questions (Character, Scenario, Diagnostics, Evidence), docked right at full height; the 3D view is shifted by half the panel's width so the character stays centred in the free area. Character and weapon state switch with *Apply and reload* (or `--character=`, `--unarmed`, `--scenario=`, `--tab=`); a scene reload is the one clean reset. Workbench code is split: panel and four tab scripts (`ui/`), scenario data, runner, session and diagnostics owner, instead of growing `pose_workbench.gd` (which still gained about 150 lines: public controls, pause, reset).

## 4. Character compatibility

MIRA and Small MIRA, armed and unarmed, load without a mission (tested). The compatibility check resolves any profile against the current skeleton: a profile mapping `LeftHand` to a missing bone gives `E_BONE_NOT_FOUND [LeftHand] ... -> correct the BoneMap entry` and a socket error; a profile with no bone map is incompatible. (The Character tab also offers the alternate test fixture as a candidate; its result against MIRA's skeleton was not examined.) Nothing substitutes MIRA assumptions silently.

## 5. Scenarios

`tactical` (armed only; the unarmed Scenario tab disables it with the reason), `exploration` (armed or unarmed), `contacts` (a 12-tread stair, then a 4 m ladder, interrupted mid-climb). All three drive the real presenter and rig, run on both humanoids where supported, and end through the workbench's reset (finished, stopped or replaced). `tactical` and `contacts` carry a "synthetic context" label. Observed: scenario `exploration` shows `gesture acknowledge: INTERRUPTED` followed by `hold replaced (gesture -> reaction)` in the history; on a 0.1667/0.3333 stair the planned foothold and the final ankle agree to under 1 mm while the plan has hold of the leg.

## 6. Diagrams and documentation

`docs/animation.md` gained *Diagnostics and the workbench*: a data-flow diagram with the observation points, the modifier order and ownership table, how to add a diagnostic, and the portability assessment (section 10 below). The workbench README has the quick start, the new-humanoid guide and a reproducible diagnosis (#55). Renders: `docs/claude/images/task12/` (8 images, regenerate with `tests/workbench_capture.gd`).

## 7. Overhead

Measured by `tools/quality/diagnostics_overhead_probe.gd` (CPU, headless): monitor refresh 14.5 us, contact measure 12.6 us (50 us with drawing), stage report 94 us, rig report 60 us. A frame with the monitor and contact overlay on cost the same as with them off within noise (6.86 against 6.90 ms headless; that figure is the rig's own work). Panel readouts refresh at 10 Hz.

## 8. Tests

New: `workbench_diagnostics_test` (217 checks: both humanoids, armed and unarmed) and `workbench_scenarios_test` (115 checks). Updated, with the reason: `unit_visual_hand_contact_diagnostics_test` (intentional design change: the key list moved from the status line to the panel, so one assertion checks the list where it now lives and the others still read the same status vocabulary; every key assertion is unchanged); `rig_profile_test` (see below).

Negative controls that fail the diagnostic or test as they should: a profile mapping a missing bone, a profile with no bone map, an injected degraded stage; a skeleton with a stage moved out of order and a stage switched off; the arm IK stage off (the target-to-wrist error rises by more than 5 cm); an unreachable ladder contact (Small MIRA flags 28 of 48 samples, MIRA 3, each flagged sample agreeing with an independent recomputation); a sample taken outside `skeleton_updated` (differs from the final pose by centimetres, which is why it has no entry point); with every diagnostic on the final pose differs by under 0.5 mm from with them off (read-only); switching off leaves no node, overlay or listener. Seven deliberate breakages of the code under test (a listener left connected, reach understated, order check disabled, a monitor that stays "listening", a scenario end that does not reset, a reset that leaves the ladder, a step twice as long) were each caught.

Results: `changed -Since HEAD` 55 PASS 0 FAIL; animation FAST 26 PASS 0 FAIL; catalog consistent (277); the pose trace (39 scenarios, bone positions, targets, crouch, passenger, phases, flags) and the route trace (853 routes) are identical to the Task 11 baselines, as expected for a change whose only production edit is a read accessor. The full Ironclad suite was not run.

Pre-existing failure found and fixed: `rig_profile_test` failed on `4f36e4d` itself. It compared the stair planner's `leg_length` (thigh plus shin, from the hip joint) with the resolver's `hips_to_ankle` (from the Hips bone), 8% apart; the resolver measures `leg_length` for exactly that purpose (0.767 against 0.77). Obsolete quantity, same invariant (within 3%), no assertion weakened.

## 9. Rendered evidence and limits

Launched the real workbench with graphics (D3D12, RTX 5060) at 1600x900 and 1280x720; inspected both humanoids in all three scenarios. Fixed from what was seen: the old key list overlapped the character; the title always said MIRA; long mono lines and folding titles widened the panel past the window; the contact readout was below the fold; the compatibility result was hidden in a folded section; a cover wall hid the character (scenarios now choose a side view); the panel was translucent. Limits: below about 1280 px of window width the 11-12 pt tables are small (the project stretches its canvas); screenshots are single frames (scenarios are paused scrubs); no human tried the controls interactively here, so interaction was exercised through the tests and the paused capture, not by hand.

## 10. Remaining defects, deferred, and the AniLab assessment

* Issue #55 (Small MIRA ladder reach) is now visible in the workbench and unchanged.
* Not done: stateful frame seeking (position-driven benches scrub; stateful behaviour is replayed by reset and play); a recorded per-stage bone-change measurement in the UI (the isolation method stays in `pose_ownership_test`); the monitor cannot see a state changed by bypassing the controller's signal; `weapon_pose_modifier_test` (failing in the Nov 21 full run) was not re-run and the full suite was not run; no one-click "add character" (it is two lines in `CHARACTER_RIGS`).
* AniLab (assessment only): the stack in `presentation/characters/` and all of `presentation/diagnostics/` import no gameplay code (the only tactical names are in comments). FuseFire-specific: `CharacterRig`'s default `character_scene` is MIRA's model; the cover, rescue, ladder and stair specialisations; the tactical adapter, cover edge policy and route builder; the workbench's character list. Helpful before any extraction: a profile-only way to name a character, the capability list as the interface of a stage, the diagnostics' read-only accessors kept as the public surface. Nothing was created or started toward extraction.

## 11. Changed files

New: `presentation/diagnostics/{rig_inspection,pose_stage_report,presentation_monitor,contact_error_diagnostics,motion_trail,bone_highlight}.gd`; `tools/animation_workbench/{workbench_session,workbench_diagnostics,workbench_scenarios,scenario_runner}.gd` and `ui/{workbench_ui,workbench_panel,character_tab,scenario_tab,diagnostics_tab,evidence_tab}.gd`; `tests/{workbench_diagnostics_test,workbench_scenarios_test,workbench_capture}.gd`; `tools/quality/diagnostics_overhead_probe.gd`; `docs/claude/images/task12/`. Edited: `character_presenter.gd` (`hold_report`), `pose_workbench.gd`, `locomotion_test_panel.gd`, `tests/catalog.json`, `tests/unit_visual_hand_contact_diagnostics_test.gd`, `tests/rig_profile_test.gd`, `docs/animation.md`, the workbench README. The six Kenney `.import` files and two `.svg.import` files are untouched and unstaged.
