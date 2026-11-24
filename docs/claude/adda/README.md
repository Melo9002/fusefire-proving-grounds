# ADDA: AniLab Diagnostic & Debugging Assistant

ADDA is the name of AniLab's diagnostic suite. AniLab makes characters move; ADDA helps you understand their movement: **observe a problem accurately, reproduce it reliably, make a better engineering decision.** It is not a separate framework: it is the read-only tools in `presentation/diagnostics/`, the Workbench (`tools/animation_workbench/`, "ADDA - Workbench"), the measurement contract, and a command line (`tools/adda.ps1`). AniLab stays part of FuseFire; nothing in the game creates a diagnostic, and the diagnostics never write a pose.

This repository is the source of truth. The project knowledge base on Drive (<https://drive.google.com/drive/folders/1KhqDfqOxZvWRA0D3dOStX2WqRDq7EXXm>) holds the wider AniLab notes; nothing here depends on it.

## Start here

| I want to... | Read |
|---|---|
| investigate a problem right now (person, in the Workbench) | [11-human-workflows.md](11-human-workflows.md), then [07-usage.md](07-usage.md) |
| investigate it as a coding agent (Claude Code, Codex) | [10-agent-workflow.md](10-agent-workflow.md) |
| know what ADDA can and cannot see, with evidence | [09-diagnostic-challenges.md](09-diagnostic-challenges.md) |
| know what it costs, what was verified, what is weak | [12-final-report.md](12-final-report.md), and what an outside user found: [13-independent-evaluation.md](13-independent-evaluation.md) |
| understand what a measurement means and when it is valid | [03-measurement-contract.md](03-measurement-contract.md) and the section below |
| know what existed before ADDA, and why it is built this way | [01](01-baseline-and-architecture.md), [02](02-capability-inventory.md), [04](04-requirements-and-research.md), [05 ADR-0001](05-adr-0001-measurement-architecture.md) |
| attempt a blind challenge | **Parked**, see the note under the table. Not needed to use the Workbench. |

Document list: 01 baseline and architecture, 02 capability inventory, 03 measurement contract, 04 requirements and research, 05 ADR-0001, 06 handoff after Assignment 1, 07 usage guide, 08 Assignment 2 report, 09 diagnostic challenges, 10 agent workflow, 11 human workflows, 12 final report, 13 independent evaluation (the first outside use). Worked example evidence is in `examples/`; images in `../images/adda/`.

> **Challenges are parked (2026-11-24, Pedro's call).** The eight sealed challenges (CH01 to CH08) are command-line only; the Workbench never shows them and you do not need them to use ADDA. They stay in `tools/adda/challenges/` because the tests and the CLI read them there; nothing was moved or deleted. Do not open `tools/adda/challenges/sealed/` (it holds the answers). Revisit them after the Workbench is easier to use. Anything said in older docs about "try a challenge first" is on hold.

## What it can do

| Question | Instrument | Where |
|---|---|---|
| Is this measurement trustworthy? | `Measurement` (kind, status, pose, space, method, limits), `PoseWitness` (the one place a pose is final), `PoseSettle` (is it still arriving?) | `presentation/diagnostics/` |
| Where is it, in the final pose, local and world? | `SessionRecorder` rows: bones (character frame), root, wrists, ankles, targets (world), reach margins, stages engaged, ladder bars, knee poles, carried passenger | |
| What happened over time? | `TimelineAnalysis`: contact acquired/released, reach exceeded, target error, foot slide / settle / **offset**, pose snaps, target and pole and passenger jumps, state, stage and context changes | |
| What should I look at, in words? | `Findings`: observation, unconfirmed hypotheses with their test, `cause: unknown` | |
| Did my change help? | `ReportCompare`: improved, regressed, unchanged, INCOMPARABLE, MISSING, UNVERIFIABLE | |
| Who moves this bone? | `StageIsolation`: each pose modifier switched off in turn (an experiment), undeclared modifiers named, rotation and intermittent faults seen | |
| Run it without the editor | `adda.gd` / `tools/adda.ps1`: `run inspect compare isolate list challenges score`, `--disable`, `--set`, `--fault`, `--challenge` | `tools/adda/` |
| See it | Workbench tabs Diagnostics, Evidence and **Why?**, `FindingMarker` | `tools/animation_workbench/` |

## The measurement rules (short)

1. **A pose is final only inside `Skeleton3D.skeleton_updated`.** Outside it the skeleton gives the animation pose without the modifiers. Every ADDA sample is taken in the `PoseWitness.final_pose` signal, stamped, and judged FRESH or STALE; a stale sample is never read as current.
2. **FRESH is not SETTLED.** A pose asked for cold takes a few updates to arrive; a clearance count taken then describes the transient. Wait for `PoseSettle` ([09](09-diagnostic-challenges.md) section 4).
3. **Bones are in the character's frame; roots, wrists, ankles and targets are in the world.** The recorder's coordinate agreement is tested at three placements and facings.
4. **Observation is not cause.** Every finding carries `cause: "unknown"` and hypotheses marked unconfirmed, each with the experiment that would test it.
5. **What was not measured says so.** `NOT TAKEN` and `UNSUPPORTED` appear in the instruments list; full mesh intersection and physical collision are `UNSUPPORTED`; a vertex count, a capsule overlap and a support claim are each named as what they are.
6. **Passive means passive.** The recorder, mesh sampling and settle watcher leave every final pose bit-identical (a hash test with a 1 mm negative control). `StageIsolation` and `--disable` / `--set` are **experiments**: opt-in, labelled, restored.

## Common measurement traps

* a FRESH sample taken on the update after a pose request (transient);
* a committed capture that cannot be reproduced from its commit;
* "RESOLVED" read as "fixed", "UNCHANGED" read as "nothing is wrong";
* a modifier the rig switches itself, "disabled" and silently re-enabled;
* the stairs bench is a treadmill: world-space foot motion is meaningless there;
* a hypothesis that is true of a coincident event (CoverCrouch engages at the same row as a clip change);
* a persistent offset of a bone with no target (nothing to be an error against);
* metrics that depend on the frame rate compared across frame rates.

## Limits worth knowing before you trust it

See [12-final-report.md](12-final-report.md) section 7 for the full list. In short: mesh sampling is ladder-only; a held pose is needed for isolation; a persistent offset of an untracked bone is not noticed unprompted; thresholds were set on two bodies; replay is exact only for fixed-step runs; **ADDA finds numerical anomalies, not wrong behaviour** (a character can smoothly carry a climb cycle onto a platform and pass every check; a clean report never means the animation is right, see [12-final-report.md](12-final-report.md) item 11 and the visual defects in [../animation-backlog.md](../animation-backlog.md)); and **so far one other agent has used it (CH07 solved blind, two GUI passes; see [13-independent-evaluation.md](13-independent-evaluation.md)), no person other than the author has, and CH08 is untried.**

## Where things are

```
presentation/diagnostics/   measurement, recorder, analysis, findings, report, compare, settle, isolation, markers
tools/adda/                 command line (adda.gd), challenge fault and set, sealed challenges
tools/adda.ps1              the wrapper
tools/animation_workbench/  ADDA - Workbench; ui/why_tab.gd
tools/quality/adda_*        probes: passivity, overhead, overhead tiers, ladder discrepancy
tests/adda_*                measurement integrity, timeline, report compare, workflow, cli, validation, challenge, why capture
```
