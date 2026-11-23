# ADDA for coding agents (Claude Code, Codex)

A repeatable procedure for finding out **why an animation misbehaves**, using only the Godot command line and the files ADDA writes. No MCP server, no embedded model: an agent runs commands, reads JSON and plain text, and reports what it measured. A person can follow the same steps; the Why? tab ([07-usage.md](07-usage.md)) shows the same data.

**Independence.** This procedure was written and exercised by one agent (Claude). It has **not** been validated by another agent. Two hold-out challenges (CH07, CH08) are set aside for that; see section 6.

## 0. Setup

```powershell
$env:PATH += ";C:\Users\Blue\Desktop\Folder\Godot"       # godot_console.exe; or pass -Godot <path> to the wrapper
.\tools\adda.ps1 list                                     # scenarios, characters, the report format
```

Always run with a **fixed frame rate** (`--fixed-fps 60`, the wrapper does): two runs of the same command are then identical to the last digit, so a difference between two runs is a real difference. Raw form: `godot_console --headless --fixed-fps 60 --path . --script res://tools/adda/adda.gd -- <command> ...`.

## 1. The procedure (nine steps)

| # | Step | Do | Read |
|---|---|---|---|
| 1 | **Pick the diagnostic** | the symptom decides (table in 2) | |
| 2 | **Reproduce** | `adda run --scenario=<s> --character=<c> [--unarmed] --out=a.json` | `config` (what ran, revision, the exact command to repeat it), `summary.headline` |
| 3 | **Collect evidence** | the same `run`; add `-Mesh` for leg-in-ladder questions; `-Detail full` if you need every row | `findings` (worst first), `worst_frames`, `events` |
| 4 | **Interpret** | `adda inspect --report=a.json --finding=F1` | `Observed` (measured), `Possible causes (NOT confirmed)`, `Does not establish`, `Measured with` |
| 5 | **Separate observation from hypothesis** | write them in two lists | a finding is an observation; every hypothesis is `unconfirmed` and names its `basis` and the `experiment` that tests it |
| 6 | **Find the likely owner** | `adda isolate` (below) names the modifiers that move the bone; `PoseOwnership.WRITES` lists what each *declares*; then read the stage's source | the two can disagree: that is information |
| 7 | **Run a controlled experiment** | change **one** thing: `--unarmed`, `--character`, `--disable=<modifier>`, `--set=Node.prop=value`, or your code | `config.experiment` in the new report says what was changed, and whether it held |
| 8 | **Verify** | `adda compare --a=before.json --b=after.json --fail-on=regression` | `VERDICT`, then metrics improved/regressed/INCOMPARABLE/MISSING, then findings NEW/RESOLVED/UNVERIFIABLE |
| 9 | **Report the uncertainty** | say what was measured, what was tested, what is still unknown; `cause: unknown` stays unknown until a test settles it | |

### 2. Which diagnostic for which symptom

| Symptom | Start with | Then |
|---|---|---|
| a hand misses its contact | `run`; findings "target out of reach" / "target error" | `inspect` the finding: margin, error, weight, the stages engaged; `isolate --bones=@right_hand` |
| a foot slides, creeps or ends off its foothold | `run`; "slides while planted", "is off its foothold", "settles late" | the three differ: a slide moves against its foothold at constant error; an offset ends far off; a settle closes in (stance onset) |
| a bone pops for a frame | `run`; "Pose snap" | does the finding say a *target* or *knee pole* jumped in the same frames? then the input moved, not the solver; `isolate --window=150` for a fault on some updates only |
| the body intersects geometry | `run -Mesh` (ladder only) | a clean count is from a **settled** pose; `UNSUPPORTED` means not measured |
| a modifier unexpectedly changes a pose | `isolate` on the bone | an `(NOT declared in PoseOwnership)` modifier is the answer to "who is this" |
| armed behaves differently from unarmed | `run` both, `compare` | armed against unarmed is an experiment; the compare says so |
| works on MIRA, fails on Small MIRA | `run` both, `compare` | lengths are divided by each body's `body_ratio`; INCOMPARABLE metrics are listed, not hidden |
| a test passes but it looks wrong | `run` the scenario the test covers; read `findings` | a passing test means its assertion held, not that nothing else is wrong (a capsule test and a mesh test disagreed in this repository) |

## 3. The experiment commands

```powershell
# is there a modifier nobody declared moving this bone, at this moment?  (pause + hold is automatic)
.\tools\adda.ps1 isolate -Scenario tactical -Character mira_0 -At 3.5 -Bones "@right_hand,@right_elbow"
# the fault fires only on some updates: sample a window
.\tools\adda.ps1 isolate -Scenario landing -Character small_mira_0 -Unarmed -At 3.0 -Bones "@right_knee" -Window 150
# switch a modifier off for the whole run, then compare with the plain run
.\tools\adda.ps1 run -Scenario contacts -Character mira_0 -Disable CoverCrouch -Out after.json
.\tools\adda.ps1 compare -A before.json -B after.json
```

`isolate` switches every `SkeletonModifier3D` off in turn **in one held pose** and reports, per modifier and bone, how far the bone moves (`mm`), turns (`deg`) or spikes (`intermittent`). It is an **experiment**: it changes state for a few frames and restores it, and it says whether the pose came back. It cannot say what a modifier "writes": a stage that only sets a target moves the arm through the solver after it, and both are reported. Roles `@hips @head @left_hand @right_hand @left_elbow @right_elbow @left_knee @right_knee @left_foot @right_foot` work on both bodies; a bone name works too.

Result reading rules (all printed with the result):
* `INCONCLUSIVE` means the pose was still moving (drift above the floor) or did not come back; effects below the printed noise floor are **not attributed**.
* `could NOT be tested` means the rig switched that modifier back on while the experiment ran (the leg IK is switched by the traversal stage). The same is flagged in a run's `config.experiment` as `NOT HELD`. A "no change" there is a false negative; do not read it.
* An effect is *what changes if this modifier is off*, not *what it writes*.

## 4. Evidence files (worked example: challenge CH01, solved; use CH07 or CH08 to attempt blind)

* [`examples/ch01-compare.txt`](examples/ch01-compare.txt): the fault run against its fault-free baseline: `REGRESSED`, one NEW finding.
* [`examples/ch01-finding.txt`](examples/ch01-finding.txt): `inspect` of that finding: observed, unconfirmed hypotheses, what it does not establish, the rows around it.
* [`examples/ch01-isolation.json`](examples/ch01-isolation.json) and `.txt`: the isolation: `AuxPass1 (NOT declared in PoseOwnership): right hand moves 50.0 mm`.

How to interpret that evidence correctly: *the finding says a pose snap of the right hand at 2.98 s, the hand target did not jump (so the pose itself changed); that is an observation. It does not say a persistent offset exists. The isolation says an undeclared modifier moves the hand 50.0 mm in a held pose; that is a measurement of its effect in that pose. Neither says why the modifier exists or whether 50 mm is wrong.*

## 5. Common mistakes (each one happened or nearly happened)

1. **Calling a FRESH sample settled.** A pose asked for cold takes a few updates to arrive; early samples can show leg-in-rung overlaps that are gone three updates later. Wait for `PoseSettle` or compare two samples.
2. **Reading "RESOLVED" as "fixed".** It means "not present in run B". A larger fault can bury a smaller finding (CH03); read the metrics too.
3. **Reading "UNCHANGED" as "nothing is wrong".** A constant offset of a bone with no target and no snap changes nothing ADDA watches (CH05).
4. **Trusting the first hypothesis.** The snap finding at cover entry offers "CoverCrouch engaged in the same row"; `--disable=CoverCrouch` leaves the snap in place. Test, then believe.
5. **Using `--disable` on a stage the rig switches itself.** Check `config.experiment` for `NOT HELD`.
6. **Comparing across frame rates.** Metrics tagged `frame_rate` are INCOMPARABLE; run both at `--fixed-fps 60`.
7. **World-space foot slide on the stairs bench.** It is a treadmill: the stairs move, the character does not. Use ankle-against-foothold.
8. **Treating a capsule or sampled-vertex count as a mesh intersection.** The instruments list says `UNSUPPORTED` for full mesh intersection.
9. **Believing a committed capture over a re-run.** One committed ladder still could not be reproduced from its own commit ([09-diagnostic-challenges.md](09-diagnostic-challenges.md), section 4).
10. **Quoting a cause.** `cause` is `unknown` until an experiment settles it. Say "the knee pole jumps in the same frames", not "the knee pole causes the pop".

## 6. Blind challenge protocol for another agent

1. Do not open `tools/adda/challenges/sealed/`, `tests/adda_challenge_test.gd` or `docs/claude/adda/09-diagnostic-challenges.md` (they contain answers for CH01 to CH06; CH07 and CH08 are hold-outs, answered only in `sealed/`).
2. `adda challenges` for the symptom; `adda run ... --challenge=CH07` (the scenario, body and armed flag are in the list).
3. Investigate with the commands above. Keep a log: commands run, hypotheses held and dropped, the time.
4. Answer with `adda score --challenge=CH07 --stage=<modifier name> --bone=<@role or name> --kind=<offset|pop|drift|yaw>`; it says which fields match, not the key.
5. Report: commands used, whether any ADDA finding or hypothesis misled you, what you wished it had measured. If you opened `sealed/`, say so; the result is then not blind.

## 7. A report template for an agent's conclusion

```
Symptom:            <as given>
Reproduced with:    <config.cli of the report>   (revision <commit>)
Observed (measured): 1. ...  2. ...
Hypotheses (unconfirmed): H1 ... (basis ... ; test ...)
Tested:             H1: <experiment>, result: supported / refuted / inconclusive
Likely owner:       <file/stage>, because <isolation or source>
Still unknown:      ...
Verified by:        compare <a> <b>: <verdict>
```
