# ADDA capability inventory (as of `review/claude-adda`)

Legend. **Core** = ADDA component. **Shared** = quality infrastructure ADDA consumes. "Final pose" = sampled inside `skeleton_updated`. Kinds are `Measurement.Kind`.

## Core diagnostics (`presentation/diagnostics/`, read-only, opt-in, rig-only)

| Tool | Purpose | Invocation | Data | Sampling lifecycle | Contexts | Limits | Tests | Overlap |
|---|---|---|---|---|---|---|---|---|
| `RigInspection` | what a rig IS: identity, role-to-bone map, proportions, capabilities and why not, degraded stages, equipment; `check_profile` for a new skeleton | static functions; Character tab; Evidence JSON | plain data/text | none (pure functions of the rig) | any `CharacterRig` | `unknown` for facts the rig does not expose; no pose | workbench_diagnostics, workbench_scenarios | none |
| `PoseStageReport` | modifier stages in the order the skeleton runs them, DECLARED writes (`PoseOwnership`), live weights, "why is this bone moving" | static functions; Diagnostics tab | arrays/dicts | read live when asked | any rig | declared ownership plus weights is not a measured bone change (`tests/pose_ownership_test.gd` is the isolation method) | workbench_diagnostics | none |
| `PresentationMonitor` | live presenter state (state, speed, facing, posture, readiness, holds, context owners) and a bounded history of changes | `attach(rig)`; on in the workbench | snapshot + history on `presenter.time` | its own `_process` / host call; no pose | presenter-backed rigs | says what changed and when, never why (except `ActionHandle` outcomes) | presentation_authority, workbench_diagnostics | `MotionReadout` is its non-humanoid sibling |
| `MotionReadout` | text for a `MotionPresenter` snapshot (non-humanoid families) | static `text(snapshot)` | text | none | motion-family demo | tiny; not wired to the workbench | none (used by `research/motion_families_demo`) | `PresentationMonitor` |
| `ContactErrorDiagnostics` | per hand: target vs final wrist, shoulder reach vs arm length; per foot: stair/ladder plan vs final ankle; contact owner and weight; recording and summary; overlay | `attach(rig)`, `set_enabled(true)`; Diagnostics tab master toggle | `latest` dict; `evidence()` gives Measurements (TARGET_ERROR, REACH_FEASIBILITY, SUPPORT_CLAIM) | **via `PoseWitness.final_pose`**, stamped; no other entry point | ladder, stairs, carry, weapon, relaxed; armed and unarmed | no mesh contact; "UNREACHABLE" is a 97% display convention, not a rig limit; a claim is not physical support | workbench_diagnostics (221), exploration_actions, workbench_scenarios, adda_measurement_integrity | `HandContactDiagnostics` (weapon grips only) |
| `HandContactDiagnostics`, `HandContactSampler`, `HandContactOverlay` | hand-to-weapon: palms, wrists, grips against the weapon profile | `attach(rig, ui_host)`; key `H` in the workbench | sample dict (`meta.timing`, frame), overlay | `skeleton_updated`, after the weapon alignment listeners; `sample("manual")` exists and labels its timing | weapon-carrying rigs | needs a weapon; `manual` samples are labelled, not blocked | unit_visual_hand_contact_diagnostics, hand_contact_test, captures | `ContactErrorDiagnostics` (the generic version) |
| `MotionTrail` | root trajectory coloured by speed; bounded speed/facing history | `attach(rig)`; Diagnostics toggle | points, history | `_process` per frame, pausable, explicit `record_step` | any host with a character root | follows the root only; world-sliding benches give a point | workbench_diagnostics, workbench_scenarios | none |
| `BoneHighlight` | rings and parent lines at chosen bones' final positions | `attach(rig)`; stage/bone pickers | draw only | `skeleton_updated` while bones are chosen | any rig | joint positions only | workbench_diagnostics | none |
| `LadderClearance` | limb capsules and **sampled skinned-leg vertices** against rungs, rails and deck; knee spread; planted sole; offenders list | `LadderClearance.new(rig)` (self-samples via the witness); Diagnostics "Ladder landing" | joints, capsule overlap, vertex counts, `vertex_evidence()` | **via `PoseWitness`**, stamped; `status()` FRESH/STALE/UNAVAILABLE; `release()` | ladder with `LadderGeometry` / `LadderLanding` | vertices are samples, not a full intersection; capsules are approximations; hands and arms are not mesh-tested | ladder_mesh_clearance (66), ladder_climb and ladder_landing (**capsule, failing by design**), adda_measurement_integrity | none |
| `LadderOverlay` | red vertices inside bars, yellow knees, green pelvis, orange planned feet, label at the worst | `WorkbenchDiagnostics.set_ladder_overlay(true)`; checkbox | draw only | from `LadderClearance.sampled` | workbench | label shows the raw bone, no bone-name strings | workbench_ladder_closeup_capture (explicit) | the `ContactErrorDiagnostics` overlay is per contact; this one is per vertex |
| `SkinnedSurface` (`presentation/characters/rig`) | CPU linear-blend skinning of chosen bones' vertices, radius/reach measurement, `capture()` of poses inside the signal | `create(skeleton, bones)`; the rig uses it at build for limb radii | points, radii | `capture()` in the witness window; `points()` skins with the capture; `has_capture()` | any skinned humanoid | uses the mesh's own skin; at rest matches to 0.0000 m (`rest_error`) | ladder_mesh_clearance, adda_measurement_integrity | none |
| **NEW** `Measurement` | the envelope: kind, status, pose, space, unit, tolerance, method, limits, identity, frame/update stamp | `Measurement.make` / `missing`, `to_dict()` | JSON-friendly | n/a | any | an envelope, not a measurement; kinds never stand for each other | adda_measurement_integrity | consumed by the tools above |
| **NEW** `PoseWitness` | the single listener per skeleton; `final_pose` signal, update counter, stamps, `judge()` | `acquire(skeleton)` / `release()` (reference-counted) | counters | emits from its own `skeleton_updated` handler | any `Skeleton3D` | cannot tell from outside whether it is inside the signal (measured), so the contract is structural | adda_measurement_integrity; workbench_diagnostics (leaves no listener) | replaces direct connections |

## Core workbench (`tools/animation_workbench/`)

`pose_workbench.tscn` (the host; path unchanged), `WorkbenchSession` (launch state, `PRODUCT`), `WorkbenchDiagnostics` (lifetime of every optional tool; `shutdown()` leaves nothing), `WorkbenchScenarios` / `ScenarioRunner` (tactical, exploration, contacts, landing: data-driven steps), `LandingFixtures`, `LocomotionTestPanel`, the four tabs (Character, Scenario, Diagnostics, Evidence), the evidence export (`report()` JSON, now with an `adda` block).

## Shared quality infrastructure (consumed, not ADDA)

| What | Where | Role | Samples where |
|---|---|---|---|
| Ironclad runner and catalog | `tools/run_tests.ps1`, `tests/catalog.json`, `docs/quality/project-ironclad.md` | tiers, selection, failure reporting | n/a |
| Pose trace | `tools/quality/pose_trace.gd` (39 scenarios, 60 fps) | behavioural equivalence across refactors: final bones and target nodes | `skeleton_updated` callback (sound) |
| Route trace | `tools/quality/route_trace.gd` (853 routes) | gameplay-routing equivalence | n/a |
| Probes | `tools/quality/*_probe.gd` (ladder_sweep, ladder_offender, skeleton_update_timing, bone_axis, diagnostics_overhead, ...) | one-off, parameterised investigation | per probe |
| Ladder demo | `tools/quality/ladder_transfer_demo.gd` | normal-speed movie and counters | via `ContactErrorDiagnostics.sampled` (sound) |
| Captures | `tests/*_capture.gd` (explicit-only, need a GPU) | screenshots and sheets | n/a |
| Replay | `docs/replay.md` and the replay tests | tactical determinism | n/a |
| F3 battle inspection | `docs/debug-inspection.md` | AI and tactical inspector; has its own "STALE" snapshot idea | n/a (separate suite) |

## Overlaps and gaps

* Fine overlap: `HandContactDiagnostics` (weapon grips) and `ContactErrorDiagnostics` (any contact) answer different questions.
* Gaps for Assignment 2: no timeline across frames for the evidence (only `ContactErrorDiagnostics.history` scalars and `MotionTrail`); no spatial annotation beyond the ladder overlay; no structured session report that bundles Measurements over a scenario; full mesh intersection is not measured; `HandContactDiagnostics`, `BoneHighlight` and `MotionTrail` do not yet emit `Measurement`s.
