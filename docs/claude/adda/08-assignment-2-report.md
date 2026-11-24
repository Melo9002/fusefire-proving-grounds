# ADDA, Assignment 2: spatial observability, evidence and usability

Branch `review/claude-adda` (based on `review/claude-animation@38d3865`, unmerged; `main` untouched). Usage guide: [07-usage.md](07-usage.md). This report says what was built, what the instruments found on the real systems, what it costs, what is proved and what is not, and what Assignment 3 should stress.

## 1. Gaps that were demonstrated, and what filled them

Assignment 1 left a handoff list. Reading the code, three things were already adequate and were reused unchanged: the Workbench pause/step/scenario controls, `ContactErrorDiagnostics.measure()` (hands, feet, reach, claims), and `LadderClearance.offenders()` (bone, bar, rung, depth). What was missing, and is now built:

| Gap (demonstrated) | Built | Where |
|---|---|---|
| Every tool answered "now"; nothing could say *when* a foot slid or a wrist snapped | `SessionRecorder`: one row per frame from the pose witness (final pose), with bones, root, targets, claims, stage ownership, context and ladder state | `session_recorder.gd` |
| No events: contact acquisition/release, slide while planted, snaps, stage and state changes had to be read off by eye | `TimelineAnalysis`: events and metrics as pure functions (testable on synthetic rows) | `timeline_analysis.gd` |
| Numbers with no plain reading, and no separation of observed from guessed | `Findings`: observation / unconfirmed hypotheses (with basis and experiment) / cause `unknown`; recurrence collapsed; "not measured" said aloud | `findings.gd` |
| No machine-readable run an agent can launch, read and repeat | `adda.report` v1 + `tools/adda/adda.gd` (`run`, `inspect`, `compare`, `list`) + `tools/adda.ps1` | `adda_report.gd`, `tools/adda/` |
| No valid way to compare two runs | `ReportCompare`: body-size normalisation, frame-rate refusal, noise bands, MISSING, UNVERIFIABLE | `report_compare.gd` |
| Findings could not be selected, shown or replayed | Why? tab: list, select, **Show it** (world marker + camera), **Replay to this moment**, body-part inspector, baseline compare, export | `why_tab.gd`, `finding_marker.gd`, `body_parts.gd`, `pose_workbench.gd` |
| No rescue/carry scenario in the Workbench | scenario *E Rescue and carry* (the R/P/M/Q key calls, as scenario steps) | `workbench_scenarios.gd` |
| "Which rung?" had no environment geometry in the evidence | mesh evidence now carries the bar's own axis, radius, nearest point and surface normal (`LadderGeometry`'s cylinder; nothing invented) | `session_recorder.gd`, `findings.gd` |

The Assignment 1 `Measurement`/`PoseWitness` contract was not changed: the recorder and the mesh sampler are witness users like every other tool.

## 2. What the instruments found on the real systems

All numbers below are from runs at a fixed 60 fps (`tools/adda.ps1 run ...`, reports in `artifacts/adda/`, not committed; every one is reproducible by the command in its `config.cli`). Each is an **observation; the cause is unknown** unless stated. Nothing here was fixed (out of scope), and none of it is new in the sense of being caused by this assignment: it is what the recorder sees in code that already existed.

**Ladder, MIRA armed (scenario `contacts`).** The right knee joint (the `RightLeg` bone, "right shin" in the report) jumps 11 to 17 cm in one frame, out and back, **at every foot swing**: ten times in the climb. Dumped by hand to check the finding was not an artefact: at row 457 (scenario 7.62 s) the knee goes x -0.310, -0.214, -0.325 m and z -0.177, -0.096, -0.164 m on three consecutive frames while the planned foothold moves smoothly and the swing parameter is 0.456. The finding says "the right foothold did not jump in those frames, so the pose itself changed." It names no cause; it gives a place to look.

**Ladder landing (leg vertices sampled).** MIRA: *Left Toes vs ladder rung 9 (6 times)*, 25 vertices, deepest 21.6 mm; *Right Shin vs ladder rung 10*, 52 vertices, deepest 20.3 mm for 0.22 s (the example in the brief, produced by the instrument rather than written by hand). The finding carries the part, the rung, the environment's own bar and surface normal, the rung each foot was planted on (`feet are planted on rungs 8 and 8; the overlap is rung 10`, so the hypothesis offered is "more likely the leg's path than a foot placement", unconfirmed), and a marker you can show on the body. This is consistent with the known landing limitation recorded in Assignment 1 (transitional overlap); ADDA now says where and for how long.

**Rescue and carry (new scenario).** In the pickup (0.85 s) and again in the release (10.8 s) both hand contacts are claimed at weight 1.00 for 1.4 to 1.5 s while the wrists are far from the contact targets: MIRA 405 and 486 mm (targets 41.9 and 50.0 cm beyond the arm), Small MIRA 562 and 634 mm (57.1 and 64.4 cm beyond a 32 cm arm). The capture `docs/claude/images/adda/why-reach-mira-rescue.png` shows the carrier's hand nowhere near the yellow diamond on the casualty. Whether the targets are placed too far or the clip is not there yet at that time is **unknown**; both hypotheses are listed unconfirmed, with the experiment to separate them.

**Crouch (scenario *B exploration*).** Both knee joints jump 8.0 cm on the crouch frame and 6.5 cm on the stand frame (5.02, 7.18, 11.60, 13.68 s). The finding lists, as a hypothesis with its basis, that the `CoverCrouch` stage became engaged at the same row (300): a pose stage that engages at full strength is one candidate; ADDA does not claim it.

**Taking cover (scenario *A tactical*).** At 4.2 s the right toe and foot jump 26 to 34 cm in one frame, ten times in the run (MIRA) and eight (Small MIRA). The finding says there is no foothold or contact target in those frames to compare against, so a retarget cannot be told apart from the pose itself changing. Cause unknown.

**Stairs and ladder feet.** The left foot is 30.3 mm from the stair planner's foothold when the plan takes full hold and closes to 0.0 mm over 0.42 s (`plant_settle`, low); the right foot on the ladder is 14.6 mm off and closes in 0.20 s. Reported as "settles late", not as "slides": telling the two apart (an ankle that moves at constant error versus one converging) was a design decision driven by the first real run, where a settle was reported as a 30 mm slide.

**Experiments, run through the comparison.**

| Experiment | Result |
|---|---|
| MIRA vs Small MIRA, rescue (lengths per body ratio 1.000 / 0.695) | deficits per body ratio: left 50.8 cm to 92.8, right 41.9 to 82.2: the short body is much further out of reach of the same contact; the four reach findings persist, two snap findings resolve |
| MIRA vs Small MIRA, landing | per body ratio the small body has more reach time (0.2 s to 1.27 s left, 0.1 to 0.85 right), fewer simultaneous leg vertices inside bars (56 to 32) but more time (1.33 s to 1.72 s) |
| Armed vs unarmed MIRA, contacts | unarmed: both hands hold a "contact claim" for 12.33 s against 3.0 s armed (an unarmed hand has a relaxed-hand claim while armed hands are owned by the weapon grip); the left reach deficit falls from 3.48 cm to 0.16 cm |
| 60 vs 30 fps, MIRA contacts | snap speeds and counts and the first-held foot error are refused as `INCOMPARABLE`; slide in millimetres still compares; pose-snap findings are `UNVERIFIABLE` rather than "resolved" |

## 3. What was proved, and how

| Claim | Evidence |
|---|---|
| Recording changes no pose | `tools/quality/adda_passivity_probe.gd`: the hash of 780 final-pose samples of hips, wrists and ankles is identical with no recorder, with the recorder, and with the recorder plus leg-vertex sampling (3389129608 in all three), and a 1 mm nudge of the body changes it (negative control). In `adda_cli_test`. |
| Recording leaves nothing behind | skeleton listener count after `end_recording` equals the count before; `is_clean()` (`adda_workflow_test`) |
| Same command twice gives the same report | `adda_cli_test`: all metrics identical, findings under identical keys |
| The instruments see injected faults and not clean motion | `adda_timeline_test` (43 checks): slide 25 mm found / still foot not accused / settling foot is a settle; 8 cm jump found at 30, 60 and 120 fps / smooth fast arc, a continuous hard stop and a 5 mm step are not; paused rows carry no speed; five bones jumping at once are one moment; four recurrences are one finding; reach only while a contact claims it; no intended point means "nothing to compare", never "did not jump" |
| A body teleported 40 cm is found; an idle body is not | `adda_workflow_test` on the real rig (one pose snap of about 40 cm moving the root and >= 10 bones) |
| Comparison refuses what it cannot stand behind | `adda_report_compare_test` (38 checks) and the CLI test (`--fail-on=regression` exits 1 on a regression, 0 on an improvement) |
| Findings never claim a cause | every finding on every real run in `adda_workflow_test` has `cause: "unknown"`, hypotheses `unconfirmed` with an experiment, and the kinds and limits of its measurement |
| Works for MIRA and Small MIRA, armed and unarmed | the workflow test records and analyses contacts (both bodies, armed/unarmed, mesh sampling) and rescue (armed MIRA, unarmed Small MIRA); the CLI test runs armed, unarmed and Small MIRA; the unsupported combination (unarmed tactical) exits 2 with its reason |

### Defects the tests found in ADDA itself (all fixed)

* The first snap test (a speed ratio against neighbours) missed an 8 cm jump on a fast arc: rewritten as a velocity departure plus a 4 cm minimum; the next run flagged ordinary heel-strike kinks, so the 4 cm floor was added with a control for a continuous hard stop.
* Retarget attribution used any target within two rows and called a swing trajectory a "retarget": now uses the same departure test, and says "nothing to compare against" where no target exists (it had said "did not jump" for bodies with no foothold at all).
* The report said `mesh_sampling: false` for a run that sampled the mesh (stop turned the flag off): found by the workflow test.
* Findings could not be matched between runs (their keys moved with the number of bones): keys are now kind, part and ordinal; a mesh finding is keyed by the leg, not the exact part; a finding only one run could have shown is `UNVERIFIABLE`.
* The first replay erased the recording it came from.

## 4. Cost

From `tools/quality/adda_overhead_probe.gd` (fixed 60 fps, headless, so frame times are CPU only):

| Item | Cost |
|---|---|
| recorder | +0.10 ms a frame (0.45 to 0.54 ms) |
| leg-vertex sampler (optional) | ~~+2.67 ms a frame on a climb~~ **corrected in Assignment 3: +14.3 ms a frame in steady ladder use** (that probe did not include the rung-and-rail test on every sample); after the exact speed-up, +3.5 ms ([12-final-report.md](12-final-report.md) section 7) |
| analysis of a 13 s run (779 rows) | 138 ms |
| report build (analysis, findings, serialisation) | about 255 ms |
| report file | about 267 KB summary for a busy ladder run; 1.6 MB with every row |
| memory | 779 rows kept for 13 s; the ring holds 7200 (two minutes at 60 fps) |
| compare | 0.17 ms |

The recorder is created only when a scenario starts or the tab asks, and stopped when the scenario ends. The game never creates it.

## 5. Limitations and honest edges

* **Replay is exact only for fixed-step runs.** *Replay to this moment* steps the scenario at the recorded frame step, paused; a run recorded at a variable frame rate returns to the same scenario time, not necessarily the same pose.
* **In-process runs are not bit-reproducible.** The rig's own frame time is the engine's real delta, so two runs in one process agree only to about 0.1 mm; the headless fixed-fps command line is exact. The workflow test says so and tests the exact claim through processes.
* **Snaps are frame-rate sensitive** by construction (a 4 cm excess over what the neighbouring frames predict); the metrics are tagged and refused across frame rates, and a hard but continuous stop is not reported.
* **A snap is a measurement of position, not a judgement.** Some are animation clip content; ADDA does not know which.
* **Sliding is measured only against a plan** (stairs, ladder). Free locomotion makes no support claim, so a foot sliding on flat ground is not detected, and ADDA says nothing about it.
* **Mesh sampling is ladder-only** (the leg surface against rungs and rails). Full mesh intersection and physical collision remain `UNSUPPORTED`. Hands against rungs are not tested ("a hand on a bar is the contact").
* **Only the contacts the rig publishes** (grip modifier, stairs, ladder) are known. A carry contact on the casualty is the rig's hand target; the casualty's own surface normal is not available and none is invented.
* **Camera framing** is a single side-ish view from the camera's current side; close-up presets from Assignment 1 are unchanged. I viewed the three captures (`docs/claude/images/adda/`); I did not exercise every control by hand, and headless success does not establish visual correctness.
* **Thresholds are conventions**, stated in each finding; they were set on MIRA and Small MIRA and have not been tuned on other bodies.
* **Selection is by finding and by body part.** A bone or limb is chosen in the part picker (live) or arrives with a finding (with its target, or the bar and rung); there is no free pick of an arbitrary target or surface in the 3D view, and support state is shown in the finding facts and the rows, not as a live overlay.
* **Experiments are character, weapon state, frame rate and code.** There is no generic "set this animation parameter" override (for example a ladder pitch or a modifier weight) on the command line; that is a recommendation below.
* **Tactical against exploration hosting is not compared.** Both are synthetic contexts in the Workbench (different scenarios, so `compare` refuses them). The recorder needs only a rig, so a host-driven run could be compared; none was built.
* Rows are per rendered frame (the last update of a frame): sub-frame behaviour inside one engine frame is not visible.

## 6. Verification run

```powershell
.\tools\run_tests.ps1 check
.\tools\run_tests.ps1 select -Test adda_timeline_test,adda_report_compare_test,adda_workflow_test,adda_cli_test,adda_measurement_integrity_test,workbench_scenarios_test,workbench_diagnostics_test,workbench_landing_test
.\tools\run_tests.ps1 changed -Since review/claude-animation
```

Results of the final run on this branch:

| Run | Result |
|---|---|
| `check` | catalog complete and consistent (294 scripts) |
| the five ADDA tests, three Workbench tests and the module boundary test | all pass (`adda_timeline_test` 43 checks, `adda_report_compare_test` 38, `adda_workflow_test` 89, `adda_cli_test` 21, `adda_measurement_integrity_test` 21) |
| `changed -Since review/claude-animation` | 65 selected, **64 pass, 2 fail**: `ladder_climb_test` (knee, thigh and shin through a rung: 0.039 / 0.023 / 0.019 m) and `ladder_landing_test` (leg through rungs 122 mm on the way down, deck overlap 59 to 64 mm, and the 30 fps hand-grip sample count of 14) |

Both failures are the inherited, deliberate ones recorded in `01-baseline-and-architecture.md` with the same numbers; no threshold was loosened and no test was weakened. Nothing that passed in Assignment 1 fails now.

`workbench_scenarios_test` was updated for an intentional design change: the panel now has five tabs (the contract was "four") and the test lists them in order; the Evidence tab stayed at index 3.

## 7. Recommendations for Assignment 3 (stress, usefulness, architecture)

1. **Use it on a defect nobody has diagnosed yet** and count the experiments it took; the three candidates above (the ladder knee, the rescue contacts, the crouch frame) each name a first experiment.
2. **Test the comparison on a real code change**: make a deliberate animation change on a branch, run `run` before and after, and check the verdict agrees with what the capture shows.
3. **Try to break the instruments:** other bodies (the roster concept lists bigger and embedded-weapon frames), 30/120 fps, scenarios with a root that moves (a unit-hosted run, not the Workbench where the root stays at the origin), a rig whose bones do not map.
4. **Decide the thresholds with the animator**: the 4 cm snap floor, 20 mm hand line and 15 mm slide were set for these two bodies; make them per-rig data if they should vary.
5. **Parameter experiments:** a `--set <rig path>=<value>` override on `run` (recorded in `config`) so an agent can vary a modifier or ladder parameter without editing code, and a host-driven run for the tactical-versus-exploration comparison.
6. **Extend the evidence, not the UI**: a free-locomotion foot-lock claim (so foot sliding on flat ground is measurable), an environment-supplied surface for the casualty and for stairs (a normal and a contact patch), and the same recorder driven by a tactical-hosted replay (it only needs a rig).
7. **Architecture check**: `presentation/diagnostics` now holds the recorder, analysis, findings, report and comparison, all free of `tools/`, `CharacterRig` internals beyond the bones and contact data it already read. Only `ContactErrorDiagnostics.measure`, `LadderClearance`, `PoseStageReport` and the ladder/stairs plan objects are FuseFire-specific inputs; `TimelineAnalysis`, `Findings`, `ReportCompare` and the report format take plain rows and are the natural first extraction candidates (still not done).
8. Known loose ends: `HandContactDiagnostics`, `BoneHighlight` and `MotionTrail` still do not emit `Measurement` envelopes; saved camera views per finding; a timeline *view* (events are in the report and the tab lists findings, but there is no scrubbing strip).
