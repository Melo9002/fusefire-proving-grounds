# AI Step 11 — Planning performance and F3 decision history

## Review summary

Step 11 measures planning at the actual action boundary and makes decisions inspectable through their recorded facts and action receipts. Two changes remove unnecessary planning work without pruning the legal candidate set. F3 also defers timeline layout until inspection opens. The profile still shows synchronous route searches large enough to miss the responsiveness target. The review branch is `codex/ai-step11-profiling-f3`. Step 12 remains a separate acceptance pass.

## Method

- Merged Step 10 base `4154b5de3cddccf01ea3b6c9191fa9d5f4f1857e`. The reference runtime is `aa7c64dc375ea89fe23f9c26bd633467d32f0f1e`, which adds the same timing boundaries to Step 10. The review runtime keeps those boundaries and adds the optimizations and F3 changes below.
- Local Windows desktop, build 22000, AMD Ryzen 5 5500, 12 logical processors, Godot `4.7.2.stable.official.ed1daf0bf`. Both runs used headless simulation, the harness's `Engine.time_scale = 12`, and the same seeds, sites, squad sizes, and difficulty. One Godot batch ran at a time. A new process starts each group, so the numbers include mixed cold and warmed planning, with no separate warmup samples. There was no hardware telemetry for background load.
- Normal at seed 17 ran Elimination and Enemy Evacuation on Service Depot, Freight Yard, and Fleet Station with 3v3 squads. Easy ran Fleet Station Rescue, seed 17 and 3v3. Hard ran Rescue on Depot and Freight Yard, seed 16 and 5v5. These nine matched missions exercise open firefights, multiple targets, path and corridor pressure, carrier/escort roles, and evacuation. Controlled checks cover deliberate Guard, a blocked carrier, and expiry. The timing sample is pooled across these cases and is not a per-difficulty budget.
- `work_us` sums uninterrupted main-thread elapsed intervals while the planner runs. It can include OS preemption and synchronous engine calls. `max_slice_us` is the longest such interval per submitted decision. `wall_us` includes planner frame suspension and excludes explicit pacing delays and the action window. Each activation additionally has a tail and total elapsed time. The action window begins after service validation and includes authoritative mutation, commit listeners, and presentation. The log reports validation, commit work before observers, and observers separately. When one actor extracts and the next starts during the window, the original activation retains that window through settlement.
- Stage timings are evidence for hotspots, with inclusive timings for nested path queries. They are not additive. Planner totals include unlabelled orchestration and action scoring around stage boundaries. `[AIPlanGoal]` remains the separate inclusive extraction-zone endpoint scan. Approach-path counts identify explicit queries, goal-path counts identify batched distance searches, and interception-path counts identify predicted route queries. The follow-up carrier probe counts ordinary, occupancy-aware, and friendly-yield route queries separately from the action sample as a whole. The inventory and plan counts are evaluated workload, not an exhaustive count of lower-level expansions.
- The profile flag enables the added clocks and log records. Legacy `[AIPlan]`, `[AIPlanGoal]`, `[AICommit]`, and `[AIAction]` outputs remain available. Replay data and combat and decision RNG are untouched. Terminal scene disposal can drop the final activation's profile, so profile samples and match decisions have separate denominators.

To reproduce either runtime after project import, use its own checkout and run the simulator once per argument group.

```powershell
godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- tag=step11-normal difficulty=NORMAL site=service_depot,freight_yard,fleet_station mission=ELIMINATE,ENEMY_EVACUATION seeds=17 players=3 enemies=3 profile-ai
godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- tag=step11-easy difficulty=EASY site=fleet_station mission=RESCUE seeds=17 players=3 enemies=3 profile-ai
godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- tag=step11-hard difficulty=HARD site=service_depot,freight_yard mission=RESCUE seeds=16 players=5 enemies=5 profile-ai
```

Save stdout/stderr per group. `tools/quality/ai_baseline_summary.py` accepts the match output directory and `--log <file>`. `tools/quality/ai_baseline_compare.py` compares decision order, rounds, final state, and outcome between equivalent groups. Compare before using the summary writer in the same input directory, or write the summaries to a separate directory.

## What changed

| Area | Prior cost or ambiguity | Review change |
| --- | --- | --- |
| Directional cover | Incoming threat evaluation looked up a hostile's directional cover even when its firing range excluded the destination. | The threat evaluation skips that unused read. Movement range, LOS, legal candidates, and score weights keep their existing rules. |
| Goal-distance search | Target distances were requested for Move inventory cells that the pre-existing corridor or escort filter would immediately reject. A far rejected endpoint could prolong a batched search. | Apply the same filter before collecting goal-distance requests. Retain the original filter and fallback behavior. Surface the route constraint in the trace. |
| Closed F3 | Every decision and outcome rebuilt the existing timeline even while it was hidden. | Store bounded history while closed and populate widgets on open. Render the live label only when shown. |
| Action truth | A Move could link to its commit, while many other explanations had no authoritative receipt. A failed Wait could disappear from the recorded outcomes. | Associate a pending selection with a matching actor and action. Link a post-action explanation to its matching latest transaction once. Keep unknown outcomes unpaired. Show actual AP and, where the result carries it, SP. Guard uses AP now and saves ammo for a valid reaction. |
| Historical context | Inspection mixed a previous decision with today's commitments. | The selected timeline row contains its own bounded destination, focus, corridor, and expiry context. The reservation overlay shows current commitments. |
| Rationale | Scores, policy filters, and legality could read as if they were on a single scale. Guard explanations lacked a concrete threat. | Timeline separates retained scored moves, policy-filtered moves, and unavailable shots. Guard names the threat and the actual firing-lane or range heuristic. A Wait retains its planner explanation plus any known execution rejection. |

F3 freezes the current inspection before pausing. Timeline navigation uses the existing trace records, including actor and faction, mission intent, movement profile, difficulty, commander, candidates, and recorded receipts. Each decision keeps at most 128 move and 32 target entries. The latest 80 decisions retain chosen and top-ranked options when lists must be shortened. Some decisions carry a short-plan summary instead of an exhaustive scored action list. The record also includes the best alternatives that the corresponding planner evaluated, when it produced those scores.

## Budget and limits

A 60 Hz frame offers 16.7 ms. On the reference desktop, target a planner work slice at or below 16.7 ms at P95, and investigate any synchronous slice above 33.3 ms. Aim for P95 decision wall latency within 150 ms so longer searches can yield and still feel responsive between actions. These are review targets for the measured setup. They are not a CI gate or a guarantee about the time left for rendering. Keep presentation and turn-pacing delays out of this budget. Retain an activation total excluding those delays to expose several individually acceptable decisions accumulating in one turn.

The largest remaining work is synchronous movement and goal search. In particular, one extraction-zone selection can try multiple endpoints in a single frame. Moving or splitting that work safely requires a reproducible expensive route, snapshot/revision safeguards, and matching behavior evidence. The current change does not add a cache, modify a candidate cap, change turn rules, or introduce a solver. The benchmark has no rendered frame-time distribution or heap instrumentation. Serialized history is a size sample rather than a measurement of live heap allocation. The publication timer covers receipt/record creation at the battle boundary and its listeners, so it is a useful combined cost rather than an isolated F3 CPU counter.

## Final measurements and evidence

Paired runs recorded 771 submitted decisions and 285 settled activations per runtime. All times below are milliseconds. P95/P99 use nearest rank.

| Interval | Reference mean / median | Review mean / median | Reference P95 / P99 | Review P95 / P99 | Reference max | Review max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Main-thread planner work | 51.71 / 55.43 | 47.12 / 49.54 | 119.76 / 162.92 | 111.77 / 156.21 | 226.02 | 216.98 |
| Longest work slice per decision | 35.74 / 28.96 | 32.34 / 25.47 | 91.76 / 133.92 | 83.02 / 123.34 | 221.62 | 216.98 |
| Wall latency per decision | 57.81 / 58.08 | 52.26 / 52.09 | 142.54 / 197.54 | 133.03 / 181.19 | 287.14 | 259.13 |
| Action window including presentation | 60.28 / 54.92 | 59.87 / 54.98 | 121.26 / 248.45 | 120.62 / 239.21 | 281.98 | 289.82 |
| Commit observers | 10.65 / 7.72 | 10.35 / 7.41 | 11.53 / 92.44 | 11.09 / 89.12 | 107.34 | 117.02 |
| Activation excluding action windows and pacing | 157.56 / 145.59 | 142.30 / 135.14 | 315.61 / 530.68 | 284.55 / 462.31 | 680.99 | 559.89 |

Mean planner work improved 8.9% and the P95 uninterrupted slice improved 9.5%. Planner yields fell from 1,873 to 1,804, with measured suspension falling from 4.71 to 3.96 seconds across the sample. The wall target held in the headless batch. The uninterrupted-work target remains open and needs rendered verification. One additional carrier diagnostic run observed a 227.73 ms worst slice on the same decision, illustrating runtime variance at the tail. Treat single-digit differences on an individual decision as timing observations.

| Observed work | Reference total | Review total | Workload |
| --- | ---: | ---: | --- |
| Goal searches | 9,057.4 ms | 7,169.2 ms | 491 → 490 measured planning passes. Review requested 9,447 cells after filtering. |
| Approach path queries | 6,486.7 ms | 6,344.6 ms | 2,618 in each run. These searches and carrier routes still dominate several single-frame spikes. |
| Position evaluation | 5,763.8 ms | 5,061.0 ms | 8,346 scored candidates in both runs. |
| Advance safety | 3,734.3 ms | 3,690.0 ms | 491 measured passes in each run. |
| Short plans | 3,019.8 ms | 2,942.8 ms | 4,013 recorded plan evaluations in each run. |
| Move inventory | 2,971.7 ms | 2,900.2 ms | 28,221 legal inventory entries in each run. |
| Validation before action | 2,958.2 ms | 2,881.7 ms | 771 observed submissions in each run. This is included in planner work. |
| Decision publication | 740.4 ms | 412.2 ms | 794 publications, about 0.93 → 0.52 ms each with F3 closed. |
| Evacuation interception | 29.3 ms | 29.3 ms | 56 checks and 32 route queries in both runs. Route-query time was 24.4 → 24.6 ms inside this inclusive interval. |

### Representative transactions

| Scenario | Reference → review longest slice | What the trace showed |
| --- | ---: | --- |
| Freight Yard Elimination, PlayerUnit1 attack #20 | 8.21 → 8.08 ms | An ordinary attack spends work on authoritative attack inventory, target scores, short plans, and service validation. |
| Freight Yard Elimination, EnemyUnit1 Guard #29 | 32.45 → 27.81 ms | The planner considered a safe advance first. Safety consumed 50.42 ms across several slices; the Guard submission itself was under 0.1 ms. |
| Freight Yard Elimination, PlayerUnit2 Wait #60 | 31.97 → 22.63 ms | The planner checked alternatives before waiting. Position scoring still consumed 24.68 ms across slices. Decision wall latency fell from 79.67 to 48.10 ms. |
| Freight Yard Rescue, PlayerUnit4 move #11 | 165.14 → 158.95 ms | Approach path work alone was 108.04 ms. Goal search fell from 31.75 to 27.19 ms. |
| Service Depot Enemy Evacuation, EnemyUnit1 move #11 | 162.18 → 150.53 ms | Selecting a reachable extraction endpoint took 83.78 ms in a synchronous scan. Player-side interception analysis was comparatively small. |
| Service Depot Rescue, PlayerUnit2 carrier move #40 | 221.62 → 216.98 ms | The dedicated follow-up reproduced the choice and attributed 193.61 ms to four carrier path queries within a 227.73 ms slice. Goal-field work added 25.78 ms. |

### Tactical parity

Nine of nine missions finished in both runs, with six victories and three defeats. Across all 821 decision records, the action/actor/subject sequences matched. The 800 committed actions also matched by actor, action, transaction, and state revisions. Per-round HP, alive actors, and objectives matched after removing elapsed time from the comparison. Final-state fingerprints, rounds and outcomes matched. Freight Yard seed-17 evacuation ended in a victory; the other two sites recorded an enemy escape. Neither the move filter nor difficulty and commander policy was retuned.

F3 now reports one rejected Wait that the old recorder omitted. In Fleet Station Rescue on Easy, PlayerUnit1 tried to Wait while PlayerUnit2's extraction still owned the action window. A temporary observer on the reference runtime independently captured the same `action_busy` result at revision 93. The paired run kept the same subsequent moves and final state. Fixing turn scheduling is outside this pass. The profiler now retains that extraction window against its original actor, and a deterministic service test checks ownership through the handoff.

### Verification and evidence

| Check | Result | Time / local evidence |
| --- | --- | --- |
| Catalog validation | 304 scripts and entries, 37 explicit-only, 107 FAST, 27 SMOKE | `tools/run_tests.ps1 check` |
| Initial focused run | Records, visualization, carrier reservation, and import passed | 27.99 s · `artifacts/test-results/20261124-230500-select/` |
| Cross-boundary selection | 16 of 17 passed, including action service, battle/rescue/traversal replay, AI determinism, scene lifetime, doctrine, hard constraints, carrier support, commitment expiry, and evacuation. The new Guard receipt assertion failed. | 188.79 s · `artifacts/test-results/20261124-230941-select/` |
| Guard receipt and action-window handoff rerun | 4 passed, including the corrected Guard and Wait scenarios, timer partitioning, fixture purity, and the action service. The Guard link now uses the latest transaction ID because turn transitions can change the state revision after a real commit. | 47.67 s · `artifacts/test-results/20261124-231728-select/` |
| Ironclad smoke | 27 tests and project import passed, no skips | 105.45 s · `artifacts/test-results/20261124-231928-smoke/` |
| Final F3 selection | 3 passed. Checks include history cap, retained choice, receipt correspondence, preservation of AP, SP, both RNG streams and tactical revision, and selection continuity when reopened. | 12.37 s · `artifacts/test-results/20261124-232127-select/` |
| Rendered F3 | 35 assertions, zero failures at 1280×720 with OpenGL compatibility. The selected Attack and its target alternatives are visible together with the authoritative AP/SP receipt. | `artifacts/step11-f3/stdout-final.log` and `artifacts/step11-f3/3-timeline-details.png` |

The fixture's four real decisions serialized to 78,584 bytes. A synthetic high-count test exercises retention rather than extrapolating that sample into a heap bound. Rendered captures also show [movement and heatmap](../../artifacts/step11-f3/1-move-arrow-and-heatmap.png), [target lines](../../artifacts/step11-f3/2-target-lines.png), and [reservations](../../artifacts/step11-f3/4-reservations.png). The captured inspection snapshot reported 0.68 ms to build, separate from AI planning. The captures are local, ignored artifacts. To regenerate them on a desktop with a display:

```powershell
$captures = (New-Item -ItemType Directory -Force artifacts/step11-f3).FullName
godot_console --path . --resolution 1280x720 --rendering-method gl_compatibility --log-file "$captures/engine.log" --script res://tests/ai_decision_visualization_test.gd -- capture "$captures"
```

Raw profile logs are `artifacts/step11-reference-*.log`, `artifacts/step11-review-*.log`, and `artifacts/step11-carrier-profile.log`. Match JSON is under `artifacts/ai-baseline/step11-reference-*` and `artifacts/ai-baseline/step11-review-*`. The reference Wait probe is `artifacts/step11-wait-control.log`. No script/parser errors appeared in the final benchmark or rendered logs. The desktop still emitted its root-certificate warning and the headless simulator could not write its default user log. The redirected test and simulator logs remained available. The full suite, the full mission matrix, and in-battle rendered frame-time profiling were outside this selection.

Implementation commit `e16cf727a40ba6ca70a6786f8dcf64b424fd2a5d` follows the profiling reference commit listed above. Review recommendation: integrate the behavior-preserving optimization and F3 changes after review, with the carrier-route slice recorded as an open performance item. The next optimization should use the measured Depot Rescue case to evaluate safely sharing or time-slicing occupied-route search while preserving route revalidation and exact commitments.
