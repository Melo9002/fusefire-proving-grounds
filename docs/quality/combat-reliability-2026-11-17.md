# Combat reliability measurements — 2026-11-17

Step 11 retains the provisional balance. See the [everyday guide and AP/ammo tradeoffs](../combat-reliability.md). Step 11 retains tuning and damage rules. Step 12 subsequently corrects the 100% random-endpoint defect and versions the simulation; see its linked report.

## Fixed conditions and results

Each condition uses 2,048 independently seeded trials, seeds 60000–62047 inclusive. All conditions share those seeds. Ordinary attacks use the first RNG draw; real Guard retaliation uses the second draw after the triggering attack. The experiment measures 34,816 selected shots/reactions across 17 conditions, with HP/AP/ammo reset between trials. It is not 34,816 turns of a continuous match.

| Condition | Advertised hit | Observed hit | Damage on hit | Mean damage | All four hit, per 512 groups |
| --- | --- | --- | --- | --- | --- |
| exposed close | 100% | 100.00% | 25 | 25.00 | 512 |
| low cover | 80% | 79.98% | 25 | 20.00 | 211 |
| full cover high | 71% | 70.46% | 25 | 17.61 | 126 |
| full cover level | 60% | 59.67% | 25 | 14.92 | 62 |
| full cover level aim | 95% | 95.07% | 25 | 23.77 | 423 |
| flanked low cover | 100% | 100.00% | 25 | 25.00 | 512 |
| low cover aim | 100% | 100.00% | 25 | 25.00 | 512 |
| range 70 | 96% | 96.04% | 25 | 24.01 | 439 |
| range 80 | 83% | 83.06% | 25 | 20.76 | 249 |
| range 90 | 61% | 60.55% | 25 | 15.14 | 67 |
| range limit | 30% | 29.83% | 25 | 7.46 | 7 |
| range limit aim | 65% | 64.70% | 25 | 16.17 | 89 |
| range limit high aim | 75% | 75.15% | 25 | 18.79 | 167 |
| range limit low | 20% | 19.78% | 25 | 4.94 | 0 |
| shield front | 80% | 79.98% | 9 | 7.20 | 211 |
| shield rear | 100% | 100.00% | 25 | 25.00 | 512 |
| guard close | 85% | 84.86% | 25 | 21.22 | 257 |

Four-shot groups use consecutive independent seed trials. Four hits would defeat an unshielded 100-HP target at 25 each; these groups do not model reloads, AP, movement, reactions or shielded kills. The 9-damage Shield result needs 12 hits. Miss streaks in the raw report are streaks across this fixed seed scan, not a promise about ordinary campaign pacing.

Full cover in this setup leaves shoulder samples visible: 60% at equal height and 71% with 2.2 tiles of height advantage at the same total distance. Low cover gives 80%, and the same low cover provides no protection from its open flank. Completely blocked shots remain illegal regardless of Aim. A 95% shot still missed in 101 of 2,048 trials. No luck correction was added.

## Reproduction

Ordinary regression uses 128 trials per condition to keep the suite bounded. Full measurement is explicit:

```powershell
godot_console --headless --path . --script res://tests/combat_reliability_test.gd
./tools/measure_combat_reliability.ps1
```

The wrapper discovers conditions from the bounded check, then measures each in a separate process and requires a clean exit from every process. Large direct runs require one exact condition name (second argument) and at most 2,048 samples (third argument); combined large batches are rejected before construction. The JSON output includes tuning signature, exact hits, damage, groups, miss streaks and outcome hashes. Queries are checked for RNG purity; committed shots are checked against the exact seeded roll, advertised integer chance and fixed hit damage. Guard additionally checks real AP/reservation/SP consumption. Distribution checks use six binomial standard errors plus one sample, with fixed seeds, not seed selection until green.

## Failures found during the measurement

The first fixture applied controlled height/distance before compilation; the compiler correctly resolved those values back to supported ground. The fixture now applies the intended controlled positions after compilation. This was a defective new test setup, not a gameplay regression or a change to the cover rules. The level full-cover baseline is 60%, with Aim 95%.

The first combined runs printed zero assertion failures but crashed during native shutdown with exit **-1073741819 / 0xC0000005**, matching the owner’s Godot dialogs. These are failures. Queued teardown, periodic yielding and process isolation alone did not resolve it: a low-cover-only process also failed, and a subsequent bounded inventory failed. The cause was not simply “too many shots.”

The fixture lacked a floor reference and built a temporary navigation graph solely to resolve standing points. It now has a real floor, as battles do, and calls the existing standing-point resolver directly; no unused AStar graph is constructed. Three focused low-cover probes and then all 17 isolated 2,048-trial conditions exited zero. Outcomes and evidence hashes match the earlier numerical output exactly. This corrects and simplifies the new measurement fixture; production combat/navigation were not changed.

A separate temporary-graph-only probe also exited zero three times, so the graph alone is **not** an established minimal root cause. Native debug collection located the failure in the Godot executable, but there are no matching internal symbols to prove an engine function or lifetime defect. [Issue #33](https://github.com/Melo9002/fusefire-proving-grounds/issues/33) stays open for that investigation. The harness fix must not be described as a general gameplay crash fix. Automated measurement children suppress the Windows crash dialog while preserving nonzero native exit failures, preventing unattended runs from waiting on a popup.

## Verification and remaining work

- Final full measurement: **17 conditions × 2,048 trials = 34,816 measured outcomes; all 18 processes (inventory plus conditions) exited zero**. Output: `artifacts/reliability-20261117-143806/summary.json`.
- The complete raw rows, tuning signature and outcome hashes equal the earlier numerical output. Equality of data does not retroactively turn the crashed processes into passes.
- Ordinary bounded fixture: 128 trials per condition; all original numerical/legality/damage assertions remain.
- The runner diagnostic passed all 11 smoke entries and correctly reported both intentional probes as failures: **11 pass / 2 expected fail / 0 skip**, exit 1. One probe exits nonzero; the new probe raises an unhandled script error and exits zero. Ironclad now rejects both. This diagnostic is not an unexplained failing smoke baseline.

The separate complete Freight Yard seed-16 battle reached victory in round 5 (52 recorded actions); Fleet Station seed 16 reached victory in round 12 (100 actions). Saved playback verified every action, final result and recent combat log; the process exited zero. These two automated matches are consistency evidence, not human difficulty or pacing feedback.

The step-11 study itself did not establish rendered battle readability, a broad green baseline, seed-17 real-map completion or query performance. The subsequent [step-12 closure report](combat-closure-2026-11-17.md) records those separately. The existing Windows root-certificate-store error appeared in the inspected logs.
