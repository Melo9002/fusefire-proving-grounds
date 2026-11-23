# ADDA final report (Assignments 1 to 3)

Question: **does ADDA make animation debugging easier and more reliable for humans and AI coding agents?**

Short answer: **for the cases tried, yes, measurably more reliable and demonstrably quicker to localise; the evidence is the author's own and has not been independently reproduced.** Where ADDA is blind it now says so, and the challenges found nine real weaknesses that were fixed ([09](09-diagnostic-challenges.md) section 5). It is ready for the project owner's review, not yet for the claim that other people or agents find it easier.

Status words used throughout: **Implemented** (exists in code), **Verified** (a named test passes), **Demonstrated** (shown on a representative scenario), **Human-reviewed** (a person other than the author examined it), **Proposed** (not implemented).

## 1. Branch and commits

* Branch `review/claude-adda`, pushed to origin. **Not merged to `main`.** `main` is untouched (`6323afb`).
* It was cut from the unmerged `review/claude-animation` (`38d3865`). **Merge `review/claude-animation` first, then this branch.**
* Assignment 1 (measurement integrity): `0633ddc`, `1d500e7`.
* Assignment 2 (spatial observability, timelines, comparison, structured reports, Why? tab, CLI): `f900077`, `33d025c`, `e0f2636`, `d71b139`, `209b4ae`, `1dfd0dc`.
* Assignment 3 (this one): `2152835` (stage isolation, settle, challenges, foot-offset finding, experiment flags), `ec1d805` (knee-pole evidence, held-off check, exact faster vertex sampling, settle-aware capture, Why? isolation, overhead tiers), `603d715` (state-change hypothesis), `7cc2f6c` (noise floor, passenger evidence), and the final documentation commit (see `git log`).

## 2. What existed before ADDA

[02-capability-inventory.md](02-capability-inventory.md) is the full inventory. In one paragraph: `RigInspection`, `PoseStageReport` (declared ownership and live weights), `PresentationMonitor`, `ContactErrorDiagnostics`, `MotionTrail`, `BoneHighlight`, `HandContactDiagnostics`, `LadderClearance` (capsules, sampled mesh vertices, deck), the Workbench with four tabs and five scenarios, and the Ironclad tests, probes and captures. They were good but they trusted a skeleton read from anywhere (one ladder report had to be withdrawn because the skinned mesh was read outside `skeleton_updated` and returned the base pose), they had no time axis, no comparison, no machine-readable output and no shared vocabulary.

## 3. Research and requirements conclusions

[04-requirements-and-research.md](04-requirements-and-research.md): Godot 4.7.2 gives a final pose only inside `Skeleton3D.skeleton_updated` (measured by `tools/quality/skeleton_update_timing_probe.gd`; no flag can say "I am inside it"); full triangle-mesh intersection is not available cheaply and is declared `UNSUPPORTED`; headless with `--fixed-fps 60` is bit-exact, in-process runs have about 0.1 mm noise from real frame time.

## 4. Architectural decisions

* **ADR-0001 (A1):** a measurement is an envelope (kind, status, pose, space, method, limits, identity, stamp); every tool samples through one reference-counted `PoseWitness`; diagnostics are read-only, rig-only, opt-in; no extraction from FuseFire is attempted but the contract classes know only a `Skeleton3D` (plus `CharacterRig` for the identity string).
* **A2:** observation, hypothesis and cause are separate; findings have stable keys; reports are `adda.report` version 1; comparison refuses what it cannot stand behind.
* **A3, recorded here as a small ADR:**
  1. *Experiments are separate from measurements.* `StageIsolation`, `--disable` and `--set` change state on purpose, are opt-in, say so in their output (`config.experiment`), and restore. `StageIsolation` lives in `presentation/diagnostics/` and writes only `SkeletonModifier3D.active`, which it restores; it is not called by the game. The boundary tests pass with it ([boundary check](#6-tests)).
  2. *Injected faults live in `tools/adda/`, not in the rig or `presentation/`.* `ChallengeFault` is a plain modifier added by the command line; nothing in the game references it.
  3. *Report format version stays 1 with additive keys* (`config.experiment`, `carry` and `knee_poles` in rows, `plant_offset` events, `adda.isolation` v1 as a separate format). A consumer must ignore unknown keys.
  4. *A fresh pose is not a settled pose* (`PoseSettle`); captures and counts that care wait for it.
  5. *Challenges are sealed by convention only.* A solver can open `sealed/`; the protocol asks them not to and asks them to say if they did.

## 5. What was implemented (all three assignments)

| Assignment | Implemented | Verified by |
|---|---|---|
| 1 | `Measurement`, `PoseWitness`, witness-driven `LadderClearance` and `ContactErrorDiagnostics`, identity "ADDA - Workbench", the ADDA guide | `adda_measurement_integrity_test` (21), `skeleton_update_timing_probe` |
| 2 | `SessionRecorder`, `TimelineAnalysis`, `Findings`, `AddaReport`, `ReportCompare`, `FindingMarker`, `BodyParts`, the Why? tab, `adda.gd` and `adda.ps1` (`run inspect compare list`), rescue scenario, passivity and overhead probes | `adda_timeline_test`, `adda_report_compare_test` (38), `adda_workflow_test` (89), `adda_cli_test` (21) |
| 3 | `PoseSettle`; `StageIsolation` (steady, rotation-only and intermittent effects, undeclared modifiers, held-off check, noise floor); `adda isolate`, `challenges`, `score`; `--disable`, `--set`, `--fault`, `--challenge`; `ChallengeFault`, `ChallengeSet`, eight sealed challenges (two hold-outs); `plant_offset` finding; knee-pole, foot-target and passenger evidence; state-change hypothesis; exact 4x faster ladder vertex sampling; Why? "Which pose stage moves it?"; settle-aware close-up capture; ladder discrepancy and overhead-tier probes | `adda_validation_test` (47), `adda_challenge_test` (39), `adda_timeline_test` (51) |

## 6. Tests

**Run for this report** (all passed unless stated; Godot 4.7.2, headless, Ironclad `select` and direct runs):

| Test | Result |
|---|---|
| `adda_measurement_integrity_test` | 21 checks pass |
| `adda_timeline_test` | 51 checks pass (new: foot offset 4, passenger and pole 4) |
| `adda_report_compare_test` | 38 pass |
| `adda_workflow_test` | 89 pass (real systems, both bodies, armed/unarmed, mesh) |
| `adda_cli_test` | 21 pass (spawns engine processes: determinism, exit codes, passivity hash with its negative control) |
| `adda_validation_test` (new) | 47 pass, headless and rendered: settle transient and negative control, isolation positive and negative controls, coordinate agreement at three placements, lifecycle (no listener left), the Why? experiment button, exactness of the faster sampling against the original formula |
| `adda_challenge_test` (new) | 39 pass (about 100 s): six public challenges, two hold-outs, `--disable`, `--set` and its refusals, the reproduction command carries the levers |
| `ladder_mesh_clearance_test`, `workbench_scenarios_test`, `workbench_diagnostics_test` | pass |
| Ironclad `check` | catalog complete (297 scripts) |
| `changed -Since review/claude-animation` | 67 selected, **65 pass, 2 fail**, 0 skipped (731 s, run at `7cc2f6c` plus documentation; run before the hold-out challenges and `--set` checks were added, which were then run directly). The two failures are the inherited `ladder_climb_test` and `ladder_landing_test`, with the same capsule numbers as the baseline (e.g. MIRA armed up knee/thigh/shin 39/23/19 mm) |

**Inherited failures, unchanged and separate:** `ladder_climb_test` (capsule checks) and `ladder_landing_test` (capsule checks and the 30 fps hand-grip sample count of 14 against `> 15`) fail exactly as in [01-baseline-and-architecture.md](01-baseline-and-architecture.md). They are a deliberate capsule-against-mesh contract disagreement awaiting an owner decision; **no threshold was loosened and no approved trace overwritten.**

**Not run:** the full suite (the `changed` tier is the broad run); explicit render captures other than the ladder close-up and the three Why? stills; any manual play-through; any test on a second machine or GPU.

**Skips:** none in the runs above.

## 7. Performance

Per-frame CPU cost of each tier, one steady workload (a long ladder climbed at a constant rate, MIRA unarmed, 60 fps, headless so no rendering is included), median of 3 runs of 180 frames; `tools/quality/adda_overhead_tiers_probe.gd`:

| Tier | ms a frame | added |
|---|---|---|
| 0 ADDA disabled | 0.79 | |
| 1 witness only (the listener every tool shares) | 0.79 | +0.01 |
| 2 + settle watcher (walks every bone) | 0.80 | +0.01 |
| 3 contact overlays (Workbench) | 0.87 | +0.08 |
| 4 recorder (what `adda run` uses) | 0.91 | +0.12 |
| 5 recorder + leg-vertex sampling every update | 4.29 | **+3.50** |
| 5 ... every 4th update | 1.78 | +0.99 |
| 5 ... every 15th update | 1.16 | +0.37 |
| 6 ladder overlay (skins the legs every update) | 4.17 | +3.38 |
| 0 again (drift check) | 0.81 | +0.02 |

One-off costs: a `StageIsolation` of one bone takes 24 frames (about 20 ms of wall time); with `--window=150`, 1824 frames (about 1 s). Analysing a 779-row run: 146 ms (653 events); building and saving its report: 273 ms, 304 KB. Comparing two reports: 0.17 ms (A2).

**Correction of an Assignment 2 figure.** The A2 report said leg-vertex sampling costs "about 2.7 to 3 ms a frame". That probe did not include the rung-and-rail test on every sample; in steady ladder use the same sampling cost **14.3 ms a frame**. `LadderClearance.offenders` was then made exact-but-faster (one transform for all vertices and an early-out: every bar lies in the plane `z = plane_ahead`, so a vertex farther from the plane than the bar's radius cannot be inside it); it now costs **3.5 ms**, and `adda_validation_test` compares it with the original formula on the same poses and with a control that makes overlaps. The expensive operation is the skinned-mesh sample; it is optional (`-Mesh`, a checkbox) and can be sampled every Nth update.

Normal FuseFire gameplay pays nothing: nothing in the game creates any of this, and an idle skeleton carries no ADDA listener (tested).

## 8. Weaknesses and limits (remaining)

1. **Independence.** The challenges, the faults and ADDA were written by one agent. No other agent or person has attempted a challenge; the "scripted solver" proves the evidence exists, not that it is findable.
2. **No human usability result.** Automated UI tests press the buttons; nobody else has used the Workbench.
3. **Blind spots, labelled:** a persistent offset of a bone with no target and no snap (CH05); a persistent facing error (CH02) shows only as a larger existing snap; a hypothesis can name a real but coincident event (CH02); ADDA cannot say a target is wrong.
4. **Isolation** needs a held pose and a suspect bone; an intermittent fault needs `--window`; a modifier its owner switches cannot be tested this way; effects below the experiment's own residual are not attributed.
5. **Mesh sampling is ladder-only**; hands against rungs are not tested; full mesh intersection and physical collision are `UNSUPPORTED`.
6. **Thresholds** (20 mm hand, 30 mm foot, 15 mm slide, 97% of arm, the snap rule) were tuned on two bodies and a handful of scenarios. They decide what appears, not what is wrong.
7. **Replay is exact only for fixed-step runs**; in-process runs carry about 0.1 mm of real-frame-time noise.
8. **Tactical against exploration hosting is not compared**; the Workbench is one host.
9. **A committed ladder close-up still does not reproduce from its own commit** and is left as history; do not read it as a measurement.
10. **Real defects found and not fixed** (observed, cause unknown): ladder knee-pole jump per foot swing (R1), rescue contact claims out of reach (R2), cover-entry foot snap (R3). See [09-diagnostic-challenges.md](09-diagnostic-challenges.md) section 3.

## 9. Prioritised follow-ups

| P | Task | Why |
|---|---|---|
| 1 | Independent blind attempts at CH07 and CH08 by another agent (Codex) and by a person; record commands, time, misleads | the central claim is unproven without them |
| 1 | Owner review of R1 to R3: knee-pole computation in `TraversalPoseModifier` / `LadderKneePlanner`; the rescue target placement or the claim at weight 1.0; the cover-entry clip transition | these are real defects with evidence, ready to act on |
| 1 | Merge `review/claude-animation`, then `review/claude-adda` | order matters (this branch contains its commits) |
| 2 | A single-run detector for a persistent offset of an untracked bone (modifier contribution per bone against the clip-only pose) | CH05's blind spot |
| 2 | A lever for the clip transition (blend or hold the state machine) | R3's remaining hypothesis cannot be tested |
| 2 | Free-locomotion foot-lock claim and foothold | stairs and ladder have one; free walking does not, so foot slide there is unmeasured |
| 2 | Calibrate thresholds on a third body and more scenarios | they were tuned on two |
| 3 | Hands against rungs and rails on the mesh; deck mesh | currently capsule or nothing |
| 3 | `adda.report` v2 only if a consumer needs a breaking change | v1 additive keys suffice |
| 3 | Extract `Measurement`, `PoseWitness`, `PoseSettle`, `ReportCompare` as a Godot addon only when a second project needs them | no extraction is planned |

Milestones: **M1** independent validation (hold-outs, a human session) and the three R-defect reviews; **M2** untracked-bone offset detector and the clip-transition lever; **M3** free-locomotion foot-lock and a third body; **M4** extraction decision.

## 10. Final acceptance assessment

| Criterion | Implemented | Verified | Demonstrated | Human-reviewed | Verdict |
|---|---|---|---|---|---|
| One coherent diagnostic identity | yes (window title, README, guide, docs hub) | title and tab names in `workbench_scenarios_test` | yes | no | **Met** (identity is naming; not judged by others) |
| A useful interactive Workbench | yes (Why? tab, isolation button, overlays) | automated UI tests | five stills viewed by the author | no | **Partly established**: works; usefulness not judged by anyone else |
| Trustworthy, labelled measurements | yes | integrity test, passivity hash with negative control, coordinate test, exactness test | yes | no | **Met**, with the transient trap now guarded |
| Final-pose spatial inspection | yes | yes | yes (ladder bars, normals, poles, passenger) | no | **Met** |
| Practical time-based diagnostics | yes | timeline test (51) | yes on five scenarios | no | **Met**; thresholds tuned on two bodies |
| Reproducible scenarios | yes (`--fixed-fps 60`) | `adda_cli_test`: exact | yes | no | **Met** for fixed-step runs; replay exact only then |
| Machine-readable evidence | yes (`adda.report` v1, `adda.isolation` v1) | CLI and report tests | yes | no | **Met** |
| A useful AI-agent workflow | yes (procedure, commands, challenges, scoring) | scripted solver passes all eight | by one agent (the author) | no | **NOT PROVEN**: needs an independent attempt |
| Accessible human instructions | yes ([11](11-human-workflows.md)) | operation tested, not comprehension | no | no | **NOT ESTABLISHED**: needs a human reader |
| Positive tests and negative controls | yes | each new instrument has one (settle never-settled, isolation no-fault, sampling control, challenge CH06) | | | **Met** |
| Known and measured performance | yes | probes | yes | no | **Met**, with the A2 figure corrected |
| AniLab's architectural boundaries | yes | `animation_module_boundaries_test` and the changed tier | | | **Met** (`animation_module_boundaries_test` is in the changed tier and passed) |

Overall: **ready for the owner's review. Not a PASS on "agents and humans find it easier"**: it works, it is measured, it found and fixed its own weaknesses, and the independent evidence for that claim is still to be collected.

## 11. What I would do first on Monday

Read [09-diagnostic-challenges.md](09-diagnostic-challenges.md) section 3 for R1 to R3 (three defects with evidence), then give CH07 and CH08 to another agent without telling it the answers.
