# FuseFire combat fairness laboratory

**Recommendation.** Keep the current Combined, contextual-on, first-legal Guard defaults while comparing a few high-value cases in real play. The owner reported a fun match with frequent repositioning on the defaults. That observation is useful even though its seed and replay have yet to be identified. Autonomous screening found that stricter modes can suppress as many good-looking lanes as questionable ones and can prolong some matches. Use that evidence to select playtests and diagnose the AI. It does not establish which mode is most enjoyable.

## Baseline and implementation inventory

| Item | Verified starting state |
| --- | --- |
| Project | Windows checkout at `C:/Users/Blue/Documents/Codex/git/fusefire-proving-grounds`, branch `codex/asymmetric-line-of-fire` |
| Source | `52f3f0925a0a47e1d2ebba7520ff994ee4f71321`. The working tree already contained local rig metadata, a trajectory overlay change, Package 04 notes and fixture changes. All were preserved. Laboratory work adds the two diagnostic hooks and the scripts in this report. |
| Engine | `C:/Users/Blue/Desktop/Folder/Godot/godot_console.exe`, `4.7.2.stable.official.ed1daf0bf`, SHA256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`. Windows 11, 12 logical CPUs. |
| Normal Start Battle | Combined, contextual firing on where supported, First legal Guard. Explicit replay configuration and the historical default for recordings without policy metadata are independent of menu defaults. |
| Replay authority | Replay executes authoritative recorded actions, compares revisions and full state fingerprints, and uses recorded firing solutions. AI planning is not rerun for playback. |

Each run records its exact command, source SHA, working-tree status, tracked-diff hash, execution identifier and configuration. Each tournament case also records selected harness/engine SHA256 values, RNG seed, map, AI configuration and initial battle fingerprint. Per-process application-data directories isolate test runs from the player's files. The source was dirty during these runs. The provenance files are the basis for reproducing the measured build.

**Legacy (A)** accepts a physical solution that reaches any of five target samples. **Head/core (B)** requires a head or core sample. **Symmetrical (C)** requires a physical lane for both units, with the same five permissible samples as A. **Combined (D)** requires central exposure in both directions. Reciprocal checks exclude AP, SP, ranges and the probability roll. Accepted shots still use the five-sample exposure calculation and existing cover, Aim and accuracy rules. A certified side step is an independently enabled same-cell physical solution. It does not spend Move AP or produce a movement reaction trigger. Guard can take the first legal reaction or apply a configurable quality threshold. It consumes no SP or RNG when holding a low-quality shot. [Combat rules](../../systems/combat_rules.gd) · [Action service](../../systems/actions/runtime/tactical_action_service.gd) · [Replay codec](../../systems/replay/battle_replay_recording.gd).

All production AI uses the same controller and action service. Shared `SquadContext` carries target claims, destination claims and objective commitments. The independent experiment gives selected actors their own context, keeping the planner, perception, individual scoring, team awareness, difficulty and commander intact. This is a coordination ablation. There is no separate independent engine. The normal default retains team contexts. The adapter runs only when a simulation explicitly requests it. [Controller and context ownership](../../systems/battle_controller.gd) · [Simulator observer](../../systems/simulation/ai_match_simulator.gd) · [Coordination regression](evidence/combat-fairness-lab/coordination.gd).

## How the laboratory classifies fairness

- **Invalid acceptance or incorrectly rejected eligibility** concerns a production result disagreeing with an independent geometric and rule expectation. Report both directions and the relevant tolerance.
- **Policy suppression** means an existing physical shot is denied because the active rule specifies central exposure or reciprocity. It can be intentional and still be frustrating.
- **Tactical asymmetry** can arise from range, cover, AP, SP, initiative, height and geometry that exposes only one shooter. A geometrically reciprocal lane does not give both units a ready or equally strong shot.
- **Counterplay** includes a legal retreat, flank, better cover or a later shot. A frozen board can expose candidate responses. It cannot guarantee those opportunities survive intervening actions.
- **Guard, previews and presentation** are separate from static eligibility. Check the actual movement checkpoint, reservation and spend. A guarded route and the destination can reach different conclusions.
- **Ambiguous gameplay judgments** include exactly how much partial exposure should count, whether guard should hold for a low percentage and whether reciprocity grants surprising immunity. Keep the underlying measurement visible.

## Controlled geometry, authority and historical witnesses

The analytic fixtures use an independent engine segment-to-box reference and a two-dimensional nearest-point test for upright cylinders with deliberately sufficient vertical extent. The reference builds its own sample rays from the stated body constants, then applies the written policies. It does not use the production candidate lookup, clipping, seam or cylinder code to produce expected outcomes. Eleven fixtures cover open and solid lanes, low cover, near-wall one-way exposure, occulted center samples, diagonal open/closed shots, narrow apertures, a fractional elevation change and two cylinder crossings. Every fixture was rotated four ways, reflected, tested in both directions and with factions reversed.

**1,408 directed policy evaluations.** Zero independently invalid acceptances and zero incorrect rejections under each declared policy. All four modes saw the same 240 physically open directed observations. A preserved 240, B preserved 192, C preserved 224, D preserved 192. The reference intentionally puts most cases away from tangency. These are fixture counts, and the mirrored cases are repeated geometry, not independent random samples. They show how a central-sample or reciprocal rule deliberately discards plausible physical shots. They do not show that such shots should or should not be permitted in play. [Geometry fixture](evidence/combat-fairness-lab/geometry.gd).

The scripted bay matrix ran 16 attack/retreat setups and 12 Guard crossing selections, with **117 checks and zero failures**. It verified unchanged previews against authority, that rejected previews do not consume RNG, ordinary AP/SP use, and the first qualified reaction checkpoint. A, B and C admitted the calibrated side-step attack with side steps enabled in both orientations. D denied it with **No mutual firing lane** because the other unit had no central return sample. B therefore preserved an actual firing angle that D removed. A, B and C could commit a retreat to a supported tile after firing. In the Guard cases, the fixtures found routes with and without a legal reaction for all four modes. Selected legal reactions occurred at checkpoint 4 under A/C and checkpoint 5 under B/D on the crossed route. The selected safe routes at 25% preserved the reaction. Those were different routes, so this result does not isolate the effect of the 25% threshold. [Scripted encounters](evidence/combat-fairness-lab/scripted.gd).

The real `Test.json` and `Strange.json` matches matched **80/80** and **74/74** records and both original victories. The archived one-way hits were narrow peripheral lanes and contextual firing was off. The original truck witness remains a controlled reconstruction, since its original replay was unavailable. In the recorded 5% Guard incident, First legal spent the shot and 15% would have held it. Later checkpoints offered no better shot on that route. Relevant old files and reconstructions are already described in the Package 05 report. [Historical inputs and reconstruction](combat-fairness-05.md).

The counterplay scan examined the actual board **after** a hit. Four surviving no-return transactions in Test and two in Strange each had a victim on 0 AP. On that fixed board all six had at least 16 one-move stops offering a legal return shot with a fresh activation. They also had at least eight stops outside that particular shooter's lane. In Strange, repeated hits at revisions 57 and 58 left 45 firing stops among 52 reachable, with two stops that offered fire while denying that shooter a return. The scan used real occupied-path reachability. It does not simulate opponent actions along the route or prove safety from other enemies. Lethal cases were tagged separately and excluded from the survivor scan. This is a concrete example of repeated damage without *immediate* fire, with potential later counterplay. [Replay response probe](evidence/combat-fairness-lab/counterplay.gd).

Crouched and kneeling combat silhouettes, posed weapon origin, a firing overhang on an actual staircase transition, sub-millimeter tangency and visually disputed doorway edges were outside the analytic oracle. The authored Parking Garage exercised actual elevated paths, while the separate curved and contextual fixtures tested the calibrated physical/animation cases in the existing certification suite. No new visual certification for those omitted configurations is implied. The report of a newly stuck player replay is open and separate. Neither of the two archived matches reproduced a freeze in this lab, and the new replay has not been identified.

### Owner playtest — Guard around the truck

The owner described a Service Depot fight on their reported default settings where neither side could shoot around the truck without exposing itself. They repositioned to create an ambush, saw the enemy shift and reserve Guard, and described their two units as having an advantage over the final hostile. The enemy eventually moved into the fight. The player liked that Guard mattered while the truck still gave them a way to break contact. Those are observations about the experience of one match.

The screenshots independently show a Move preview with **0 outgoing and 0 incoming lanes at arrival**, and identify route reactions separately. The combat log shows the cargo truck blocking the hostile's reaction while preserving its reservation. Later screenshots show Alpha and Hostile 2 guarding on opposite sides of the truck. The opening pressure, eventual commitment, exact positions and active settings across the whole match are not reconstructed from stills. In this example, mutual obstruction gave the player a reason to reposition.

**Separate replay incident.** The owner reported that playback stalled after the match and no replay JSON or seed was saved. The current replay session holds the last recording in memory. The Save Replay dialog belongs to the original battle result, and switching to playback removes that battle. A candidate session log contained seed `407140976` and a 45-action Depot victory, but it recorded Hostile 2 dying first. The screenshots show Hostile 1 defeated while Hostile 2 remains alive. The candidate log cannot establish the seed or failing action for this event. The replay freeze remains open without a verified reproduction. [Replay session](../../systems/replay/battle_replay_session.gd) · [Battle-result save flow](../../ui/turn_hud_controller.gd).

## Autonomous design

The pilot contained four matched Depot Crossfire modes plus a second cold-process Legacy run. The primary sample contained **128 battles**, or 32 matched blocks of four. It crossed eight map/seed/force blocks with both shared, both independent, shared-player-only and shared-enemy-only coordination. It used Depot Crossfire with three seeds, Freight Yard with two 2v2 seeds plus one 3v3 seed, Fleet Station and Parking Garage with one seed each. Both factions used matched Generic equipment, Hard, Default commanders, contextual firing off and First legal Guard. **All 32 blocks had identical opening state fingerprints across the four modes.**

The **32-match factorial** crossed mode, side steps on/off and 0%/15% Guard on Depot Crossfire and Freight Yard at seed 16, both teams coordinated. A separate **16-match bay block** used four seeds covering both spawn sides and both authored orientations. It toggles the physical role of Player and Enemy, while the seed also changes RNG. In ordinary matches Player initiative is fixed by `TurnManager.start_battle`. The laboratory did not alter it or claim to separate initiative, faction and map deployment effects beyond the exact faction reversals in the analytic fixtures. In total, **181 AI matches completed their experiment and saved recordings**, including capped matches. Eight full rounds was the fixed cap. “Unfinished” means the cap was reached, with no winner inferred. Five pilot cases took 5.9–7.8 wall seconds per match under the initial worker count. Further runs increased contention. The batch size balanced matched map coverage with practical desktop time.

All primary and factorial matches used real production decisions and action validation, in headless fixed-60-delta mode. The slight loss of rendered fidelity permits comparisons of decisions and mechanics. It does not estimate frame rate. The repeated Legacy pilot produced byte-equivalent canonicalized action records, including the same rolls and state fingerprints. In the main steps-off workload, B and D also produced identical action records across all 32 matched blocks. B and D differed with contextual steps enabled in two factorial blocks, and in two bay blocks. Their identical trajectories in the primary workload are not a claim of global equivalence.

## Autonomous results

Each column represents 32 main comparisons. Directional counters refer to the current policy's physical return lane measured on the post-hit surviving board. Due to lethal hits and reactions, not every transaction can be inspected. Reaction damage is excluded from the direct damage denominator.

| Measure | Legacy | Head/core | Symmetrical | Combined |
| --- | ---: | ---: | ---: | ---: |
| Completed / capped | 25 / 7 | 9 / 23 | 21 / 11 | 9 / 23 |
| Player wins / Enemy wins | 20 / 5 | 8 / 1 | 20 / 1 | 8 / 1 |
| Moves / Waits | 532 / 107 | 536 / 307 | 504 / 187 | 536 / 307 |
| Ordinary attacks / hits | 479 / 392 | 286 / 274 | 386 / 330 | 286 / 274 |
| Guard armed / reactions | 111 / 33 | 169 / 22 | 117 / 22 | 169 / 22 |
| Direct HP damage | 9,800 | 6,850 | 8,250 | 6,850 |
| Surviving direct hits evaluated / unchecked damaging hits | 308 / 84 | 218 / 56 | 266 / 64 | 218 / 56 |
| Damage without a physical return lane / inspected surviving damage | 200 / 7,700 | 0 / 5,450 | 0 / 6,650 | 0 / 5,450 |
| Damage-free counted rounds | 76/182 (42%) | 152/218 (70%) | 100/182 (55%) | 152/218 (70%) |
| Multiple allied shooters on a target in a round | 25 | 22 | 26 | 22 |
| Median committed record at first attack | 17.5 | 18 | 16 | 18 |

The eight Legacy survivor hits without a return constituted 2.6% of assessed surviving direct damage. This is a measured directional difference, without evidence in itself of invalid shots or an inability to reposition. One-way lanes at AI activation were observed 42 times under Legacy and zero under the other three in this sample. The geometry controls and enabled factorial show that B can still admit physically one-way scenarios. A raw observed zero is conditional on the positions reached by each policy.

| Main match completions by map | Denominator per mode | Legacy | Head/core | Symmetrical | Combined |
| --- | ---: | ---: | ---: | ---: | ---: |
| Depot Crossfire | 12 | 12 | 4 | 8 | 4 |
| Freight Yard | 12 | 9 | 5 | 9 | 5 |
| Fleet Station | 4 | 0 | 0 | 0 | 0 |
| Parking Garage | 4 | 4 | 0 | 4 | 0 |

Across the 32 pairs, B and D each completed **50 percentage points fewer** than A. A descriptive 95% bootstrap, clustered by the eight map/seed/size blocks, spans **−87.5 to −12.5 points**. C completed **12.5 points fewer** than A, with a descriptive interval of **−37.5 to 0**. The intervals describe variability across this short list of fixed scenarios, including Fleet cap effects. They are not population estimates or a proof about match quality. Moving remained frequent in all modes. The additional Wait actions, reduced damage and higher protected-activation counts show the pace trade-off more clearly than win rate.

The mixed coordination conditions had nearly the same completion counts. Shared-player-only completed 7/8, 3/8, 6/8 and 3/8 under A/B/C/D. Each other coordination pattern completed 6/8, 2/8, 5/8 and 2/8. Role assignment was balanced across blocks, but Player always opened from its authored spawn side. No claims about inherent faction advantage or causal initiative effects follow from this design.

**Interaction.** Steps and Guard are independent. With two maps per factorial cell, enabling steps enabled four B attacks in the Depot match and raised the completion count for that cell from 0/2 to 1/2. It also introduced up to 75 HP of one-way damage in each enabled B cell. A and C finished 1/2 in every factorial setting. D finished 0/2 in all settings. The 15% threshold did not change the receipts in these matched scenarios and no actual low-quality hold was logged. The 5% archive witness still proves the threshold can matter. In the swapping bay variants A and C completed 4/4, B completed 2/4 and D completed 1/4. The stricter policy's main cost in this matrix was suppression and time without progress, not a documented fabricated ray.

## Technical costs

These are actual samples from the specified headless host under parallel workloads. CPU contention, renderer absence and fixed simulation delta limit what can be inferred about the shipping build.

| Main workload, ms | Legacy | Head/core | Symmetrical | Combined |
| --- | --- | --- | --- | --- |
| Per-decision planner work median / P95 / max | 35.5 / 116.9 / 268.1 | 36.1 / 115.6 / 205.4 | 37.7 / 125.3 / 251.7 | 37.5 / 121.5 / 269.6 |
| Full AI activation median / P95 / max | 807 / 1,396 / 2,218 | 448 / 1,346 / 2,123 | 790 / 1,796 / 2,445 | 547 / 1,661 / 2,625 |
| Per-match wall time median / P95 / max, seconds | 11.8 / 21.4 / 22.2 | 14.2 / 21.6 / 23.0 | 13.1 / 27.2 / 30.3 | 17.5 / 24.7 / 26.5 |
| Logged attack-inventory evaluations | 3,483 | 3,697 | 3,537 | 3,697 |

Inventory counts are planner evaluations, not raw ray counts. Read-only instrumentation made 308/218/266/218 post-hit return-lane queries, with mean cost about 221/207/227/201 µs under the recorded conditions. The fixed-board benchmark measures complete hypothetical shot evaluation on the same candidate lists. Each cell below is the median of five blocks after warm-up, in µs per query. Each block contained 912 evaluations on Depot or 549 on Freight. Query order rotated. This rerun did not overlap the tournament batch.

| Canonical query workload | Legacy | Head/core | Symmetrical | Combined |
| --- | ---: | ---: | ---: | ---: |
| Depot Crossfire, steps off | 519 | 531 | 589 | 584 |
| Depot Crossfire, steps on | 782 | 795 | 849 | 877 |
| Freight Yard, steps off | 521 | 520 | 611 | 606 |
| Freight Yard, steps on | 583 | 600 | 675 | 696 |

Terrain caches remain as shipped. The laboratory did not instrument engine-wide cache hit rates or certify rendered frame timing. [Query microbenchmark](evidence/combat-fairness-lab/query_bench.gd).

## High-value comparisons and reproduction

1. **Normal match with current defaults.** The owner’s enjoyable, repositioning-heavy match is important alongside autonomous cap rates. Keep a replay or a seed and the last few action details when practical. A staged manual conclusion is stronger than inference from these automated opponents.
2. **Depot Crossfire, same seed, contextual on.** Use `Match Setup → Combat → Service Depot — Crossfire`. Run it under Combined, then Head/core or Symmetrical with the other controls held fixed. Watch whether moving creates a new useful line and how long a protected opponent waits. The preset fills settings. **Start Battle** uses the visible briefing.
3. **Calibrated bay shot and retreat.** Open the saved Head/core witness. It records the successful side-step Attack followed by a retreat. Combined suppresses the initial shot on that identical board. The headless replay verified both recorded actions.
4. **Guard 5% historical witness.** Open the original Test replay in the existing Replay menu. The diagnostic shows First legal committing at the third checkpoint and 15% holding. Replay playback preserves the original rule. Use the counterfactual tool to compare.

Keep Legacy as a historical control. Retain the side-step capability and verify where the AI can find real firing opportunities under Combined. Treat higher Guard thresholds as configurable until a broader set contains enough opportunities where they operate. Reconsider narrow central filtering and explicit reciprocity as independent policy choices if further games reproduce the suppression trade-off. Investigate blocked-origin AI routes and where a human finds a flank that the planner ignores. The present results do not justify an AI retune or any removal.

The commands below ran on Windows using the explicit source checkout and Godot above. Use **new** output folders for repeat runs. The scripts produce case manifests, individualized provenance, compact receipts and replay JSON files. Reports under the artifact directory are generated by the analyzer. Launch smoke probes confirmed real scene initialization for Combined Depot Crossfire with 15% Guard and Head/core Freight with side steps off. The optional rendered laboratory launcher stamps the actual source SHA prefix, dirty-tree marker, seed and combat options on screen. Normal interactive play can also use the existing Match Setup. Other operating systems and exported binaries were outside the verification.

```powershell
Set-Location 'C:/Users/Blue/Documents/Codex/git/fusefire-proving-grounds'
$godot = (Get-Command godot_console).Source
$lab = 'docs/quality/evidence/combat-fairness-lab'

python "$lab/run_lab.py" --project . --godot $godot --out artifacts/fairness-lab/main-v1 --batch main --workers 5
python "$lab/run_lab.py" --project . --godot $godot --out artifacts/fairness-lab/factorial-v1 --batch factorial --workers 2
python "$lab/run_lab.py" --project . --godot $godot --out artifacts/fairness-lab/mirrored-v1 --batch mirrored --workers 2
python "$lab/analyze_lab.py" artifacts/fairness-lab main-v1 factorial-v1 mirrored-v1

python "$lab/run_probe.py" . $godot artifacts/fairness-lab/geometry-v2 "res://$lab/geometry.gd"
New-Item -ItemType Directory -Force artifacts/fairness-lab/witnesses | Out-Null
python "$lab/run_probe.py" . $godot artifacts/fairness-lab/scripted-v1 "res://$lab/scripted.gd" res://artifacts/fairness-lab/witnesses
python "$lab/run_probe.py" . $godot artifacts/fairness-lab/response-test "res://$lab/counterplay.gd" res://docs/quality/evidence/contextual-04/Test.json
python "$lab/run_probe.py" . $godot artifacts/fairness-lab/verify-bay "res://$lab/replay_check.gd" res://artifacts/fairness-lab/witnesses/bay-attack-retreat-mode-1.json

python "$lab/run_probe.py" . $godot artifacts/fairness-lab/playable-build-verified res://docs/quality/evidence/combat-policy-05/play_comparison.gd --play combined guard=15 smoke
```

Project import and **10 selected Ironclad tests passed**, including combat geometry, curve integration, combat previews, shared engagement policy, Guard, AI determinism, presentation authority and replay. The laboratory coordination probe passed six checks. Representative completed and capped tournament recordings verified **48/48** and **50/50** actions. Qualification is limited to those replays and the archived fixtures above. The laboratory is local and changes no production default or balance rule.
