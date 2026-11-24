# ADDA — Workbench (the animation workbench)

**ADDA** (AniLab Diagnostic & Debugging Assistant) is the name of AniLab's diagnostic suite: the read-only tools in `presentation/diagnostics/`, this workbench, and the measurement contract (`Measurement`, `PoseWitness`) that says what every reading is and whether it may be trusted. This scene is ADDA's Workbench. Its paths, scene name, command-line arguments, scenarios and tests keep their old names. It opens on the **Start** tab: three buttons (watch, find what went wrong, change how she moves). Read [`docs/claude/adda/`](../../docs/claude/adda/) for the inventory, the measurement contract and the architecture decision.

Every number the workbench shows is read inside `skeleton_updated` and stamped; a reading that is stale, unsupported or could not be taken says so instead of showing 0. A *vertex* count is not a mesh intersection and a *support claim* is not physical support (see the contract).

`pose_workbench.tscn` is a **host** of the shared character stack, like the tactical adapter and the exploration host, built for inspection: it drives a `CharacterRig` and its `CharacterPresenter` exactly as the game does (presenter tick, action stage, weapon pose), with no tactical unit, match or mission. Architecture: [`docs/animation.md`](../../docs/animation.md).

**Documentation.** Everything about ADDA (what it measures and does not, how to investigate a problem as a person or as a coding agent, the diagnostic challenges, performance and limitations) starts at [`docs/claude/adda/README.md`](../../docs/claude/adda/README.md). The command-line interface is `tools/adda.ps1`.

## Quick start

Open `tools/animation_workbench/pose_workbench.tscn` in Godot and press F6, or from a shell:

```powershell
godot --path . res://tools/animation_workbench/pose_workbench.tscn -- --character=small_mira_0 --unarmed --scenario=contacts
```

| Argument | Meaning |
|---|---|
| `--character=<key>` | a key of `CHARACTER_RIGS` in `pose_workbench.gd` (`mira_0`, `small_mira_0`) |
| `--unarmed` | build the character without its weapon |
| `--scenario=<id>` | start a scenario on launch: `tactical`, `exploration`, `contacts`, `landing`, `rescue` |
| `--tab=<name or number>` | open on a tab: `Start`, `Scenario`, `Why?`, `Tune`, `Diagnostics`, `Character`, `Evidence` |
| `--side-view`, `--auto-sequence` | as before |

The **Evidence** tab prints the exact command for the current configuration; its JSON report now carries an `adda` block of measurement records (kind, status, pose, space, what each does not establish).

## The panel: seven tabs

The panel is docked to the right edge, full height, and the 3D view is shifted so the character stays centred in the free part of the window. Compact tables use a 14-point minimum and the panel can occupy up to 44% of the viewport to improve readability at 1280×720. **F1** hides or shows it. (The old long key list is no longer drawn over the viewport; it is in *Scenario > Keyboard shortcuts*. No shortcut changed; F1 is new.)

| Tab | Question | What it holds |
|---|---|---|
| **Start** | Where do I begin? | one button per scenario; **Report this moment** (F2 from anywhere): pause, write what looks wrong, and it saves a folder in `adda_reports/` for a coding agent (note, scenario, time and frame, character and equipment, revision, what was on screen, the drafts in use, ADDA's observations near the moment, a screenshot, how to reproduce it; `moment_report.gd`); "What went wrong in that run?"; "Open the settings and clips"; the words ADDA uses |
| **Character** | What am I inspecting? | rig identity and body proportions; semantic roles and the bones they resolved to (required `*` and optional); capabilities with the resolver's reason (supported, fallback, unsupported, not implemented); degraded stages; equipment state; a character and armed/unarmed switch; a compatibility check |
| **Scenario** | What am I asking it to do? | scenario presets with play, pause, single-frame step, reset, repeat; then every manual control that existed before (locomotion, turns, cover and authorised attack, ladder, stairs, path corridor, camera, slow motion) in folding sections |
| **Tune** | How do I change how she moves, without changing the game by accident? | the motion profiles (cover, walking, ladders, stairs, weapon hold) as sliders with their units: a few **basic** settings per profile, the rest behind *Show advanced settings* (a search finds any). A change is an **experiment**: it shows at once and is listed against the game's value. *Keep as draft* stores it in `art/characters/<id>/tuning/drafts/` (not committed; only the Workbench window reads drafts, the `adda` command line only with `-Drafts`). *Back to game values* undoes it. **Apply to game** (two clicks, after the list of changes) is the one action that writes where the game reads: `tuning/<profile>.tres`, or the profile's own `.tres`; CharacterRig loads it when it is built. *Edit in Godot* opens the draft in the Godot editor's Inspector; a save there shows up live. **Animation clips** (generated by code): *Edit this clip in Godot* copies the clip into `drafts/clips.tres` and opens `drafts/clip_editor.tscn` (her model, an AnimationPlayer on its skeleton) on it; a save there plays here at once; *Apply this clip to the game* copies it to `tuning/clips.tres` (the controller's existing saved-clip rule). Only the base clip is edited there: IK, crouch, ladder and weapon stages still apply on top. The editor side is the `addons/adda_bridge` plugin (enabled in `project.godot`; `tools/animation_workbench/editor_bridge.gd`); with no editor open, the button starts one |
| **Diagnostics** | What is the animation system doing? | live presentation state; the measured contacts; a bounded event history; overlay switches; the pose stages in execution order with declared writes and live weights; "why is this bone moving" |
| **Evidence** | How do I reproduce and show it? | screenshot, JSON report, the relaunch command |
| **Why?** | Why is my robot doing that? | ADDA's recording of the scenario turned into findings in plain words (what was measured, possible causes marked unconfirmed, cause unknown), each line starting with when it happened and which body part; *Go there* replays to the finding's worst frame, pauses and marks it; *Mark it again* re-marks it on the current pose; a body-part inspector, compare with a saved baseline, export the report an agent gets. See [`docs/claude/adda/07-usage.md`](../../docs/claude/adda/07-usage.md) |

### Scenarios

Each preset is data in `workbench_scenarios.gd`: timed steps calling the workbench's public controls. They compose existing capabilities; none sets up a match.

| Id | Shows | Needs | Context |
|---|---|---|---|
| `tactical` | move, turn while moving, low cover, aim at an authorised target, fire, recover | a weapon | **synthetic** tactical context (a wall and a target position); cover side, posture and shot choice use the production `CoverEdgeSelector` and `CoverPostureProfile` |
| `exploration` | walk, turn, crouch, stand, gesture, nod, inspect, a reaction that interrupts a gesture | nothing (armed or unarmed) | the shared presenter's public API, as `ExplorationCharacterHost` uses it; no tactical state |
| `contacts` | a 12-tread stair, then a 4 m ladder shown from a three-quarter inspection camera, interrupted mid-climb; contact diagnostics switch on | nothing | the workbench supplies the progress the game would; planner, leg IK, ladder solver and hand contacts are the production ones |
| `landing` | the supported ladder transfer on a 3 m ladder: a deck with posts and a deck whose ladder rails run on, each climbed and entered in reverse, then a deck with nothing to hold and a lip too far for the arm (both must stay on the fallback). Uses `LandingFixtures`; the Diagnostics tab shows the landing status and the measured deck and bar clearances. | none (unarmed works) | **synthetic** deck; the pose is the production solver and rig, the landing is the same `LadderLanding` the sandbox supplies |
| `rescue` | pick a casualty up from the floor, carry it walking, stop, set it down (the R, P, M and Q key calls, as steps); contact diagnostics switch on | nothing (armed or unarmed) | the workbench supplies the passenger a metre ahead, as the game supplies the rescued actor's place; the lift, carry contacts and release are the rig's |

An unsupported combination is shown disabled with the reason (for example `tactical` on an unarmed character). **Pause** stops the scenario and the character together (the animation tree runs in manual mode and the presenter is not ticked); **Step frame** advances both by exactly one step (1/60 s). **Reset** ends every bench, hold and posture request the workbench made and squares the body; it works while paused and mid-scenario. Starting a scenario resets first.

### Diagnostics, and what each one can and cannot tell you

All are read-only, rig-only tools in `presentation/diagnostics/` (usable from any host), created when switched on and freed when switched off.

* **Live presentation and events** (`PresentationMonitor`): runtime values from the presenter's public accessors (state and the one before, speed, facing, posture, readiness, hold and its rank, which contexts own the body). The history says *what changed and when* on the presenter's own clock; it never says *why*, except through an `ActionHandle` outcome (COMPLETED, CANCELLED, INTERRUPTED, SKIPPED), which the presenter itself reports.
* **Pose stages** (`PoseStageReport`): the stages in the order the skeleton really runs them, checked against `PoseOwnership.STAGE_ORDER`, with each stage's DECLARED writes and its live weight. *Declared ownership and live weights are not a measured bone change.* To measure what a stage really writes, use the isolation method in `tests/pose_ownership_test.gd`. Highlighting a stage or a bone marks the bones on the body.
* **Contact error** (`ContactErrorDiagnostics`): for each hand, the intended target (diamond), the final wrist (cross), the error between them, the shoulder's reach against the arm's length and the margin; for each foot, the stair or ladder plan against the final ankle. It samples **only** in the skeleton's `skeleton_updated` callback, after every modifier has run. A reading taken anywhere else in the frame is a different pose (the test measures it up to several centimetres off), which is why there is no other entry point. A contact farther than 97% of the arm's length from the shoulder is called UNREACHABLE: that fraction is a display convention shared with `hand_contact_test`, not a limit the rig enforces. Nothing here fixes an unreachable contact. It does not measure mesh contact or penetration (no surfaces exist).
* **Weapon-grip contacts** (`H`, the existing `HandContactDiagnostics`): palms, wrists and grips against the weapon's profile; needs a weapon.
* **Root trail** (`MotionTrail`): where the root went, coloured by speed. Position-driven benches (ladder, stairs) can be scrubbed; stateful behaviour (gestures, holds, attacks) is replayed by resetting and playing the scenario again, because rewinding it would need the presenter's state, which the workbench does not own.

## Keys

Unchanged except F1: `1`-`6` idle/move/aim/shoot/hit/defeat, arrows, `T`, `[` `]`, `I`, `C`, `Space`, `7`-`0`, `V B N L`, `F`, `R P M E Q K`, `O , . Y`, `H J G Z X`, `Esc`. The full list is in *Scenario > Keyboard shortcuts*.

## Introducing and inspecting a new humanoid

1. Import the model, make a `RigProfile` (a `BoneMap` of Godot's humanoid roles, anatomy, sockets): `art/characters/<name>/<name>_rig_profile.tres`. See *How to add or configure a humanoid rig* in `docs/animation.md`.
2. Make `<name>_rig.tscn` (a `CharacterRig` with the model, profile, optional weapon and handling) and add a key to `CHARACTER_RIGS` in `pose_workbench.gd`.
3. Launch with `--character=<key>`. **Character tab**: required roles must show a bone; every capability you expect must be `SUPPORTED` or a stated `FALLBACK`. If a skeleton or profile does not fit, *Compatibility check* resolves a profile against the skeleton without building a rig and explains what to fix (`E_BONE_NOT_FOUND [LeftHand]: mapped to 'X', which this skeleton does not have -> correct the BoneMap entry`). *Break the mapping* shows what an error looks like.
4. **Scenario tab**: run `exploration` and `contacts` armed and unarmed; the stair and ladder tell you whether the body's proportions work. **Diagnostics** shows any contact the arm cannot reach.
5. A new animation or capability: add it as `docs/animation.md` describes, then watch it in **Diagnostics** (the state and history, the stage that should engage, the hold and its outcome).

## A diagnosis you can reproduce (issue 55)

*Does Small MIRA reach the ladder?* Launch with `--character=small_mira_0 --unarmed --scenario=contacts --tab=2`, and let the ladder start (about 5.5 s in; pause there). *Contact measurement* shows each hand's `target->wrist` error, its reach against the arm length and, when the rung is beyond the arm, `UNREACHABLE by n cm`; the green reach line turns red past the arm's length. On MIRA the same scenario flags a few samples, on Small MIRA about half of them. It is the ladder solver's rung windows, authored for MIRA's arms; the diagnostic shows it and does not change it (tracked as #55). `Record contacts` then `Stop and summarise` counts the unreachable frames and the worst deficit.

## Known limits

* Switching character reloads the scene (the one clean reset), so any non-default workbench state is lost.
* The status line and the panel are laid out in canvas units; text is 14 pt or larger in canvas units, so it scales down with the window; 1280x720 is comfortable, smaller is not recommended.
* The root trail follows the root; the ladder and stair benches slide the world past a fixed character, so their trail is a point (their contact readouts are the useful measurement). While the workbench is paused, the trail records neither time nor stationary frames; stepping records exactly one sample at the stepped simulation delta.
* The monitor cannot see a state set by bypassing the controller's signal (the live snapshot would show it; the history would not).
