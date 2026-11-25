# AI planning responsiveness — occupied paths and carrier routing

[Issue #4](https://github.com/Melo9002/fusefire-proving-grounds/issues/4) · [Architecture research](../ai-architecture/performance.md) · [Step 12 baseline](ai-step12-acceptance-2026-11-25.md#carrier-routing)

Review base `a69b744`, the merge of the architecture report. Runtime candidate `0088a365bc2315be759fd9693a9b7e36268a1318`. The tactical geometry and profiling source at the review base match the post-milestone research baseline. The Step 12 exact-edge scratch cache already existed here.

## What caused the stalls

Occupied endpoint searches did expensive work synchronously. In Depot Rescue transaction 40, four carrier endpoint queries took about 90–93 ms, followed by a 23 ms reverse goal field. The controller only checked its time budget between position candidates. In ordinary ally movement, transaction 16 was worse: 149 ms in one slice, with about 93 ms in approach paths alone. Terrain geometry changes the actual path inside a logical edge, so repeating the body sweep at every visit carries a cost even when an occupant is nowhere near that edge.

## Implementation and correctness

- [Surface navigation](../../systems/grid/surface_navigation.gd) retains canonical partial-cell standing points and exact swept body geometry. For a stable batch, collect blocking positions once. All actual elbow, ladder and vault waypoints stay inside the XZ rectangle of their endpoints. A conservatively expanded rectangle can reject distant bodies before building the traversal route. Nearby cases still use the original sweep, including height and clearance. Missing occupancy-cell data falls back to the original check. The margin covers quantized route-cache coordinates.
- [Occupied paths and reachability](../../systems/grid/pathfinder.gd) reuse that check across queries with the same occupancy assumptions. The fallback keeps its ordered frontier scan, approximate tie rule and neighbor order. Packed ID-indexed estimates and open-membership remove repeated dictionary and array scans. The goal field indexes static XZ buckets by graph revision, uses the same nearby distance test and preserves the existing heap/settlement order.
- [The controller](../../units/ai_controller.gd) shares clearance across the strict neighbor-approach batch and yields between costly independent approach or carrier endpoint queries. The reverse goal field retains its heap, tentative costs and pending set across checkpoints during index construction or expansion. Targets, costs, destination order, scoring and commander rules are preserved.
- A route in flight captures current authority revision, graph and map identity, graph/LOS revisions, body dimensions, occupancy IDs and standing points, extraction cells, the subject's carrier/faction information and relevant squad reservations. The resume guard checks scene ancestry, activation and subject liveness, and waits while the battle is paused or the service is busy. A stale carrier/approach scan reruns with fresh inputs when still applicable. A cancelled goal field returns no partial output. Mandatory authority revalidation still happens after planning.
- [Regression controls](../../tests/ai_carrier_reservation_test.gd) relocate the exit during a forced yield, move a hostile onto the replacement exit, change the active actor, and queue the whole battle for disposal. They also verify no transaction or decision random draw occurs during the search. [Goal field tests](../../tests/ai_planning_clearance_cache_test.gd) compare exact budgeted and unbudgeted field maps, and reject a partial result on cancellation. [Partial-cell geometry tests](../../tests/surface_navigation_test.gd) place a body on a valid bent route where the direct chord would miss it.

The first exact work-reduction pass took the carrier slice from 121–125 ms to 70.35 ms. Scheduling across those same endpoint queries shortened it further. The longest individual carrier query in the first scheduled run was 15.88 ms, making a rewrite of native AStar and scripted fallback expansion unnecessary for this case. The reverse field can cross the budget on its own, so the change makes the actual heap search resumable. The cooperative threshold is 5 ms, checked at safe boundaries. A native endpoint query, individual expansion, visibility forecast, or authority observer can still cross it.

## Benchmark method

Windows, AMD Ryzen 5 5500 (12 logical processors), GeForce RTX 5060, official Godot 4.7.2. Headless harness uses 12× time scale; rendered capture uses actual 1× game speed, 1280×720, OpenGL compatibility and a 60 FPS cap. Runs were serialized. Rendered repetitions alternate exact baseline and implementation commits in one clean checkout. Capture excludes transactions 0–3 and compares common transactions 4–45. Raw stage spans are monotonic main-thread elapsed work, with yields excluded and authority/presentation separately timed. The process-frame interval includes other work in the frame. The snapshot records the latest transaction, so a transaction label associates a frame with action progress and does not assign all frame cost to planning.

### Headless planner timing

All values are milliseconds except yield counts. P95 uses nearest rank. Depot has 189 completed profile samples per run, Freight 131 across two missions, Fleet 86 across two. The simulator records terminal commits even when final activation profiling has already ended.

| Workload | Mean work before → after | P95 slice before → after | Worst slice before → after | P95 wall before → after | Suspension before → after |
| --- | ---: | ---: | ---: | ---: | ---: |
| Depot Rescue seed 16, Hard 5v5 plus ally, repeat 1 | 47.78 → 35.33 | 94.57 → 16.07 | 149.11 → 22.61 | 142.29 → 128.31 | 1,124.62 → 2,112.42 (478 → 864 yields) |
| Depot Rescue, repeat 2 | 47.55 → 35.57 | 93.06 → 16.08 | 148.26 → 22.75 | 137.01 → 121.67 | 1,155.02 → 2,174.43 (477 → 872 yields) |
| Freight Yard seed 17, Normal 3v3 Eliminate and Evacuation | 49.08 → 41.41 | 70.04 → 27.23 | 118.10 → 52.80 | 124.36 → 112.99 | 597.02 → 1,101.83 (396 → 700 yields) |
| Fleet Station seed 17, Normal 3v3 Eliminate and Evacuation | 51.08 → 42.08 | 73.35 → 31.48 | 101.73 → 46.97 | 108.22 → 96.94 | 301.40 → 767.77 (205 → 473 yields) |

Carrier transaction 40 still tested four endpoints and seven scored destinations in each run. The route stage took **90.29–93.46 → 47.53–47.61 ms**, and its longest resumed carrier query was **15.66–15.87 ms**. The whole decision changed from **121.26–124.97 ms without yielding** to **17.07–17.21 ms maximum slice** across seven yields. The headless decision wall fell to **91.10–91.60 ms**. CPU-work attribution here measures elapsed main-thread work. Expansion counts and cache hit rates were not isolated in the runtime logs. Lower work with the same query counts is evidence for the combined exact changes; it does not isolate one algorithmic gain.

The ordinary AllyUnit1 approach at transaction 16 fell from **148.26–149.11** to **13.83–13.97 ms** maximum slice headless, and from **148.27–149.12** to **94.57–98.81 ms** wall. This was the worst baseline Depot planner decision. The remaining headless Depot peak near 23 ms came from a short attack reposition. Freight's 52.80 ms Wait and Fleet's 46.97 ms Move are still above the spike investigation threshold. Their largest recorded stage was candidate scoring. Maps with custom traversal links also retain per-candidate occupied path calls when the reverse field is unavailable. Multiple stage timers can span work across yields, so these rows do not determine the exact cost of a single score or fallback search. The seed-18 Depot Extract challenge produced a remaining 84.66 ms slice at PlayerUnit3 transaction 8. Its existing goal-selection log attributes 61.08 ms to the synchronous exit-zone scan and the profiled goal stage another 21.65 ms. The next bounded candidate is to schedule the remaining non-carrier zone scan with the measured endpoint mechanism and preserve its selection order. It is independent of the reproduced carrier improvement.

### Normal-speed rendered repeats

The comparison measures a common transaction 4–45 window. An early paired probe saved its screenshot at transaction 40. To remove GPU readback and PNG encoding from the timed interval, the table uses two replacement A/B pairs with capture deferred until transaction 46. The regular frame distribution and hitch counts come from the measured window. P95 and maximum planner numbers use the settled profile samples in that window.

| Run | Frames | Frame median / P95 / max (ms) | Frames above 33.3 / 50 / 100 ms | Transaction 40 max frame (ms) | Planner mean work / P95 slice / max slice (ms) | Decision wall P95 (ms) | Total planning suspension (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| baseline-1 | 3,321 | 16.66 / 16.79 / 166.46 | 35 / 29 / 13 | 136.62 | 69.54 / 121.23 / 150.85 | 129.00 | 155.61 (22 yields) |
| baseline-2 | 3,253 | 16.66 / 16.92 / 166.66 | 51 / 35 / 26 | 149.94 | 74.88 / 126.54 / 148.83 | 134.20 | 275.73 (23 yields) |
| candidate-1 | 3,579 | 16.67 / 16.77 / 31.64 | 0 / 0 / 0 | 16.77 | 39.32 / 13.73 / 16.78 | 140.76 | 2164.49 (218 yields) |
| candidate-2 | 3,579 | 16.66 / 16.77 / 30.76 | 0 / 0 / 0 | 17.79 | 42.14 / 14.38 / 17.00 | 161.07 | 2251.45 (230 yields) |

Across the two clean pairs, the worst observed process-frame interval fell from **166.46–166.66 ms to 30.76–31.64 ms**, and the number of intervals over 33.3 ms fell from **86 to zero** across the common transaction windows. Transaction 40's own longest planner slice fell from **121.23–125.09 ms to 16.78–17.00 ms**, with window-labeled frame intervals falling from **136.62–149.94 ms to 16.77–17.79 ms**. This does not assign the start of a multi-frame decision solely to the interval labeled with its commit. Most rendered frames were already near the 60 FPS cap. Scheduling adds planning suspension, and the rendered P95 decision wall was 140.76 ms and 161.07 ms in the two candidate runs. The match had reached transaction 57 by the end of both candidate samples, versus 58 and 57 on baseline.

The fixed-duration probe may report Timeout/Ongoing once the captured window has ended. Battle completion and legality are checked in the separate headless simulations. The rendered sample was automated at normal speed. It does not establish a frame guarantee or replace a human playtest. Raw captures and logs are in `artifacts/ai-latency/clean-*`. The earlier `matched-*` captures remain available as diagnostic controls.


## Behavioral parity

The two Depot repeats and four matched Freight/Fleet missions reproduced **all six actor/action/subject decision sequences**, all **614 committed action receipts** (including actors, action, transactions, revisions and AP/SP fields), round-sampled progress and final simulation signatures. There were zero recorded rejections. Depot completed in defeat twice, Freight won both missions, Fleet won Eliminate and lost Evacuation. The additional seed-18 Depot Extract, Rescue and Terminal missions all completed in victory with the original conditions. Those runs exercise mission logic and do not establish victory-rate changes.

Two further repeated missions matched full decision records and authoritative receipts within the candidate. Their saved replay JSON also matched the Step 12 records in full, including the exact cell paths, standing points, reaction events, attack rolls, committed revisions and every expected state fingerprint. The two recordings replayed all 186 events with zero divergence. A direct service observer saw zero rejected submissions. The recordings and driver are under `artifacts/ai-latency/`.

- [LatencyRepeat] fleet-rescue identical=true decisions=91 commits=89 result=1
- [LatencyRepeat] freight-evacuation identical=true decisions=63 commits=64 result=1
- [LatencyReplay] fleet-rescue verified=true events=110 divergence=
- [LatencyReplay] freight-evacuation verified=true events=76 divergence=

## Verification, limitations and recommendation

The complete ordinary Ironclad run finished **RED**, with **266 passes**, **1 failure**, and a passing project import. 267 tests completed. There were 0 timeouts, 0 blocked or unstarted tests, 0 retries, and 37 explicit-only exclusions. Total time was 3,087.83 seconds. Artifacts are under `artifacts/ai-latency/full/20261125-173256826-ede935f0-full/`. Per-test logs and machine-readable results remain there.

The focused clearance, surface geometry, diagonal movement, carrier reservation and action-service selection also passed. The sole full-run failure was the inherited MIRA descent gate in `ladder_landing_test`, which reported four failures out of 216 checks. The 120.1–121.9 mm diagnostic envelopes overlap the range independently reproduced before this branch. The integrated baseline has the same ladder presentation and test as the earlier forensics. [Ironclad failure forensics](ironclad-failure-forensics-2026-11-25.md) · [Issue #64](https://github.com/Melo9002/fusefire-proving-grounds/issues/64)

Keep [#4](https://github.com/Melo9002/fusefire-proving-grounds/issues/4) open. This change materially reduces the supported-point carrier hitch and common approach stalls. Broader maps and the Dense Depot Extract challenge still show spikes above 33.3 ms. The 16.7 ms P95 longest-slice and 150 ms P95 decision-wall targets should be interpreted per workload. The targeted Depot headless runs met both, while the broader headless slice distributions still missed 16.7 ms. Review this implementation independently of the remaining non-carrier exit scan and per-candidate scoring costs.

Compiled tactical geometry, scoring and replay formats stay on the existing contracts. No whole-battle responsiveness guarantee is inferred from the timed window. The raw logs under `artifacts/ai-latency/`, captured simulations under `artifacts/ai-baseline/latency-*`, and the exact probe below give the next investigation a reproducible baseline.

## Reproduce

Run in the project root on the exact baseline and candidate with an imported project and an isolated writable Windows user-data directory. Substitute distinct tags and log paths.

~~~powershell
godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- tag=latency-sample site=service_depot mission=RESCUE seeds=16 players=5 enemies=5 difficulty=HARD profile-ai
godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- tag=latency-freight site=freight_yard mission=ELIMINATE,ENEMY_EVACUATION seeds=17 players=3 enemies=3 difficulty=NORMAL profile-ai
godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- tag=latency-fleet site=fleet_station mission=ELIMINATE,ENEMY_EVACUATION seeds=17 players=3 enemies=3 difficulty=NORMAL profile-ai
python tools/quality/ai_baseline_compare.py artifacts/ai-baseline/latency-base-1 artifacts/ai-baseline/latency-candidate-1
./tools/run_tests.ps1 select -Test ai_carrier_reservation_test,ai_planning_clearance_cache_test,surface_navigation_test,diagonal_movement_test,tactical_action_service_test
./tools/run_tests.ps1 full -Import -LogDirectory artifacts/ai-latency/full
~~~

Save the rendered capture driver below as `artifacts/ai-latency/compare_clean_render.gd`.

~~~powershell
godot_console --path . --resolution 1280x720 --max-fps 60 --rendering-method gl_compatibility --script res://artifacts/ai-latency/compare_clean_render.gd -- profile-ai
~~~

<details>
<summary>Rendered capture driver</summary>

~~~gdscript
extends SceneTree

var simulator: AIMatchSimulator
var previous_tick := 0
var per_transaction := {}
var last_transaction := 0
var intervals: Array[float] = []
var worst: Array[Dictionary] = []
var capture_started := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	Engine.time_scale = 1.0
	simulator = AIMatchSimulator.new()
	root.add_child(simulator)
	process_frame.connect(_sample)
	var result := await simulator.run_match({
		"seed": 16, "battlefield_id": BattlefieldCatalog.SERVICE_DEPOT,
		"map_size": Vector2i(40, 40), "mission_kind": MissionObjectiveDefinition.Kind.RESCUE,
		"difficulty": AIDifficultyPolicy.Tier.HARD, "player_count": 5, "enemy_count": 5, "ally_count": 1,
		"timeout_seconds": 75.0, "stall_seconds": 15.0, "maximum_rounds": 30,
	})
	intervals.sort()
	if not intervals.is_empty():
		print("[RenderedFrames] ", JSON.stringify({"count": intervals.size(), "median_ms": intervals[intervals.size() / 2],
			"p95_ms": intervals[ceili(intervals.size() * 0.95) - 1], "max_ms": intervals.back(), "worst": worst, "max_by_transaction": per_transaction, "reached": last_transaction,
			"over_33_ms": intervals.filter(func(ms: float) -> bool: return ms > 33.3).size(),
			"over_50_ms": intervals.filter(func(ms: float) -> bool: return ms > 50.0).size(),
			"over_100_ms": intervals.filter(func(ms: float) -> bool: return ms > 100.0).size()}))
	print("[RenderedResult] ", result.summary())
	quit(0 if capture_started and last_transaction >= 45 else 1)

func _sample() -> void:
	if simulator.get_child_count() == 0:
		return
	var level := simulator.get_child(0) as BattleLevel
	if not is_instance_valid(level) or level.turn_manager.current_round <= 0:
		return
	var service := level.battle_controller.action_service
	var now := Time.get_ticks_usec()
	var transaction := service.last_transaction_id
	last_transaction = transaction
	if previous_tick > 0 and transaction >= 4 and transaction <= 45:
		var interval := float(now - previous_tick) / 1000.0
		intervals.append(interval)
		per_transaction[transaction] = maxf(per_transaction.get(transaction, 0.0), interval)
		if worst.size() < 10 or interval > worst.back().ms:
			worst.append({"ms": interval, "last_transaction": service.last_transaction_id, "busy": service.is_busy})
			worst.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ms > b.ms)
			if worst.size() > 10:
				worst.pop_back()
	previous_tick = now
	if not capture_started and service.last_transaction_id >= 46:
		capture_started = true
		_capture.call_deferred()

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("res://artifacts/ai-latency/capture.png")
	print("[RenderedCapture] ", error)
~~~

</details>
