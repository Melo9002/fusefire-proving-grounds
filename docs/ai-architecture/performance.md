# AI performance and frame scheduling

[Architecture index](README.md) · [Temporal diagram](diagrams.md#e--frame-timing-and-ownership) · [Health assessment](assessment.md) · [Measured excerpts](evidence/samples.json) · [Tracking #4](https://github.com/Melo9002/fusefire-proving-grounds/issues/4)

## What blocks a frame

The controller is a coroutine running on the main thread. It yields around the activation delay, busy/pause wait, action presentation and post-attack pacing. Its movement loops check a 5 ms threshold **between candidates**, then resume on `process_frame` and validate actor, state revision and occupancy. An entire legal inventory, carrier exit scan, reverse goal field, one expensive candidate, final validation, synchronous commit or commit observer can still run between those checks. Native AStar and GDScript are both synchronous here. A coroutine cannot preempt a function that never yields. The next actor can be selected inside extraction's commit, but its planning waits for the prior window to close.

| Clock | Meaning |
| --- | --- |
| Work | Running main-thread elapsed time before submitting an action. This includes native calls, allocation and any scheduler interruption during the slice. It is an elapsed-work proxy, not OS CPU accounting. |
| Maximum slice | Longest recorded uninterrupted work segment preceding that submission. A frame can also include validation, commit, observers, UI, physics and rendering work outside the slice. |
| Decision wall | Work plus planning suspensions, with explicit pacing and completed action windows excluded by profile bookkeeping. |
| Yield time | Suspension credited to a planning yield. More yields may improve frame responsiveness and increase total decision wall time. |
| Action window | Busy from service admission to release. It includes synchronous rules and observers as well as asynchronous presentation. Commit core and observers are separately measured. |
| Activation | Actor's overall profiled interval, with action-window and pacing totals available. Terminal teardown can drop a final activation sample. |

Sources: [AIActivationProfile](../../systems/ai/ai_activation_profile.gd) `_close_slice`, `resume`, `begin_action`, `end_action`; [AIController](../../units/ai_controller.gd) `_await_action_window`, `_carrier_route`, `_move_along_goal_path`, `_best_reposition_plan`; [TacticalActionService](../../systems/actions/runtime/tactical_action_service.gd) `_set_busy`, `_publish_commit`.

## Measurements on integrated main

Godot 4.7.2 on Windows, AMD Ryzen 5 5500 with 12 logical processors. Headless simulations ran serially with the baseline harness's time scale 12 and profiling enabled. Each is one complete match and both sides use the same difficulty. Percentiles use nearest rank. These are within-run distributions across decisions, not repeat-run confidence intervals. The 61–189 samples per match support a descriptive P95. Collect more comparable runs before treating a P99 or worst as a stable budget. Tests and optional outputs do not count as planning samples.

| Site and mission | Profiled decisions / activations | Work mean / median | Slice P95 / max | Wall P95 / max | Action window median |
| --- | ---: | ---: | ---: | ---: | ---: |
| Depot Rescue, Hard seed 16, 5v5 plus ally | 189 / 71 | 49.70 / 41.71 ms | 96.63 / 150.55 ms | 158.80 / 245.51 ms | 82.35 ms |
| Freight Evacuation, Normal seed 17, 3v3 | 61 / 22 | 61.97 / 63.58 ms | 79.60 / 123.48 ms | 167.91 / 232.36 ms | 88.89 ms |
| Freight Eliminate, Normal seed 17, 3v3 | 70 / 25 | 43.62 / 52.05 ms | 70.16 / 74.62 ms | 101.37 / 110.07 ms | 93.55 ms |

Examples from actual submitted decisions:

- **Depot Rescue transaction 40.** Four route queries consumed 89.685 ms of the 121.139 ms uninterrupted headless decision. The single reverse goal field consumed 23.371 ms, legal move inventory 2.289 ms, position scoring 0.199 ms for seven scored cells, and submit validation 2.372 ms. This decision never yielded. Carrier routing and goal field account for about 93% of its planner work. The action window took another 88.709 ms including synchronous commit observers (7.884 ms).
- **Freight Evacuation transaction 38.** The selected interception Move had a 42.150 ms maximum headless slice. Its follow-up Attack used 2.932 ms. Allocating more CPU to the intercept itself is unwarranted without finer evidence. The path to the goal and the ordinary move engine remain part of this chain.
- **Freight Eliminate.** Attack 20 used an 8.049 ms slice. Reposition Move 36 used 18.227 ms. Wait 60 still used a 29.511 ms maximum pre-submit slice because earlier branches had to rule out useful movement. The final Wait action does not explain that cost.

### Rendered normal-speed sample

The same Depot Rescue fixture ran at 1×, 1280×720, OpenGL compatibility on a GeForce RTX 5060, capped at 60 FPS. The probe sampled 4,000 process-frame intervals. Median **16.665 ms**, P95 **16.822 ms**. Transaction 40 was reached. The planner's uninterrupted slice was **133.208 ms** (carrier exit scan **100.048 ms**, goal field **24.430 ms**, zero yields). A frame interval observed beside transaction 40 was **149.306 ms**. The separate window for the committed move lasted **1,152.729 ms** including presentation. Sampling associates an interval with the latest transaction ID and busy flag. It does not isolate that transaction as the only cause of a frame. The run timed out after about 75 seconds at round 2. It verifies the motion interval and capture, while the headless simulation verifies match completion.

The overall maximum was a 4,808.758 ms startup interval before the first transaction. It is retained in the raw sample and should be excluded from a future matched steady-state distribution. Other busy intervals around transactions 30–32 exceeded 200 ms and remain unattributed. The prior Step 12 render observed 135.96 ms at the carrier move. This follow-up reproduces the responsiveness problem. Timing differences between individual runs are not change estimates.

### Prior paired comparisons and budget

[Step 11](../quality/ai-step11-profiling-f3-2026-11-24.md) measured 771 submitted decisions in nine matched missions per build. Its major aggregate stages were reverse/other goal searches (7,169.2 ms in review), approach queries (6,344.6 ms), position evaluation (5,061.0 ms), advance safety (3,690.0 ms), and short plans (2,942.8 ms). Inclusive and nested timers, such as carrier routes measured within squad setup, must not be summed as independent cost. The profiler records work in the actual planner. It does not replay it to benchmark.

[Step 12](../quality/ai-step12-acceptance-2026-11-25.md#carrier-routing) measured 221.21 → 131.23 ms on transaction 40 after sharing scratch swept-edge results across four searches, with matched decisions and authoritative commits. At the recent 133.208 ms rendered sample, removing all carrier-route time would still leave approximately **33 ms** of planner work. That arithmetic is a hotspot bound for this sample, not a measured optimization. Goal-field work and final validation need their own attribution after fixing the largest slice.

The established review targets are **16.7 ms P95 longest slice**, investigate spikes above **33.3 ms**, and **150 ms P95 decision wall**. All three fresh headless samples miss the slice target. The Rescue and Evacuation samples miss the wall target. The rendered carrier spike misses the investigation threshold. The engine's normal frame budget is shared with other work. A chosen planning slice budget must leave measured headroom for that work.

## Invalidation and preparation

| Work | Current guard | Safe boundary for a future experiment |
| --- | --- | --- |
| Static graph topology, traversal links and longest-edge bound | `Pathfinder.graph_revision()` changes on graph edits, and the goal-field edge-radius bound caches against it. | Build stable adjacency, edge metadata or a conservative broad phase outside activations. Invalidate it on graph/geometry changes and battle identity. Do not retain old scene nodes. |
| Standing points and swept-body clearance | `calculate_path_with_occupancy` validates a scratch signature including graph, grid and map identity, body settings and occupants/points. The carrier live-edge cache relies on one synchronous scan with one ignored actor. | Treat an occupied search as scoped to actor, occupancy, resolved geometry and traversal options. Separate strict and friendly-yield searches. Invalidate on movement, registration/removal including defeat/extract, point changes, or stance/body inputs used by the query. Do not carry the current synchronous scratch unchecked across frame yields. |
| Committed carrier route and objective endpoint | Controller checks graph revision, carrier origin and endpoint membership, then rechecks live clearance. Squad context trims or releases its corridor on refresh. | Path work can reuse a stable graph and a valid suffix. Candidate ranking and corridor publication must recheck casualty state, exit set, team claims and current active actor. An ignored ally in a yield search never becomes permission to move through it. |
| Move eligibility and tactical reservations | The planner's hard vetoes and legal action inventory are separate. The existing planning snapshot checks service revision and occupancy. | A new continuation should explicitly test graph/zone state, planner-relevant squad changes, actor lifetime and pause. Existing snapshot fields do not independently encode all of those. A geometry-only query need not discard on an unrelated AP spend if its actual input geometry stays valid. |
| Cover, LOS, Aim, Shield, firing forecasts and Guard | [BattleController](../../systems/battle_controller.gd) keys its shot-cell cache by map/LOS revision, graph and combat inputs. Other forecasts read live actors and map. | Reuse static ray information only where geometry is truly identical. Exposure/forecast results require pose, cover, weapon, range, stance and effect state as relevant. Resources, Guard triggers and combat predictions must be refreshed before submitting. |
| Full proposed action | Service request carries expected revision, then revalidates the live window, actor and action rules. | Always submit to the same authority. Incomplete work cannot consume gameplay RNG, reserve a speculative tile, advance turn, or commit. Discard stale work with no gameplay side effect. |

## Ranked experiments

| Order and class | Experiment and benefit | Complexity, risk and test |
| --- | --- | --- |
| 1 · C | **Make occupied carrier work resumable.** First capture per-endpoint native path, fallback expansions, swept edges, cache hits and allocation costs. Measure a yield between independent endpoint evaluations only if each is short enough. Split the scripted fallback by deterministic expansion order if one search dominates. This targets a measured 90–100 ms stage. Redistribution can reduce the worst frame while leaving CPU unchanged or slightly higher. | Medium. Preserve queue order, current tie breaks and winning endpoint. Keep scratch local to a validated continuation. Match route cells and costs on exact, alternate, impossible, crowded and topology-changing fixtures. Add cancellation across yield for move, death, changed exit, mode switch and teardown. Then compare receipts, RNG, replay and matched rendered frame intervals. |
| 2 · C | **Reduce work in fallback and reverse goal field.** Measure array frontier scan/shift work first, then consider deterministic priority-queue parity. The reverse field already uses a heap and stops once it settles requested cells. It still scans graph points for nearby bodies and can spend ~24 ms synchronously in the trace. An exact edge broad phase and earlier safe endpoint rejection could reduce work. | Medium. Approximate tie comparisons in the fallback complicate heap substitution. Require path or decision parity and obstacle occupancy results. Use a provable lower bound or equivalent cost calculation before pruning any endpoint. Existing carrier selection uses path point count, which is a different metric from weighted route cost. |
| 3 · C | **Reuse identical queries within one decision or stable revision.** Measure repeated shoulder/current threat, Guard validation, move inventories and endpoint cases by input fingerprint. `BattleController._query_move_data` rebuilds the full inventory for a single destination, then builds the route and visual segments. Time the targeted validation pieces before deciding whether a cheaper query can preserve the same checks and error semantics. Move/hypothetical views differ intentionally. Existing Step 12 edge reuse gives a measured precedent. | Low to medium for isolated pure inputs. Mandatory final validation is kept. Check equipment/resources, map/LOS and occupancy invalidation, especially relations to squad claims. |
| 4 · B | **Consolidate route-selection evidence and receipt publication.** Create a small internal lifetime for a chosen candidate/receipt with pre-submit facts. Use the tracked terminal/fresh divergences to characterize scope. Restrict claimed coverage to actually measured F3 performance. | Medium for wrapping combat publication. Keep authoritative listeners, replay and decisions stable. Add terminating Attack and stale candidate controls. |
| 5 · D | **Try opportunistic precomputation only for stable inputs.** Static topology broad phase or revision-keyed reusable fields can prepare while presentation has slack. Time-slice it, or it can hitch animation anyway. Final Move/Attack decisions should occur after the preceding action's consequences and clear window. | Useful only if trace shows stable inputs and real worker-free headroom. Low risk for static map data, higher for speculative next-actor state. Count cancellation/discard ratios and additional CPU. |
| 6 · D | **Evaluate detached workers or incremental reuse across revisions only after simpler gains.** A worker would need an immutable value graph, deterministic ordering and a validated result handoff. Incremental path repair can help stable repeated goals across sparse changes, and has setup cost on changing endpoints. | High. Directly using live scene nodes or shared `AStar3D` across threads is outside Godot's documented contracts. Require evidence of remaining benefit and compare frame budget, CPU usage, memory and determinism before expanding. See [Godot thread-safe APIs](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html) and [D* Lite](https://publications.ri.cmu.edu/d-lite). |

Run optimization A/B on the same renderer, cap, host and revision, with warm-up separately reported, at least several matched repeats, and capture p95 and near-tail interval samples rather than a lone maximum. Report profile-on/off overhead and the first behavioral divergence. An approved experiment should preserve exact legal results and seeded traces on unchanged inputs, and avoid changing map outcomes merely by pruning options.

## Reproduce the evidence

From the project root with an imported cache, run these commands serially. Create a writable isolated profile for direct Godot launches, or use the existing Ironclad isolation for tests. These commands enable both sides' AI.

~~~powershell
$dir = (New-Item -ItemType Directory -Force artifacts/ai-architecture-research).FullName
godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- tag=arch-carrier site=service_depot mission=RESCUE seeds=16 players=5 enemies=5 difficulty=HARD profile-ai *> "$dir/carrier.log"
godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- tag=arch-evacuation site=freight_yard mission=ENEMY_EVACUATION seeds=17 players=3 enemies=3 difficulty=NORMAL profile-ai *> "$dir/evacuation.log"
godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- tag=arch-combat site=freight_yard mission=ELIMINATE seeds=17 players=3 enemies=3 difficulty=NORMAL profile-ai *> "$dir/combat.log"
~~~

The harness writes the complete JSON to `artifacts/ai-baseline/arch-*`. Timings come from `[AIActivation]` rows keyed to service transaction IDs. [Rendered probe reproduction](evidence/rendered-probe.md) uses real process-frame intervals. [Selected evidence](evidence/samples.json) preserves relevant counts, profile and decision rows with the largest candidate lists reduced to examples.

## Verification and open questions

- The three fresh headless battles completed with 192, 64 and 73 committed actions and zero observed rejections. Against the matching Step 12 traces, their configurations, committed receipt sequences by actor/action/transaction/revisions, outcomes, rounds and final simulation signatures matched. Rescue choice sequences matched. Evacuation and Eliminate each omitted a single final Attack **explanation** on the fresh run. The unchanged authoritative receipt and the earlier terminal-teardown finding explain the distinction.
- Seven Ironclad tests passed in 85.36 seconds using the existing cache. Selection covered decision scenarios, occupancy scratch, scene lifetime, F3, AI match determinism, battle replay and squad commitments. Search parser/runtime errors separately from numeric exit status. Full Ironclad, explicit capture sweeps, a Fleet Station performance rerun, hardware scaling, allocator profiling, and human play were outside this pass.
- All seven Mermaid blocks rendered to SVG using Mermaid CLI 11.12.0 with headless Edge. Relative paths and document heading anchors were checked. Raw fresh logs, engine output and capture remain under `artifacts/ai-architecture-research/`. Timing limits remain estimates for these workloads. Before optimizing fallback priority queues, the most important missing evidence is per-search attribution and whether one query alone exceeds the frame budget. Before preparing actor-level work early, measure whether prediction survives reactions, actor removal, objective updates and repeated claim changes.
