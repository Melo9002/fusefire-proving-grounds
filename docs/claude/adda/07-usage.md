# ADDA usage: investigating an animation problem

ADDA answers "why is my robot doing that?" with measurements, and says plainly what it does **not** know. There are two ways in, and they read the same data: the **Why? tab** in ADDA — Workbench (for a person) and the **command line** (for a coding agent or CI). Both produce the same `adda.report` JSON.

## 1. Vocabulary

| Word | Meaning |
|---|---|
| **Observation** | What the recorded numbers show: "Right Hand target is 41.9 cm beyond the arm's reach for 1.47 s". Measured, with its frames, values, method and what that method does not establish. |
| **Hypothesis** | What might explain it. Always `unconfirmed`, always with the *basis* it rests on and an *experiment* that would test it. |
| **Cause** | `unknown` unless something proves it. ADDA never fills this in on its own. |
| **Finding** | One observation with its hypotheses, subject (the bone, limb, target or bar it is about), evidence kinds and how to reproduce it. A defect that repeats is **one** finding listing every occurrence. |
| **Recording** | One row per rendered frame of what the skeleton really showed, read only inside `skeleton_updated` (the final pose). It changes nothing: proved bit for bit (below). |

## 2. For a person: the Why? tab

1. Launch the workbench: `godot --path . res://tools/animation_workbench/pose_workbench.tscn -- --character=small_mira_0 --unarmed` (or open the scene in the editor). Pick a scenario in **Scenario** (stairs and ladder: *C Contacts*; ladder landing: *D*; rescue and carry: *E*; cover and aiming: *A*; gestures and crouch: *B*). Playing a scenario records it automatically.
2. Open **Why?** and press **What happened?**. You get one sentence ("12 findings: 5 high, 4 medium, 3 low. These are measurements; the causes are unknown unless a finding says otherwise.") and the first eight findings in plain words, worst first. *Show all* lists the rest.
3. Pick a finding. You see **what was measured**, **possible causes (NOT confirmed)**, and **"Cause: unknown until one of these is tested."** *Technical detail of the selected finding* (folded) adds the facts, the measurement method, what it does not establish and the recorded frames.
4. **Show it** marks the finding on the body (cyan cross = where the pose put it, yellow diamond = what was asked, red line = the error, magenta = the bones, orange = the environment's own bar, green = its surface normal) and moves the camera to it. **Replay to this moment** restarts the scenario and pauses at the finding's time (one step per frame; a moment 5 s in takes about 5 s to reach); **Pause / Step** in the Scenario tab then walk through it. **Copy reproduction** puts the relaunch command on the clipboard.
5. **Inspect a body part** (folded): choose "right shin" and read its live position (final pose, the character's frame), speed, and which stages are declared to write it and are engaged now. The bones are highlighted.
6. **Compare with an earlier run** (folded): *Save as baseline*, change something, run the same scenario again, *Compare with baseline*: improved, regressed, unchanged, and what cannot validly be compared (see 4).
7. **Hand it to someone**: *Export report (JSON)* writes the report an agent would get; *Copy agent command* copies the headless command that reproduces it.

Tick *Also sample leg vertices against the ladder* before a ladder scenario if you want to know whether legs cross rungs (about 3.5 ms a frame; 1 ms if sampled every 4th update). With it off, ADDA says it did not look.

## 3. For an agent: the command line

```powershell
.\tools\adda.ps1 list
.\tools\adda.ps1 run -Scenario landing -Character small_mira_0 -Mesh -Out artifacts/adda/small-landing.json
.\tools\adda.ps1 inspect -Report artifacts/adda/small-landing.json -Finding F1
.\tools\adda.ps1 inspect -Report artifacts/adda/small-landing.json -Row 212
.\tools\adda.ps1 compare -A artifacts/adda/before.json -B artifacts/adda/after.json -FailOn regression
```

(The wrapper needs `godot_console` on `PATH` or `-Godot <path>`. Raw form: `godot_console --headless --fixed-fps 60 --path . --script res://tools/adda/adda.gd -- run --scenario=landing ...`. Run at a **fixed frame rate**: with `--fixed-fps 60` two runs of the same command are identical to the last digit; without it the rig's own frame time varies.)

| Command | Does |
|---|---|
| `run` | plays a scenario headlessly with the recorder on, writes the report, prints the headline and the ten worst findings. Options: `-Character mira_0\|small_mira_0`, `-Unarmed`, `-Mesh` (leg-vertex sampling), `-Detail full` (every recorded row), `-Window n0-n1` (rows to include), `-Fps`, `-FailOn high\|medium` |
| `inspect` | one finding in full (`-Finding F3` or its stable key), or one recorded row (`-Row 212`); with neither, every finding |
| `compare` | two reports: verdict and every metric, with `-FailOn regression` for a gate |
| `list` | scenarios, characters, the report format |
| `isolate` | an **experiment**: play a scenario to `-At <seconds>`, hold it, switch each pose modifier off in turn and report which move `-Bones "@right_hand,..."` (and which are not declared in `PoseOwnership`). `-Window n` samples n updates per condition to see a fault that fires on some updates only |
| `challenges`, `score` | the diagnostic challenges (symptoms only) and a scorer for an answer; see [10-agent-workflow.md](10-agent-workflow.md) |

`run` also takes experiment levers, recorded in `config.experiment`: `-Disable <modifier>` (a modifier the rig keeps switching back on is reported `NOT HELD`), `-Set "<NodePath>.<property>=<value>"`, `-Fault <json>` and `-Challenge <id>`. The investigation procedure for agents and the diagnostic challenges are in documents 09 to 12; start at [README.md](README.md).

Exit codes: `0` done, `1` a `-FailOn` condition held, `2` a usage problem or a configuration that cannot run (for example `tactical` unarmed: "needs a weapon", no report is written).

### The investigation loop

1. **Reproduce:** `run` the scenario (the report's `config.cli` is the command that repeats it).
2. **Find:** read `summary.headline` and `findings` (worst first); `worst_frames` says which rows to look at.
3. **Inspect:** `inspect -Finding F2` prints the observation, the unconfirmed hypotheses, what the method does not establish, the subject and the recorded rows around the worst frame.
4. **Hypothesise:** each hypothesis names its `basis` and an `experiment`.
5. **Experiment:** change one thing (`-Unarmed`, `-Character`, `-Fps`, or your code) and `run` again.
6. **Compare:** `compare -A before.json -B after.json`. Read the verdict, then which metrics improved or regressed, which are `INCOMPARABLE` and why, and which findings are new, resolved or `UNVERIFIABLE`.

### Report format (`adda.report`, version 1)

Top-level keys: `format`, `version`, `config`, `summary`, `findings`, `worst_frames`, `events`, `markers`, `samples`, `instruments`, `limitations`, `meta`.

* `config`: `scenario`, `character`, `identity`, `armed`, `body_ratio`, `frame_dt_s`, `fps`, `rows`, `duration_s`, `mesh_sampling`, `engine`, `revision{commit, branch, dirty}`, `command`, `cli`.
* `summary`: `headline`, `findings{high,medium,low,info}`, `counts` (events by kind), `metrics` (`value`, `unit`, `better`, `tags`, `noise`, `label`: what a comparison uses).
* each finding: `key` (stable across runs: kind, part, ordinal), `id` (F1.. for this report), `severity`, `title`, `observation{text, facts, frames{n0,n1,worst_n,t0,t1,st0}}`, `hypotheses[{text,status:"unconfirmed",basis,experiment}]`, `cause:"unknown"`, `subject{kind,text,side,part,bones[],surface}`, `evidence{kinds,method,does_not_establish}`, `reproduce`.
* `samples.rows`: the recorded rows. Positions are `[x, y, z]` metres; **bones** are in the character's frame (x left, y up, z forward), **root, targets, wrists and ankles** are world. Each row: `n`, `t`, `dt`, `st` (scenario time), `state`, `context` (free, ladder, stairs, carry), `stages` (engaged pose stages), `root`, `yaw`, `bones`, `hands`, `feet`, and `ladder` / `mesh` when present.
* `instruments`: for every measurement kind, whether it was `TAKEN`, `NOT TAKEN` or `UNSUPPORTED` (full mesh intersection and physical collision), with what it does and does not establish.

A measurement that could not be taken is a finding of kind `not_measured`, never a silent zero. `inspect` of a row that is not in `samples` says so and tells you how to include it.

## 4. Comparing runs: what is and is not valid

`compare` refuses to print a number it cannot stand behind:

| Situation | Result |
|---|---|
| different scenario | `NOT COMPARABLE`: nothing is compared |
| different report version / not an ADDA report | refused |
| different body size (MIRA vs Small MIRA) | lengths are divided by each body's `body_ratio`, and the note says so |
| different frame rate | metrics tagged `frame_rate` (snap speeds, snap counts, the first held foot error) are `INCOMPARABLE`; millimetres, centimetres and seconds still compare |
| armed vs unarmed | compared, noted as an experiment |
| metric one run did not take | `MISSING`, never zero |
| change inside the metric's noise | `UNCHANGED` |
| a finding only one run could have shown (no leg-vertex sampling, another frame step) | `UNVERIFIABLE`, never "resolved" or "new" |
| a new high or medium finding | a regression even if every metric is equal |

## 5. What ADDA can and cannot say

* It reports **observations** about recorded final-pose numbers. A *support claim* is the animation system's claim, not physical support; a *sampled vertex* count is not a mesh intersection; a *target error* does not say the target is right.
* The thresholds that decide what is reported (20 mm hand, 30 mm foot, 15 mm slide, 97% of the arm, a snap = a velocity that departs from its neighbouring frames' by more than 0.5x plus 1 m/s *and* at least 4 cm beyond them) are in the findings' `evidence.method` and in `TimelineAnalysis`. They decide what appears, not what is wrong.
* A finding with no grounded hypothesis says "none that the measurements support. Cause: unknown."
* Full mesh intersection and physical collision are not measured (`UNSUPPORTED`).

## 6. Where things are

| Piece | File |
|---|---|
| recorder | `presentation/diagnostics/session_recorder.gd` |
| events and metrics | `presentation/diagnostics/timeline_analysis.gd` |
| findings (observation / hypothesis / cause unknown) | `presentation/diagnostics/findings.gd` |
| report build, save, load | `presentation/diagnostics/adda_report.gd` |
| comparison | `presentation/diagnostics/report_compare.gd` |
| in-world marker | `presentation/diagnostics/finding_marker.gd` |
| plain names for bones | `presentation/diagnostics/body_parts.gd` |
| Why? tab | `tools/animation_workbench/ui/why_tab.gd` |
| command line | `tools/adda/adda.gd`, `tools/adda.ps1` |
| tests | `adda_timeline_test`, `adda_report_compare_test`, `adda_workflow_test`, `adda_cli_test` (+ `adda_measurement_integrity_test`) |
| probes | `tools/quality/adda_passivity_probe.gd`, `adda_overhead_probe.gd` |
| captures (explicit) | `tests/adda_why_capture.gd` |
