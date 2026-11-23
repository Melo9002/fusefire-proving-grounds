# ADDA, Assignment 3: diagnostic challenges and what they showed

The question: **does ADDA make animation debugging easier and more reliable?** This document is the evidence, challenge by challenge, with what worked, what did not, and what was changed because of it. Status words follow [12-final-report.md](12-final-report.md): *Implemented* (in code), *Verified* (a test passes), *Demonstrated* (shown on a representative scenario), *Human-reviewed* (a person looked), *Proposed*.

**What this is not.** One investigator (Claude) wrote the faults, wrote ADDA and ran the challenges, so nothing here is an independent trial and no productivity figure is claimed. Two hold-out challenges (CH07, CH08) exist for a *different* agent or person to attempt blind (see [10-agent-workflow.md](10-agent-workflow.md)); nobody has yet.

## 1. How the challenges are built

* **Injected faults with known cause.** `ChallengeFault` (`tools/adda/challenge_fault.gd`) is a plain `SkeletonModifier3D` added to a rig's skeleton after a chosen stage. It offsets a bone, pops it on one update in N, drifts it, or turns the hips. The game, the rig and `PoseOwnership` are untouched; nothing in the game creates it. Its node name is neutral (`AuxPass1`...), so a report never says "fault".
* **Sealed answers.** `tools/adda/challenges/index.json` is what a solver may read (symptom, scenario, body). `sealed/<id>.json` holds the fault and the answer key. `adda challenges` lists symptoms, `adda run ... --challenge=<id>` injects the fault without printing it, `adda score --challenge=<id> --stage=.. --bone=.. --kind=..` checks an answer. Nothing but the solver's word keeps `sealed/` unread.
* **Controls.** Every fault challenge is run against a fault-free baseline of the same scenario and body; CH06 is a no-fault control whose correct answer is "nothing is wrong"; each isolation is repeated on the fault-free run and must name nothing.
* **A scripted solver** (`tests/adda_challenge_test.gd`, 39 checks, about a minute and a half) runs the investigator's steps for each challenge and checks the evidence is there. It proves the evidence exists, not that an agent will find it.

## 2. The six public challenges

| | Fault (ground truth) | Scenario, body | Compare with the baseline | The experiment | Located? | Misleading? | Evidence ADDA lacked |
|---|---|---|---|---|---|---|---|
| **CH01** weapon grip | right hand +50 mm, after `HandGrip`, from 3 s | tactical, MIRA armed | REGRESSED: one new finding, a 3-bone pose snap at 2.98 s ("right hand 8.1 cm... the right hand target did not jump, so the pose itself changed") | isolation of the right hand at 3.5 s: **`AuxPass1` (NOT declared) moves the hand 50.0 mm**; the baseline run names none | Yes: bone, size, modifier, "undeclared". Compare found the *onset*, the isolation the *persistent offset* | No | The weapon hand has no target (weight 0 "weapon grip"), so a constant offset has nothing to be an error against |
| **CH02** cover facing | hips turned 25 deg, after `CoverCrouch`, from 4.22 s | tactical, MIRA armed | REGRESSED on metrics only (largest snap 33.5 to 39.2 cm); **no new finding**: it joined an existing real snap | isolation of the hips at 6 s: **`AuxPass2` turns the hips 25.0 deg**, moving no hips origin | Yes, but only by asking about the hips and only because the isolation measures angles (it did not at first: see 5) | **Partly.** The snap finding offered "CoverCrouch engaged in the same row", which is true of the real defect and says nothing of the injected one | A persistent facing error is not a measurement ADDA takes unprompted |
| **CH03** knee pop | right knee +120 mm on one update in 70, after `TraversalLegIK` | landing, Small MIRA unarmed | MIXED: more snaps (44 to 51), right foot error 29.9 to 144 mm | isolation with `--window=150`: **`AuxPass3` intermittent, spikes 120.0 mm**; with one update per condition it does not claim to see it; `--disable=AuxPass3` returns the run to the baseline **exactly** (UNCHANGED) | Yes | The compare lists "RESOLVED: Right Foot slides while planted": the fault buried the baseline finding under a larger one. "Resolved" means "not in B" | A fault on a few updates is invisible to a held-pose experiment unless a window is asked for |
| **CH04** stairs creep | left foot +10 mm/s sideways, after `TraversalFoot`, from 1 s | contacts, MIRA armed | **was only a metric**: foot error 30 to 134 mm and no finding. Now a new finding, "Left Foot is off its foothold while planted (14 times)" | isolation at 4 s: **`AuxPass4` moves the foot 31.7 mm** (3 s of creep: 30 mm) and says INCONCLUSIVE because the pose keeps changing | Yes, after the change in 5 | No | none after the change |
| **CH05** head | head 67 mm off, whole run | exploration, MIRA unarmed | **UNCHANGED**: no target, no snap, no finding | isolation of the head: **`AuxPass5` moves it 67.1 mm** | Only if the solver already suspects the head | No, but ADDA is silent | A constant offset of a bone with no target is a **known blind spot**, now labelled so |
| **CH06** control | none | contacts, Small MIRA unarmed | UNCHANGED, no new finding | isolation names no undeclared modifier | Correctly "nothing is wrong" | No | |

**Portability (MIRA and Small MIRA, armed and unarmed).** The same 50 mm right-hand fault, injected with `--fault={...}` into `contacts` and isolated at 3 s, is reported as `AuxPass (NOT declared) moves the hand 50.0 mm` on all four of MIRA armed, MIRA unarmed, Small MIRA armed and Small MIRA unarmed. The challenges themselves run on MIRA armed (CH01, CH02, CH04), MIRA unarmed (CH05, CH08), Small MIRA unarmed (CH03, CH06) and Small MIRA armed (CH07).

**Steps to investigate** (tool invocations, from a clean checkout): baseline `run`, challenge `run`, `compare`, `inspect` (optional), `isolate` = 4 to 5 per fault challenge; one more for `--disable` (the controlled experiment). Time per command: 15 to 30 s headless.

**Debugging without ADDA.** No controlled comparison was run. An honest sketch for CH01: screenshots show a hand off the rifle but nothing says which modifier moved it; there are no per-bone logs; `PoseOwnership` lists the stages that *declare* a hand write, and an undeclared modifier is exactly what it cannot show. Source inspection finds it only by recognising an extra `SkeletonModifier3D`. That is an argument, not a measurement, and it is made by the person who built the faults.

## 3. Real defects investigated (ground truth unknown)

These are **not** faults I injected. For each, what ADDA says, what was tested, and what is still unknown.

### R1. The right knee pops at every foot swing on the ladder (MIRA, `contacts`)
* **Observed (Assignment 2, re-checked by dumping rows):** the knee bone moves 11 to 17 cm for one frame, ten times in a climb.
* **New evidence added in this assignment:** the recorder now keeps the rig's knee-pole and foot-target nodes on ladder rows. At the first pop (row 351) the knee goes (-0.308, 0.604, -0.177) to (-0.225, 0.650, -0.090) and back to (-0.333, 0.698, -0.163), and **the right knee pole jumps (-0.504, 0.743, -0.040) to (-0.322, 0.808, 0.110) and back in the same row**. The snap finding now says so: "the right knee pole, the point the leg solver bends the knee toward, jumped 29.6 cm in the same frames".
* **Tested:** `--disable=Traversal` removes the pops (and the whole ladder pose, so it is not specific); `--disable=TraversalLegIK` does **nothing, and ADDA says why**: the rig switched the stage back on in 438 of 780 frames (see 5), so that experiment would have been a false negative.
* **Code ownership (from the source, not from ADDA):** the pole is written by `TraversalPoseModifier` (`presentation/characters/rig/modifiers/traversal_pose_modifier.gd`, the `knee_poles[side].global_position = character_frame.to_global(plan.pole)` line) from `LadderKneePlanner.at_turn`.
* **Cause: unknown.** The input the leg solver is handed jumps in the same frame; why it jumps is not tested. No fix attempted (out of scope: no animation redesign).

### R2. Rescue: the hands claim a casualty far out of reach
* **Observed:** hand contacts claimed at weight 1.0 for about 1.5 s with the wrists 405 mm (right) and 486 mm (left) from targets that are 42 and 50 cm beyond the arm's reach (MIRA; 562 to 634 mm on Small MIRA).
* **Tested:** isolation at 4 s: `WeaponArmIK` moves the right hand 120.8 mm, `CoverCrouch` 17.6 mm and 19 deg, `HandGrip` turns it 139 deg; every smaller effect (5.9 mm, repeated across unrelated stages) is the experiment's own residual (see 5) and is not attributed. The result is INCONCLUSIVE (the pose does not come back exactly: 6.2 mm), and says so.
* **Contact acquisition and phases (events, with times):** crouch engages 0.18 s, pickup state 0.47 s, grip 0.52 s, both hand contacts acquired together at 0.85 s (weight 0.5, both out of reach), carry_move 2.53 s, crouch released 3.23 s, carry_idle 3.25 s, contacts released 12.2 s, context back to free 12.98 s.
* **Passenger attachment (new):** rows now carry the passenger's world position, its distance from the carrier's neck (162 cm at the start, about 16 cm in the middle of the carry) and the carry blend; a 12 cm jump of the passenger at 3.25 s, the same row as the state change to carry_idle, is a `target_jump` event on "passenger".
* **Tested with `--set`:** `--set=.carry_contacts_enabled=false` (an exported property of the rig) removes both "target out of reach" findings: they are about the carry contacts' claim, not about the arm solvers. (It also makes the largest snap bigger, 44 to 61 cm, which this experiment does not explain.) That localises the claim to the carry contact system; it does not say the claim is wrong.
* **Cause: unknown.** Which of "the target is placed on the casualty beyond the arm's reach" or "the claim should not be weight 1.0 when it cannot be met" is the defect is a decision for the rescue's owner.

### R3. The foot and toe jump 26 to 34 cm when cover is taken (tactical, MIRA armed)
* **Observed:** at 4.22 s, 12 bones at once (right toe 33.5 cm, right foot 26.4 cm).
* **Hypotheses ADDA offers (unconfirmed):** the animation state changed that row (`move` to `rifle_idle`, a state-change hypothesis added in this assignment because the snap finding had ignored a recorded event), and `CoverCrouch` and `Locomotion` engaged that row.
* **Tested:** `--disable=CoverCrouch` does **not** remove the snap (the largest step rises to 37.5 cm); `--disable=Locomotion` does not either. The stage-engagement hypothesis is **refuted** for the main snap; the clip-transition hypothesis is untested (there is no lever for it).
* **Cause: unknown**, narrowed.

### R4. Stairs: lateral drift or stance motion?
* In the baseline, per planted span the lateral ankle-minus-foothold change is at most 5.5 mm (left foot, first span, which also holds the 30 mm settle) and 4.5 mm (left foot, last span), 0.0 mm in the other nine stairs spans; the slide metric is 7.6 mm against the 15 mm threshold. The 30.3 mm over 0.42 s at the start is a `plant_settle` (the plan took hold before the ankle arrived): intentional stance motion, not a slide.
* **Trap found:** the stairs bench is a treadmill (the character stays at the origin, the stairs move), so a planted foothold moves about 1.4 m/s in world space. A *world-space* foot-slide measure would call every step a slide. ADDA measures the ankle against its own foothold, which is correct there, and cannot see a foothold that itself drifts.
* The injected creep (CH04) is 10 mm/s sideways; it is found as an offset (30 to 134 mm), not as a slide (each span moves under 15 mm).

## 4. The ladder mesh-sampling discrepancy

*The question:* some Workbench close-up captures show leg vertices inside rungs; the mesh-clearance test measures none. Pose freshness, fixture, timing, paused updates, or something else? The cause was not assumed.

*Evidence* (probe `tools/quality/adda_ladder_discrepancy_probe.gd`, test `adda_validation_test` section 1):

| Check | Result |
|---|---|
| Same body, same heights (1.0 to 3.0 m), four paths: test-style progressive climb, test host cold-asked, Workbench cold-asked (paused), Workbench progressive | **0 vertices on every path, every height**, MIRA unarmed and armed and Small MIRA, once the pose has settled. Pose freshness and the fixture are **not** the cause |
| Every sample's status | FRESH. The measurement was never stale |
| A pose asked for *cold* (a height jumped to), sampled each update at a fixed 60 fps | **23 vertices on update 0, 13 on update 1, 0 from update 2**; joints still move 25 to 30 mm per update until update 4 |
| The same at the engine's real frame time, headless | 6, 3, 8, 0 vertices at the same height in successive runs: the transient depends on frame time, so a fixed "wait 4 frames" lands inside it or outside it |
| The committed still `docs/claude/images/ladder55/workbench-closeup-mira-up-threequarter.png` ("32 vertices inside, right foot, rung 4..10") **re-rendered at its own commit `38d3865`** | **no red vertices**, and a different posture: [`ladder-closeup-rerendered-at-38d3865.png`](../images/adda/ladder-closeup-rerendered-at-38d3865.png). The still is not reproducible from the commit it was committed with |
| The same capture on this branch, waiting until the pose settles | none: [`ladder-closeup-settled-current.png`](../images/adda/ladder-closeup-settled-current.png) |

*Conclusion.* (1) A FRESH final pose is not a SETTLED one; the first updates after a pose is requested show a transient with real leg-in-rung overlaps. That mechanism is reproduced and is now guarded: `PoseSettle` says "still moving" or "settled", the close-up capture waits for it, and `adda_validation_test` asserts both the transient and the settled zero. (2) The *committed* still disagrees with the code at its own commit, so it is most likely a capture from an earlier working-tree state of that commit, not a measurement of its code. I cannot prove which of the two produced the picture; I can show that neither pose freshness, fixtures, nor paused updates do. The still is left in place (it is history); do not read it as a measurement of the current code.

## 5. Weaknesses the challenges exposed, and what was done

| Found by | Weakness | Change | Test |
|---|---|---|---|
| ladder discrepancy | FRESH was read as "final and settled" | `PoseSettle` | `adda_validation_test` 1 (transient, settled, never-settled control, no-update reason) |
| CH04 | a foot that ends 134 mm off its foothold produced only a metric | `plant_offset` event and finding "is off its foothold while planted" | `adda_timeline_test` (parked 80 mm, 20 mm not reported, settle not an offset, creep) |
| CH02 | isolation measured bone origins, so a pure turn of the hips was invisible | orientation effects (`turns N deg`) | `adda_validation_test` 2, `adda_challenge_test` CH02 |
| CH03 | a pop on one update in 70 cannot be seen in a held pose | `--window=N`: spike against the window's median | both tests |
| `TraversalLegIK` | `--disable` and the isolation silently "tested" a stage the rig kept switching back on | `config.experiment` says "NOT HELD ... 438 of 780 frames"; isolation says "could NOT be tested" | CLI check and manual run |
| R2 isolation | the same 5.9 mm "effect" repeated on unrelated stages | noise floor = the experiment's own restore error; smaller effects are not attributed | manual run (rescue) |
| R1 | the knee pole, the leg solver's input, was not recorded | pole and foot-target positions on ladder rows; `target_jump` on "left/right knee pole"; the snap finding cites it | `adda_timeline_test` 8 |
| R3 | the snap finding ignored a recorded `state_changed` event at the same row | state-change hypothesis | manual run |
| R2 | passenger attachment was not observable | `carry` on rows; `target_jump` on "passenger" | `adda_timeline_test` 8 |
| overhead probe | Assignment 2's "about 3 ms a frame" for leg-vertex sampling was wrong (see [12-final-report.md](12-final-report.md)): 14.3 ms in steady ladder use | `offenders()` early-out and one transform, results identical | `adda_validation_test` 7 against the original formula, plus a control |

## 6. Where ADDA did not help, stated plainly

* A constant offset of a bone that has no target and does not snap (CH05) is **invisible** unless someone asks about that bone.
* A persistent rotation (CH02) shows only as a worse snap that was already there; the cause is found by isolation, not by compare.
* ADDA cannot say a target is *wrong* (a hand holding exactly the wrong place has zero error); this is documented in every finding's "does not establish".
* The isolation needs a held pose and a suspect bone. It answers "what moves this", not "what is wrong".
* Hypotheses can still point at a real but unrelated coincidence (CH02). They are labelled unconfirmed; the discipline of testing one (R3's `--disable`) is what refuted one.

## 7. For the next investigator

Run the hold-outs blind (CH07, CH08) with only `adda challenges`, `run`, `compare`, `inspect`, `isolate` and `score`. Report how many commands it took, whether the answer scored, and whether any finding or hypothesis pushed you the wrong way.
