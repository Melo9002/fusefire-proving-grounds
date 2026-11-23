# ADDA for a developer who does not know AniLab's internals

You do not need to know how the rig, the stages or the solvers are built. You need a symptom, a scenario that shows it, and the two places ADDA lives:

* **ADDA - Workbench** (the window): `godot --path . res://tools/animation_workbench/pose_workbench.tscn -- --character=mira_0` (or `small_mira_0`, add `--unarmed`). Five tabs: Character, Scenario, Diagnostics, Evidence, **Why?**.
* **The command line**, for repeatable and comparable runs (details in [07-usage.md](07-usage.md), the agent procedure in [10-agent-workflow.md](10-agent-workflow.md)).

**Evidence of testing.** The Workbench operation described here is exercised by automated UI tests (`workbench_scenarios_test`, `workbench_diagnostics_test`, `adda_workflow_test`, `adda_validation_test`: they press the buttons, read the text, check state is restored). **No person other than the author has used it.** Nothing here is a usability result. What a project owner should try by hand is listed in section 3.

## 1. The words ADDA uses

| Word | Meaning |
|---|---|
| **Observation** | what the recorded numbers show |
| **Hypothesis** | what might explain it; always "NOT confirmed" and always with the test that would settle it |
| **Cause** | "unknown" until a test settles it. ADDA says so |
| **Settled** | the pose has stopped changing; a measurement taken while it is still arriving describes the transient |
| **Experiment** | something that changes state on purpose (switching a pose modifier off, a scenario run with one thing changed); it is labelled and put back |
| **Undeclared modifier** | a pose modifier that exists in the skeleton but is not in the table of stages the project declares (`PoseOwnership`) |

## 2. "My problem is..." (eight common cases)

For each: what to do in the Workbench, the command-line equivalent, what to read and what *not* to conclude.

### 2.1 A hand misses its contact
1. Scenario tab: pick the scenario (C Contacts for ladder and stairs, E Rescue and carry, A Cover and aiming). It plays and records.
2. **Why?** > *What happened?*. Look for "Right Hand target out of reach" or "target error".
3. Select it. Read *what was measured* (the error in mm, the reach margin in cm, the weight) and *possible causes (NOT confirmed)*. *Show it* marks the wrist (cyan), what was asked (yellow) and the gap (red).
4. *Inspect a body part* > "right hand" > *Which pose stage moves it? (experiment)* names the modifiers that move the hand.
5. Do **not** conclude the target is right: a target error says the hand is far from it, not that the target is where it should be.
CLI: `.\tools\adda.ps1 run -Scenario rescue ...`, `inspect -Finding F2`, `isolate -Bones "@right_hand"`.

### 2.2 A foot slides
Findings come in three kinds, easy to confuse: **slides while planted** (the ankle moves against its foothold at constant error), **is off its foothold while planted** (it stays far off, even if it does not slide), **settles late** (it starts off and closes in: normal stance onset). The first two are problems; the third is information. The stairs scenario is a treadmill (the stairs move, the character does not), so ignore world-space foot movement there. CLI: `run -Scenario contacts`, `inspect`.

### 2.3 The character intersects geometry
Only the **ladder** is measured on the skinned mesh. Before the scenario, tick *Also sample leg vertices against the ladder* in Why? (about 3.5 ms a frame, 1 ms if sampled every 4th). A finding "Right Shin intersects ladder rung 10" shows the bone, the rung and the depth in mm. **Wait until the pose has settled**: right after you jump to a height the first updates show transient overlaps that disappear. With sampling off, ADDA says it did not look ("not measured"), never "clean". CLI: `run -Scenario landing -Mesh`.

### 2.4 The animation snaps or pops
"Pose snap: N bones at once" gives the moment, the bones and the size. Read the sentence after it: *did a hand target, foothold, knee pole or the passenger jump in the same frames?* If yes, the input moved and the pose followed it. If it says "did not jump, so the pose itself changed", look at the hypotheses (an animation state change, a stage engaging) and **test one**: *Replay to this moment* then Pause and Step in the Scenario tab walks across it frame by frame. CLI: `run`, `inspect -Finding F1`, then `run -Disable <stage>` and `compare`.

### 2.5 A modifier unexpectedly changes a pose
*Inspect a body part* > choose the part > **Which pose stage moves it? (experiment)**. It pauses the pose (and puts the pause back), switches each modifier off in turn and lists who moves the part, by how many mm and degrees, and marks any `(NOT declared in PoseOwnership)`. Effects smaller than the printed noise floor are not attributed. A modifier the rig switches itself is marked "could NOT be tested". CLI: `isolate`.

### 2.6 It behaves differently with equipment
`run` the scenario armed and unarmed (`-Unarmed`), then `compare`. The comparison is labelled an experiment. A scenario that needs a weapon (tactical) refuses to run unarmed and says why (exit 2).

### 2.7 It works on one humanoid and fails on another
`run` with `-Character mira_0` and `small_mira_0`, then `compare`. Lengths are divided by each body's size ratio; metrics that depend on the frame rate are listed as incomparable instead of compared. A finding only one run could have shown is `UNVERIFIABLE`, not "new" or "resolved".

### 2.8 A test passes, but it looks wrong
A passing test means *its* assertion held. In this project a capsule test failed deliberately while a mesh test passed on the same ladder. `run` the scenario the test covers and read the findings; if ADDA finds something the test does not cover, the test's coverage is the question, not the animation. Do not change a threshold to make either side agree.

## 3. What the project owner should try by hand (not done by anyone yet)

1. Open the Workbench, play *C Contacts*, open **Why?**, press *What happened?*, select the first finding, press *Show it* and *Replay to this moment*. Is it clear what is being pointed at? Is the camera framing useful? (Automated tests cannot judge this.)
2. Read three finding texts aloud. Do they say what was measured and no more?
3. *Inspect a body part* > right hand > *Which pose stage moves it?* in the tactical scenario. Is the answer understandable without reading the source?
4. Follow section 2.4 for the ladder knee pop (scenario C, MIRA) from this page alone. Where do you get stuck?
5. Run `adda challenges`, pick CH07, and see whether the instructions in [10-agent-workflow.md](10-agent-workflow.md) are enough.
6. Look at the three images in `docs/claude/images/adda/` and say whether the markers are legible at your screen size.

## 4. If something looks wrong in ADDA itself

* Findings say **STALE** or **UNAVAILABLE**: the sample was not taken in the final-pose window or no update arrived (the simulation is paused in a way that stops skeleton updates). Step once, or run unpaused.
* `isolate` says **INCONCLUSIVE**: the pose is still moving or did not come back exactly. Hold it (pause, or choose a moment in a scenario) and run again; do not read the sizes.
* A run's `config.experiment` says **NOT HELD**: the rig kept switching that modifier back on; the experiment tested nothing.
* Two runs of the same command differ: run them with `--fixed-fps 60`; without it the rig uses real frame time (about 0.1 mm noise).
