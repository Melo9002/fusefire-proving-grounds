# Task 14: architecture validation and Project Ironclad integration (report)

Baseline: `main` at `0c0b8ff` (Task 13), verified as HEAD and equal to `origin/main` before any change. Guide: [`docs/animation.md`](../animation.md) (section "The architecture at completion"). Tests: [`docs/quality/project-ironclad.md`](../quality/project-ironclad.md). Codex audit brief: [`task14-codex-audit-brief-2026-11-22.md`](task14-codex-audit-brief-2026-11-22.md).

## Executive verdict: PASS WITH KNOWN LIMITATIONS

The architecture matches its documented ownership model, its boundaries are now enforced by gates that were shown to fail when violated, and the deterministic pose and route traces are unchanged. One real lifecycle defect and two private-state leaks were fixed; one test-selection gap that would have hidden regressions in Task 13 code was closed. Bounded issues remain (listed under "Known issues and dispositions"). The independent Codex audit status is in "Independent audit". No claim below is broader than the evidence cited.

## What was inventoried (condensed)

| Component | Responsibility | Production consumers | Automated coverage | Extension point |
|---|---|---|---|---|
| `CharacterPresenter` (+ `AttackSequence`, `AimHold`, `PostureArbiter`, `ActionHandle`) | presentation time, intent, holds, handle lifecycles | `TacticalCharacterAdapter`, `ExplorationCharacterHost`, `PoseWorkbench` | `character_presenter_test`, `combat_presentation_lifecycle_test`, `posture_*`, `action_handle_test`, `presentation_frame_driver_test` | gestures, holds with rank |
| `CharacterRig` + modifiers + `PoseOwnership` | skeleton, roles, stage order and bone writes, IK targets, attachments | the same three hosts, `movement_ghost` | `pose_ownership_test`, `modifier_boundary_test`, `traversal_*`, `stair_contact_test`, `hand_contact_test` | add a stage |
| `rig_profile/`, `motion/`, `equipment/` | data and pure solvers | the rig | `rig_bones_test`, `rig_profile_test`, `humanoid_portability_test`, `unarmed_*` | new rig = profile and scenes |
| Hosts (`presentation/tactical`, `exploration`, workbench) | context translation | tactical battle, exploration playground, tool | `adapter_boundary_test`, `exploration_host_test`, `exploration_actions_test`, `workbench_*` | new host = a Node3D with a Rig child |
| `presentation/motion/` + `research/motion_families/` | family-neutral contract and non-humanoid examples | the demo scene, the opt-in bridge | `motion_contract_test`, family gate | extend `MotionPresenter` |
| `presentation/diagnostics/`, workbench | read-only observation and tooling | workbench only (nothing in the game creates them) | `workbench_diagnostics_test`, `workbench_scenarios_test`, gate C | add a diagnostic |

Documentation findings: the guide still described itself as "after Task 07" (fixed, restructured around the completed architecture); it had no consolidated dependency diagram, frame rules, test classification, procedure for adding a stage, or decision record (added); `docs/quality/project-ironclad.md` listed stale counts (FAST 80, smoke 18) and did not describe the Task 14 rules (fixed); `docs/architecture.md` is about generation and does not mention animation (left: `docs/index.md` already links the guide).

## Audit of the migration (claim, implementation, evidence)

| Claim | Implementation | Evidence | Status |
|---|---|---|---|
| Hosts consume one shared humanoid stack without duplicating it | three hosts own a `CharacterRig` and drive `presenter.tick` once | boundary-test composition rules; `presentation_frame_driver_test`; `context_independence_capture` exists but was not rerun | resolved |
| Shared presentation imports no tactical or gameplay types | `presentation/characters/` | boundary rule 1 (zero known importers) and the new gate B for contract, diagnostics, families, demo and workbench | resolved |
| Presentation does not decide legality or outcomes | requests flow one way; handles describe visuals only | `presentation_authority_test` (new): identical action records, state fingerprints, AP and cells with the presentation at 1x unobserved and 4x observed | resolved (see limits of the test) |
| One owner of presentation time and completion | presenter `time`, `ActionHandle` | boundary single-owner rules; frame-driver, handle and cleanup tests | resolved. Two wall-clock uses remain (below) |
| Posture arbitration deterministic | `PostureArbiter` (priority, then call-order counter) | `posture_arbiter_test`, `posture_ownership_test` | resolved |
| Modifier order and overlaps intentional; poses final only after modifiers | `PoseOwnership.STAGE_ORDER/WRITES/OVERLAPS`; diagnostics sample at `skeleton_updated` | `pose_ownership_test` (measures real bone changes), gate C | resolved; `pose_ownership_test` is intermittently flaky (below) |
| Actions settle once, cleanup releases state | `ActionHandle`, `teardown()` | `action_handle_test`, `animation_cleanup_test`, lifecycle test | one defect found and fixed (below) |
| MIRA and Small MIRA share one implementation | profile and scene data only | `humanoid_portability_test`, `rig_bones_test`, `unarmed_humanoid_test`, renderings | resolved; ladder #55 deferred |
| A non-humanoid family needs no skeleton | `MotionRequest`, `MotionPresenter` | `motion_contract_test` (57 checks, controls), family gate, rendering | resolved for the two examples; quadruped and tracked are designs |

## Changes made

Architectural fixes (production):
1. `AttackSequence.begin` now ends an attack that an observer started while the previous attack was being interrupted (it used to overwrite that live attack, leaving both of its handles pending forever). Found by Codex in the Task 13 review (`agent-comms/review_attack_reentrancy.gd`), reproduced, fixed, regression added to `combat_presentation_lifecycle_test` (fails without the fix with the two expected messages, passes with it).
2. `CharacterRig.cover_yaw()` and `CharacterRig.halt_interaction()` give the tactical adapter public access to two things it reached for through underscore members. Behaviour is identical (the pose trace and route trace are unchanged).

Ironclad improvements:
* Catalog: `presentation/motion/`, `presentation/diagnostics/` (now also animation), `research/` and two root presentation files are mapped. Before this, editing `presentation/motion/` or `research/motion_families/` selected 70 unrelated critical tests and neither the motion-contract nor the boundary suite (verified with `changed -Changed ... -List`); now it selects the animation set including both.
* `run_tests.ps1 check` gained STALE (area path missing) and UNMAPPED (a source file no area covers) rules, with a control (a stray `presentation/zz_probe/x.gd` makes `check` fail). It was run clean afterwards.
* Smoke tier 18 to 24: boundaries, motion contract, frame driver, action handles, cleanup, rig bones (all headless, about 12 s together). `motion_contract_test` and `workbench_diagnostics_test` are FAST.
* Boundary gates A to D (production never depends on research; contract, diagnostics, families, demo and workbench never reach gameplay; diagnostics call no driving or writing method; hosts use no underscore member of the rig or presenter). Each has a self-check that its pattern matches a violation and lets legitimate code through, and each was shown to fail on a real injected violation (a diagnostic calling `tick`, the workbench preloading a unit, a production file naming `DronePresenter`, the adapter's old private reach) and to pass when it was removed. Gate D also failed against the original `0c0b8ff` code (the two leaks), which is why it passed after the fix and not before.
* `presentation_authority_test` (new, critical, not smoke: a real battle, about 22 s).
* Changed-file selection, FAST and smoke are described in the Ironclad guide.

No folder was moved. Candidates examined: `ActionHandle` and `PresentationTypes` (neutral but under `characters/presenter`) would help a future extraction and are recorded as an obstacle; moving them touches many `.uid` and resource paths and nothing needs it now.

## Presentation authority, frame ownership, rig portability, context independence, non-humanoid extensibility

* **Authority:** `presentation_authority_test` plays eight real legs (flat route, ramp, stairs, ladder, return) and compares records, fingerprints, AP, cells and accept/reject results between a 1x unobserved run and a 4x run with `PresentationMonitor` attached; presentation time really differed (13.5 s against 3.5 s) and a tampered AP, record or cell is detected. What it does not prove: it varies speed and observation, not a stalled or skipped presenter; pause is covered by the workbench tests, not by a battle. `traversal_replay_determinism_test` (features off against on) passed in the full run.
* **Frame ownership:** `presentation_frame_driver_test`, the workbench pause and step tests, and the lifecycle test pass. **Duplicate frames:** reviewed; the diagnostic contract is kept (reasoning in the guide). No consumer reads the counter except `MotionReadout`; rejecting repeats would drop legitimate input for host-defined frame ids and would not protect the humanoid path.
* **Rig portability:** `humanoid_portability_test`, `rig_bones_test`, `rig_profile_test`, `unarmed_humanoid_test` passed (both characters, armed and unarmed, the renamed-bone and incomplete-anatomy fixtures preserved). #55 is untouched and stays a Small MIRA ladder specialisation.
* **Context independence:** tactical, exploration and workbench all drive the same presenter; no host holds a second clock except two wall-clock uses (below). The tactical adapter was the only host reaching private rig state and no longer does.
* **Non-humanoid:** `motion_contract_test` passed (3D velocity survives, facing independent of travel, no skeleton, capability reporting, refused unsupported actions, handles and teardown); family gate passed.

## Verification (what was and was not run)

| Run | Result |
|---|---|
| `check` | passed: 280 scripts, 280 entries, 34 explicit-only, 100 FAST, 24 SMOKE; STALE and UNMAPPED rules proven by a control |
| `smoke` | PASS 25 (24 tests and the project parse), FAIL 0 |
| `fast -Subsystem animation` | 29 PASS (28 tests and the parse), 0 FAIL on the final tree. One earlier execution failed `pose_ownership_test` (below) |
| `changed -Since 0c0b8ff` | 73 selected, 73 PASS |
| `-ProbeFailureHandling` | three failures reported as designed (exit 7, a zero-exit script error rejected, a timeout killed); the runner behaved correctly |
| `full` | one run on the tree before two small test corrections: 245 PASS, 2 FAIL, 34 explicit-only skipped, 2605 s. The failures: `resource_references_test` (a defect in my new gate's control string, which named a path that does not exist; fixed and re-run green) and `pose_ownership_test` (intermittent, see below; green on every later run). A clean full on the final tree: see "Final state" |
| Pose trace (39 scenarios) | byte-identical (parsed JSON equal) to the Task 12 approved trace; it differs from the original Task 07 baseline by the visual changes approved in Tasks 10 and 11 |
| Route trace (853 routes) | identical to the Task 12 trace and to the original baseline |
| Captures with the real renderer (GPU) | MIRA and Small MIRA equipped, unarmed contacts, exploration actions, the workbench (diagnostics on stairs, Small MIRA ladder), tactical cover firing, the ladder sheet, the wheeled and drone examples: all inspected, in `docs/claude/images/task14/`. Nothing new looked wrong; the Small MIRA ladder shows the known #55 reach problem. The Task 12 four-tab workbench was not hand-driven interactively |
| Not run | the explicit-only batches (`ai_*`, stress, quality metrics, `prototype_1_milestone`) and the other 20+ capture scripts; a screenshot comparison does not exist |

Excluded by policy and not claimed: the 34 explicit-only scripts, and anything on GitHub (the hosted smoke job runs after the push; its result is not part of this report).

## Performance (existing probes, headless, this machine, idle load)

| Measure | Baseline (recorded) | Task 14 | Reading |
|---|---|---|---|
| Adapter `_process` per character, n=24 | 0.023 ms | 0.025 ms | within the run-to-run spread seen in the baseline (0.023 to 0.026) and the CPU state; the hot path was not changed |
| AnimationTree + modifier stack per character | 0.010 to 0.011 ms | 0.012 to 0.014 ms | same reading; scaling from 1 to 24 characters is linear |
| `MotionRequest` build | 2.0 us (Task 13) | 2.0 us | |
| Wheeled / drone present | 5.1 / 8.8 us | 5.1 / 8.7 us | |
| Humanoid direct / via bridge | 4.2 / 8.7 us | 4.1 / 8.4 us | |
| Diagnostics: monitor refresh, contact measure, stage report, rig inspection | | 15, 13, 94, 60 us per call; whole frame with diagnostics on and off 6.86 against 6.90 ms | no measurable cost on the frame; diagnostics are opt-in anyway |

A first measurement taken while another Godot process ran was about 10 to 20 percent higher; it was discarded and repeated on an idle machine. No budget is enforced: these numbers depend on the CPU and its load, and a fixed limit would fail on a busy CI runner without meaning a regression. Not measured: rig construction time, memory and allocations, a scene with many visible characters beyond the linear n=24 probe, GPU cost.

## Known issues and dispositions

| Issue | Evidence | Disposition |
|---|---|---|
| `pose_ownership_test` intermittent (undeclared `shin` in stages that cannot write it) | failed in 1 full run and 1 FAST run on the Task 14 tree; passed in six other executions (standalone twice, once under concurrent CPU load, once with the original production code, in the final FAST rerun and in the changed tier) | still open; it compares rigs sampled in the same frame against a control and looks sensitive to frame timing, not to a stage writing a bone; not reproduced on demand; it is the only unexplained failure; tracked in the Task 14 issue |
| Tactical host feeds the route speed to the locomotion feed during stairs (3.5 m/s reported, 1.0 m/s travelled; Codex probe `review_stair_speed.gd` reproduced it) | probe output | deferred: the stair pose owns the legs there and the stair visuals were tuned with it; changing it moves the approved pose trace; needs an owner decision and a render review |
| Exploration host's "still moving" window uses wall-clock time; tactical action presenter's watchdogs use wall-clock deadlines | `Time.get_ticks_msec` in both | deferred: affects only the exploration gait decay and an early end of a visual wait after a long pause (Codex probe `review_pause_deadline.gd` did not show a wrongly-settled action) |
| Small MIRA ladder (#55) | unchanged | deferred, reported separately |
| `MotionTrail` and workbench tabs need a rig; no multi-family workbench; neutral types under `characters/presenter` | | documented obstacles, not built |
| The authority test varies speed and observation only | | documented |

## Independent audit

Status: see "Codex audit" below (appended after it ran).

## Final state

See the Task 14 issue and the commit message for the final commit, the full-suite run on the final tree and the sign-off checkpoint.
