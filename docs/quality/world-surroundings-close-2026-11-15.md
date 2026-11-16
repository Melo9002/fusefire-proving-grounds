# Roadmap 03 — World surroundings close

The prototype milestone is complete for **Service Depot, Freight Yard and Fleet Station**, including both accepted layouts of each. Battles now sit within continuing industrial surroundings, their playable limits remain explicit, and the same existing Generation 2 pipeline supplies tactical content. No scenery generator, streaming system or LOD framework was introduced.

## Delivered content and editing

Freight keeps its container/fleet aprons and gains a connected logistics compound: neighboring service buildings, container stacks, delivery vehicles and continuing service roads. Fleet keeps its north/south frontage and vehicle court, with neighboring offices, overflow parking and road-aligned boundary labels.

Both use the proven 640-unit ground, adjoining road strips, yellow 40 × 40 boundary, corner cones/short fence runs and six quiet low-detail background districts. The shared scenery pieces remain ordinary saved Godot scenes. The two new near scenes use existing calibrated reusable objects; their visual-only camera bounds rebuild through the existing occlusion helper.

The [everyday guide](../world-surroundings.md) now describes today's workflow and lists the five plot scenes, two new near scenes and shared boundary/backdrop pieces. Historical step reports are linked separately. Tactical parcels, movement, combat, missions and loading behavior were not redesigned in this step.

Freight and Fleet plot revisions increase from 1 to **2** because their surroundings changed. Old revision-1 recordings reject with `STALE_PLOT_REVISION`; they do not silently reconstruct different scenery. Depot remains revision 1. No replay-schema change or historical-art archive was added.

## Visual and camera review

- **60 final review views:** all three sites × seeds 16/17 × entry, overview, reverse, low, wide, three additional cardinal low views, high and high-wide. Every view was reviewed through six contact sheets. Ground supports the extended roads; near compounds read as adjoining yards; the low-detail skyline is visible at low/high angles; the yellow limit remains legible. The paving retains deliberately simple prototype shapes.
- The expanded camera check passed **288 orbit/zoom poses** (four headings × four pitches × three zooms × six layouts), bounded pan/recenter, live action framing and return, and saved replay playback in all three camera modes.
- The original Depot workshop/floor-inspection regression remains intact. Freight/Fleet additionally verify their saved neighboring offices fade during floor inspection and restore afterward.
- The rendered camera review saved **56 captures** with zero assertion failures. This supplements the 60-view visual review; it is not a claim of pixel-by-pixel inspection of every camera capture.
- **Six final live/replay pairs** were captured and reviewed. Each reconstructs the same surroundings and atmosphere. HUD and unit presentation differ appropriately; these are not identical full-screen pixel hashes.

Artifacts: `artifacts/world-rollout-final-views/`, `artifacts/world-rollout-camera-review/`, `artifacts/world-rollout-live-replay-final/`. The review tool saves camera transforms/FOVs in `views.json`.

## Tactical isolation and reconstruction

The existing four-edge regression now runs on all three sites: **24 edge cases, zero failures**. It retains legal inside movement/shot/picking controls, rejects off-map movement/targets/predicted firing cells and checks rejected submissions do not spend AP or alter HP/occupancy. Controlled extraction-zone queries run beside each edge. Normal deployment and transport placement are checked separately; the controlled queries do not simulate complete departures at all 24 locations.

The fixed-scenery check now covers **48 presentations**: three sites, seeds 16–23, population on/off. Scenery is stable within each recorded plot. A deliberate transform mutation changes its comparison and restoring the transform restores it. Freight deliberately shares its surroundings scene across two different parcel arrangements.

The ordinary mission/replay matrix remains **48 cases**: three sites × two layouts × eight mission kinds. All initialized with validated actor/mission/terminal/transport placements inside the tactical map and reconstructed matching accepted choices, surrounding geometry/materials/transforms and atmosphere after serialization. Each case verifies a committed Aim action, not a complete mission playthrough. Its explicit graphics capture mode now covers six Eliminate layouts instead of only Depot's two; no-argument coverage remains all 48.

The replay subsystem also completed existing full Freight and Fleet recordings: **69/69 actions to victory** and **47/47 to defeat**, respectively. These were generated against the current revision-2 content. They establish useful complete-playback coverage, not every mission/seed combination.

## Final scenery cost

Measured sequentially after the broader headless suites finished, with no concurrent diagnostic graphics process: Godot 4.7.2 debug executable, Windows, Forward+ / D3D12, Ryzen 5 5500, RTX 5060, approximately 16 GiB RAM, 1600 × 900, VSync off, uncapped. Every block reports a focused benchmark window.

The benchmark now covers all three sites, both layouts and normal/low/high-wide views. Three paired repetitions reverse visibility order, settle 120 frames and sample 600 frames per state: **108 blocks / 64,800 measured frames**. Timing methodology and limitations remain those of the [initial measurement](surroundings-cost-2026-11-15.md). Hidden resources stay allocated; static battle processing and camera updates are suspended to isolate scene rendering cost. This is not an AI-turn, animation or occlusion-CPU benchmark.

| Site | Authored scenery meshes / triangles | Largest added median GPU | Largest added median render CPU | Largest added p95 frame interval | Largest added draw calls |
| --- | ---: | ---: | ---: | ---: | ---: |
| Depot | 132 / 19,004–19,964 | 0.196 ms | 0.048 ms | 0.123 ms | 67 |
| Freight | 142 / 20,592 | 0.157 ms | 0.053 ms | 0.133 ms | 73 |
| Fleet | 150 / 21,496 | 0.180 ms | 0.057 ms | 0.226 ms | 67 |

All satisfy the existing content cap (160 meshes / 25,000 triangles / no extra lights) and reference-machine review thresholds (added median GPU 1 ms, render CPU 0.5 ms, p95 frame interval 2 ms, draw calls 80). The shared backdrop still has 42 meshes / 6,060 triangles and no shadows. These are bounded prototype budgets, not universal hardware or whole-game performance promises.

The first measurement found additions of **84 Freight / 94 Fleet draw calls**. Rather than raise the threshold, flat nearby paving/paint stopped casting unnecessary shadows and one redundant Fleet background truck was removed. The final comparison above remeasured all sites. The content test now protects shadow-free flat paving/paint on these new near scenes. No LOD or streaming was needed.

Full battle preparation through validated ready took about **0.63–1.05 seconds** in the final run; start through first rendered frame was approximately **1.00–4.26 seconds**. Resources are preloaded before the harness timer, and the first/subsequent battles have different cache states. These are not cold application startup or isolated scenery loading times. The unconditional loading screen remains appropriate.

The checked-in [measurement summary](world-surroundings-cost-2026-11-15.json) preserves setup, individual loading stages, warm construction/generation measurements and all 18 view/layout comparisons. Raw samples and 36 on/off screenshots are in `artifacts/world-rollout-cost-final/`; the first comparison is retained under `artifacts/world-rollout-cost/`.

## Verification and failure accounting

| Check | Result |
| --- | --- |
| Generation subsystem | 53 passed, 0 assertion/process failures, 7 explicit-only diagnostics skipped |
| Replay subsystem | 15 passed, 0 failed, 0 skipped |
| Final content budget / continuity / revision checks | Six layouts, zero failures |
| Final edge isolation / fixed scenery | 24 edge cases plus 48 presentations, zero failures |
| Final headless camera review | 288 orbit/zoom poses plus live/replay/floor checks, zero failures |
| Rendered camera review | 288 poses, 56 captures, zero assertion failures |
| Final graphics mission/replay capture | Six cases, 12 captures, zero failures |
| Final review capture | 60 views, zero initialization/capture failures |
| Final cost comparison | 108 blocks, zero reported failures; all review thresholds met |
| Repaired compact battlefield regression | Focused rerun passed, including all three real actions through terminal victory |

The generation runner's green exit result initially concealed a **pre-existing defective test path** in `compact_battlefield_test.gd`. It looked for the range reference car before the plot/Tactical ownership layer and aborted the rest of its coroutine on a null access. Log review caught this. The path now follows `TacticalTestRangeSite/Tactical/TacticalTestRange`; missing nodes/geometry fail explicitly. Original aperture, tactical blocking, movement, terminal and victory assertions remain and executed in the passing focused rerun. The initial broad generation log therefore is not a clean no-script-error claim.

Initial new-test setup issues were also corrected: the generalized boundary test required an explicit boolean type, and the new road-support check incorrectly demanded vertical containment inside the thin ground mesh rather than containment of the road's horizontal footprint. Both corrected checks pass; no gameplay invariants or existing assertions were weakened.

Broad suites ran before the final scenery cost reduction. Final focused content, edge, camera, live/replay and rendered-view checks ran afterward. No full suite or exported-build test was run. Final focused/graphics/benchmark logs contain no script/parse errors or resource-leak warnings; certificate/user-log diagnostics remain environmental. Counts overlap and must not be summed as unique tests.

Suite logs: `artifacts/test-results/20261115-223420-subsystem-generation`, `artifacts/test-results/20261115-223421-subsystem-replay`. Focused evidence is under `artifacts/world-rollout-*.txt` / `*.log`.

## Reproduce

```powershell
godot_console --headless --path . --script res://tests/world_surroundings_rollout_test.gd
godot_console --headless --path . --script res://tests/world_tactical_isolation_test.gd
godot_console --headless --path . --script res://tests/depot_boundary_readability_test.gd
godot_console --headless --path . --script res://tests/depot_camera_readability_test.gd
godot_console --headless --path . --script res://tests/current_mission_replay_matrix_test.gd
godot_console --path . --script res://tools/environment_authoring/current_surroundings_capture.gd -- artifacts/surroundings-review
godot_console --path . --script res://tests/depot_camera_readability_test.gd -- capture artifacts/camera-review
godot_console --path . --script res://tests/current_mission_replay_matrix_test.gd -- capture artifacts/live-replay-review
godot_console --path . --script res://tools/environment_authoring/surroundings_cost.gd -- artifacts/surroundings-cost
```

Run the performance command separately from other diagnostic work. The older `depot_*` test filenames retain their original regressions and now also cover Freight/Fleet where stated. Ordinary generation/replay suites discover the expanded checks through the existing runner.

The milestone closes at this tested prototype boundary. Arbitrary future assets, unmeasured hardware, every possible camera pose and all missions across all seeds remain outside these results. More diverse scenery art can be authored later through the documented scenes; it does not require reopening generation architecture.
