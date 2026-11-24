# Independent evaluation: first outside use of ADDA

Up to this point ADDA had been written, tested and judged by one agent (its author). This is the first record of anyone else using it. Two reports were brought back by the project owner (Pedro), from an AI assistant he asked for help. The model and product were not stated; the reports are quoted from what he relayed.

**What this is and is not.** It is one other agent's attempt: one blind challenge (CH07) through the command line, plus two GUI passes in the Workbench. It is not a multi-agent validation, not a usability study with people, and CH08 has not been attempted. Statements below are marked **verified** (I reproduced them in the code or by running ADDA), **reported** (the evaluator's account, not reproduced by me) or **fixed**.

## 1. Blind challenge CH07

| | |
|---|---|
| Answer submitted | stage `AuxPass7`, bone `@left_elbow`, kind `offset` |
| Score | CORRECT on all three fields (`adda score`) |
| What it read first | the public agent and human workflows (`10`, `11`); it did not open `09`, the sealed folder, the tests or the fault source |
| Route | `challenges`, a fault run and a baseline run, `inspect`, `compare`, `isolate`, a `--disable` run, `score` |

The evidence it used matches what a hold-out is meant to offer: one extra finding in `compare` (left forearm and hand jumped 4.7 cm at 2.02 s with the hand target unmoved), an isolation naming the undeclared modifier at 40.0 mm, and a `--disable=AuxPass7` run that returned every metric to the baseline.

Reading it fairly: one agent, one challenge, with the workflow documents it was pointed at. It shows a hold-out was solvable from the public tools and docs. It does not show how often another agent would succeed, and it says nothing about CH08.

### Problems it hit, and what I found

| Reported | Status | What I found |
|---|---|---|
| An isolation requested at 1.9 s still found the fault, which starts at 2.0 s. | **verified, fixed** | The fault's clock added the delta of every skeleton update since it was installed, warm-up and settle frames included, so in `isolate` it started earlier than in `run`. The fault now follows the scenario's clock when run from the command line. At 1.5 and 1.9 s the isolation sees nothing; at 2.1 s it sees 40.0 mm. Only timed challenge faults were affected (CH02, CH07); the measurement of real animation was not. |
| `isolate` did not say at which scenario time the pose was held. | **fixed** | It now prints "Pose held at scenario time X s (requested Y s; the scenario does not advance during the experiment)" and stores `held_at_s`. |
| The "Reproduce" line printed by `inspect` omitted `--challenge=CH07`, so copying it reproduced ordinary Exploration. | **verified, fixed** | My earlier fix covered the report's `cli` field but not the finding's reproduction text. A finding from a run that used `--challenge`, `--fault`, `--disable` or `--set` now also names the exact headless command. |
| The 47 mm frame jump, the 48 mm wrist-to-target error and the 40 mm isolation effect are three different measurements and are hard to reconcile. | reported | They are different things (a jump between frames, a distance to a target, the effect of removing one modifier). Not yet explained side by side in a document; listed in the backlog. |
| It wanted a per-bone displacement vector and a short time series. | reported | Not built. |

One test contract changed as a result. `adda_challenge_test` asserted that CH04's isolation was INCONCLUSIVE ("the pose is still changing"). That result was the fault clock's artifact: the isolation holds the scenario, so a creep that began at 1.0 s is a steady 30 mm at 4.0 s, and the isolation now reports exactly that. The assertion was replaced by the exact 30.0 mm check, and the "a moving pose is reported inconclusive" behaviour is now tested directly with a genuinely moving pose in `adda_validation_test`, so nothing was weakened without a replacement.

## 2. GUI passes (reported, not reproduced by me)

Both passes were by an agent driving the Workbench window. The first used Scenario C and D, the second Scenario A (a question about the support-hand grip).

**What worked, as reported:** What happened? produced findings with times and magnitudes and the "NOT confirmed / cause: unknown" wording was valued; Replay to this moment reached the stair and ladder findings; Show it framed the feet well on the stair finding; Inspect a body part with "left foot" and the stage experiment (55.1 mm with `Traversal` off, 21.5 degrees with `TraversalFoot` off; `TraversalLegIK` honestly reported as not testable) gave useful results for the held pose; the weapon-grip overlay worked and separated "wrist reached its target" (0 mm) from the estimated palm gap (4.6 and 7.0 mm).

**Ratings given** (1 to 5, one evaluator, one session): discoverability 3, interface clarity 2, explanation quality 3, visual feedback 2, diagnostic usefulness 4, accessibility to an animation newcomer 2.

**Problems reported, with my status:**

| # | Reported problem | Status |
|---|---|---|
| G1 | Events in the event list are not clickable; nothing jumps to or pauses at a chosen moment. No way to step backward; clicking the progress bar does not seek. | reported; plausible from the design (replay is built around findings) |
| G2 | The HUD shows PAUSED while a replay is still visibly advancing. | reported, not reproduced |
| G3 | A previous finding's label or overlay can persist into a new scenario until Show it is pressed again. | reported, not reproduced |
| G4 | After playing Landing, What happened? said there was no recording while still listing the previous Contacts findings. The evaluator recovered with Record (free play) and could not tell why the first attempt had none. | reported, not reproduced; the stale list and the missing recording are two separate things to look at |
| G5 | Summary says 12 findings, the button says 13 (the extra one is an informational item about a measurement that did not run). | reported; the button counts all findings including informational ones, the summary headline does not (not yet checked against the code) |
| G6 | Show it frames the current body; it cannot show the event itself, and on the ladder the framing cropped the feet. | reported; Show it is documented as marking the current view, Replay is the step that gets to the event |
| G7 | A finding's title says what and how many ("Pose snap: 5 bones at once") but not where or when. Wanted "Feet jump as MIRA takes cover, 4.21 s". Also wanted a way to inspect the hands when no hand finding exists. | reported |
| G8 | The weapon-grip overlay text runs over the Scenario and Diagnostics panels and the G confirmation appears in the same overlapping text. | reported, not reproduced |
| G9 | Camera controls are buried under Scenario, Manual controls, Camera and time; Front put the cover wall between the camera and the hands. | reported |
| G10 | No challenge picker or scoring in the GUI; the challenge workflow is command-line only. | verified (by design); not stated in the app |
| G11 | The first screen gives no obvious first action; the guide is in the Diagnostics tab. | reported |
| G12 | The stair-entry slide and the ladder exit are visible but ADDA does not explain them or say whether the legs perform the right action (see the visual defects in `../animation-backlog.md` and limit 11 in `12-final-report.md`). | reported; matches a known limit |

**The evaluators' own priorities**, in order: (1) clickable events and findings that replay and pause at the moment, with frame step in both directions and slow motion beside the viewport; (2) Show it in context (fixed framing, before and after, labelled joint and target, an angle that keeps the legs and the landing surface visible); (3) label every finding and overlay with its scenario and capture, clear stale results when playback changes, show recording status beside Play; (4) body-part and transition filters ahead of severity, and a grip readout in its own panel; (5) a guide on the start screen.

A usability check the evaluator proposed, worth keeping: give someone one instruction, "Pause where MIRA starts aiming. Show me the support hand and tell me what ADDA can measure about its grip", and count it a success if they reach the pose, see the palm and its target together and explain the result without opening the docs.

## 3. What this changes in the documents

* The independence limit in `12-final-report.md` is updated: one hold-out has now been attempted blind by one other agent.
* `animation-backlog.md` carries G1 to G12 as ADDA/Workbench items.
* G2 to G5 should be reproduced before any fix: they are the ones that could mean the tool shows something untrue (stale findings, a wrong HUD state), which matters more than missing convenience.
