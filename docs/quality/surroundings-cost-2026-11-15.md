# Surroundings cost and loading

Roadmap 03, step 8. Depot's current surroundings are inexpensive to render on the measured setup. Keep the present simple scenery; no LOD, streaming, asset reduction or generator changes are justified by these results. Loading remains visible regardless of map size, as requested.

## Repeatable setup

Windows, Godot 4.7.2 official debug executable, Forward+ / D3D12 12_0, Ryzen 5 5500, RTX 5060, approximately 16 GiB physical RAM. Viewport 1600 × 900, VSync disabled, uncapped. All recorded blocks report a focused window. This is one development machine, not a minimum-spec or exported-build result.

Seeds 16/17 exercise both Depot plots, population enabled, Eliminate mission, two players and two enemies. Normal, low and high-wide views use saved explicit transforms/FOVs in `tools/environment_authoring/surroundings_cost.gd`. For each view, three paired repetitions reverse on/off order, settle for 120 frames, then sample 600 frames per state: **36 blocks / 21,600 measured frames**.

The same battle stays instantiated; only Peripheral and Distant visibility changes. Tactical geometry, actors, HUD, lighting, resolution and camera stay fixed. The harness suspends battle processing to isolate static scene/rendering cost and verifies the tactical state fingerprint remains unchanged. These timings do not measure AI, action animation or active-turn performance. Camera occlusion updates are also suspended with the static camera; this is not an occlusion-processing benchmark.

Frame time is the wall interval between rendered-frame signals. CPU/GPU render times come from Godot's viewport measurements. The two are not interchangeable or additive. Draw calls/primitives/objects are Godot's total frame counters, including other rendering passes and HUD; they are not unique authored mesh counts.

## Measured frame cost

Each row combines 1,800 samples per state. Times are milliseconds; medians except the explicitly marked 95th percentile. Columns read **scenery off → on**.

| Seed / view | Frame median | Frame p95 | Render CPU median | Render GPU median | Draw calls | Rendered primitives |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 16 normal | 0.617 → 0.748 | 1.020 → 1.241 | 0.196 → 0.256 | 0.362 → 0.543 | 115 → 179 | 69,238 → 97,660 |
| 16 low | 0.718 → 0.762 | 1.153 → 1.594 | 0.213 → 0.250 | 0.467 → 0.604 | 120 → 177 | 75,286 → 98,982 |
| 16 high-wide | 0.575 → 0.658 | 0.852 → 1.042 | 0.184 → 0.222 | 0.142 → 0.329 | 78 → 105 | 26,423 → 44,427 |
| 17 normal | 0.605 → 0.734 | 0.898 → 1.142 | 0.193 → 0.246 | 0.360 → 0.556 | 118 → 185 | 71,461 → 102,847 |
| 17 low | 0.634 → 0.746 | 0.984 → 1.187 | 0.202 → 0.251 | 0.415 → 0.522 | 135 → 201 | 128,303 → 151,251 |
| 17 high-wide | 0.573 → 0.642 | 0.861 → 1.014 | 0.188 → 0.222 | 0.139 → 0.301 | 78 → 104 | 26,423 → 45,079 |

The largest paired median additions were approximately **0.20 ms GPU, 0.06 ms render CPU and 0.13 ms frame time**. The largest p95 frame addition was 0.44 ms. Driver scheduling and other desktop work introduce noise; use repeated paired results rather than individual frames.

Visible object counters range from 353–413 off and 489–578 on. Reported video-memory allocation was approximately 189.2 MiB for seed 16 and 189.7 MiB for seed 17, unchanged by visibility. This does **not** establish zero scenery memory cost: hidden resources remain allocated in both states. No unload/streaming memory comparison was performed.

## Generation and loading

| Measurement | Seed 16, first battle in process | Seed 17, subsequent battle |
| --- | ---: | ---: |
| Battle instantiated/configured through validated ready | 1,515.9 ms | 712.4 ms |
| Same start through first rendered battle frame | 6,552.9 ms | 1,134.0 ms |
| Warm tactical generation median, three repetitions | 105.3 ms | 87.4 ms |
| Isolated plot instantiation without surroundings, median of five | 0.001 ms | 0.002 ms |
| Isolated plot instantiation with surroundings, median of five | 0.562 ms | 1.164 ms |

The isolated plot comparison packs equivalent plot copies with the Tactical children removed, retaining/removing Peripheral and Distant. It measures warm-cache instantiation, excluding packing, scene-tree ready callbacks, shader preparation and freeing. It is evidence about construction cost, not a promise that disabling scenery shortens total loading by precisely that amount.

Generation has no scenery toggle because scenery belongs to presentation, not tactical generation. The same accepted data is used for on/off rendering. Full battle load measurements retain all content. Resource preloads happen before the harness timer, so these are not cold-disk, application-startup or complete click-to-battle measurements. The first-render delay warrants loading coverage; its exact CPU/driver/shader breakdown was not profiled, and a universal attribution would be speculative.

## Modest prototype budget

- **Content:** Peripheral + Distant together ≤160 mesh instances and ≤25,000 authored triangles per Depot plot; no extra lights. Actual: 132 meshes and 19,004/19,964 triangles. `depot_surroundings_test.gd` enforces these hardware-independent caps.
- **Distant detail:** retain the existing ≤60 meshes / ≤6,500 triangles / no shadows budget. Actual distant backdrop: 42 meshes / 6,060 triangles.
- **Reference-machine review thresholds:** investigate paired additions above 1 ms median GPU, 0.5 ms median render CPU, 2 ms p95 frame interval or 80 draw calls in these views. Current maximum draw-call addition is 67. These are manual comparison thresholds, not portable CI timing assertions or a whole-game frame budget.
- Keep loading visible from before heavy preparation through the first rendered frame. Re-measure after meaningful scenery, materials, lights, resolution or map-scale changes. Simplify the costly content first if a comparison exceeds the budget.

## Loading behavior

The existing opaque loading screen is reused for new matches, opened replay files, Parcel Editor test battles and result-screen rewatch. It draws on CanvasLayer 100 over the battle HUD. It renders before construction and remains until the initial battle frame has drawn; a process-frame yield alone did not guarantee either condition.

Editor and old-replay controls are suspended during the transition; repeated launches are ignored. Preparation keys are consumed. Real initialization stages supply the progress label/bar. The text uses ordinary language rather than internal tactical data terminology. Editor test loading no longer assumes preparation must finish within 240 frames.

Initialization errors remain actionable: setup retains its loading error and return button; failed rewatch retains the original battle, restores its camera, and offers Back to battle. Invalid editor content returns to the preserved editing session with its existing diagnostic. A loading screen does not prevent out-of-memory crashes or make synchronous construction threaded. The displayed frame can remain static during synchronous work; no fake animation, arbitrary timeout or unsafe background scene construction was added.

## Verification and reproduction

- Graphics benchmark: **36 blocks, zero reported failures**; final log has no script/parse errors. Twelve paired-view screenshots were saved; representative normal and high-wide pairs were inspected directly.
- New content budget: both Depot layouts passed. The existing distant cap remains unchanged.
- Loading regression: passed headlessly and rendered, including invalid setup and failed rewatch recovery. Those fixtures intentionally log `UNKNOWN_BATTLEFIELD` errors.
- Rendered editor → local battle → rewatch → editor handoff passed. Captures confirm opaque loading appears before editor construction and replay reconstruction, with no battle HUD drawn above it. Real Match Setup loading was also captured.
- UI subsystem: **25 passed, 0 failed, 1 explicit-only capture skipped** (`20261115-220931-subsystem-ui`).
- Replay subsystem: initially **14 passed, 1 failed, 0 skipped** (`20261115-220931-subsystem-replay`). The sole failure was an obsolete immediate-scene-replacement assertion after pressing Rewatch. The test now asserts loading appears, waits for the transition, and preserves its exact-file, atmosphere, pause/return and playback assertions. Its focused rerun passed with zero failures. An intermediate test-edit type-inference parse error was corrected before that passing rerun. The other 14 checks were not repeated without cause.
- No full-suite run was performed. Environment certificate/user-log diagnostics remain; no claim is made about every hardware configuration or full gameplay performance.

The compact checked-in [baseline](surroundings-cost-baseline-2026-11-15.json) preserves setup, loading stages and frame summaries. Raw samples and captures are ignored artifacts under `artifacts/surroundings-cost-20261115-measured/`; transition captures are under `artifacts/step8-loading-handoff/`.

```powershell
godot_console --path . --script res://tools/environment_authoring/surroundings_cost.gd -- artifacts/surroundings-cost
godot_console --headless --path . --script res://tests/depot_surroundings_test.gd
godot_console --headless --path . --script res://tests/battle_loading_screen_test.gd
godot_console --path . --script res://tests/battle_loading_screen_test.gd -- capture artifacts/loading-review
godot_console --path . --script res://tests/parcel_editor_handoff_test.gd -- capture artifacts/loading-review
```

Keep the benchmark window visible, avoid concurrent GPU work, and compare the same machine/settings. Its script intentionally lives outside automatic test discovery. Step 8 is complete for the representative Depot setup. The remaining roadmap work is the planned scenery rollout/review for other sites, not a new optimization framework.
