# Package 03B — Contextual firing on authored battlefields

[Package 03A checkpoint results](contextual-firing-03a.md) · [Service Depot incident](asymmetric-line-of-fire-investigation.md) · [Predictive feedback and truck correction](intelligent-cover-and-contextual-firing.md)

## Playable checkpoints

03A is recoverable at `79d9c71ec85244737473c1cdb411d04e031196ef` on `codex/asymmetric-line-of-fire`. The reference bay launch in the 03A report is still available. The ordinary Service Depot and Freight Yard entries keep the existing firing rules and replay identity.

Launch the new **Depot Crossfire** encounter with the normal tactical HUD, a cautious enemy commander and ordinary Eliminate victory conditions. The default is 2v2. Use `duel` to isolate the first engagement.

```powershell
godot_console --path . --script res://docs/quality/evidence/contextual-03b/play_crossfire.gd
godot_console --path . --script res://docs/quality/evidence/contextual-03b/play_crossfire.gd -- duel
```

In the duel, end the opening turn to see the enemy's approach around the blue shipping container. To try the same tactic, reach the opposite side of the container and hover candidate destinations before committing AP. The prospective destination summary includes the number of known enemies that offer a side-step shot. Attack chooses the posture automatically. Normal Match Setup also offers **Service Depot — Contextual Firing** and **Freight Yard — Contextual Firing** with ordinary authored deployments.

## Authorization and presentation

The existing shot evaluator tries direct fire first. In the named 03B variants, a blocked direct lane can try two lateral directions relative to the target bearing. At a 1 m tile with a 28 cm body radius, the maximum candidate is 27.5 cm after allowing 5 mm for rounding. Quantized offsets and opposite-side order are deterministic. The 03A bay retains the authored 24 cm adjustment and bearing. The map ID travels with the existing replay configuration and manifest. The ordinary authored sites keep their prior IDs and rules. Future changes to certified constants should retain this replay behavior or use a new variant identity.

Each candidate must stay in the same logical tile and have level floor support along its entire straight sweep. This is stricter than ordinary edge traversal, which can legally take an elbow, vault or ladder. A broad weapon and posture envelope checks indexed static obstacles and neighboring bodies. The same path is reversible. The muzzle is calibrated against the ordinary upright MIRA AUG shot. The selected ray must fit the level aim cone and pass a padded 25 mm obstacle test, using the box, cylinder or rounded-prism representation already used by CombatRules. A direct shot keeps its established tolerance. The initial 24 cm exploratory Depot angle cleared only at nominal alignment and the new margin rejected it. Extending the discovered displacement within the existing body radius let that angle pass the padded test. The 03A reference displacement remains intact.

The adapter holds the approved firing pose during the local step and releases the resting cover posture until the return. Foot IK, raise-before-fire, muzzle effects and recovery remain in the existing presenter. The tactical actor stays at the resting support point. The action service revalidates, and Attack and Guard record the same solution contract. There are no extra movement transactions, reactions, AP or SP charges. Compatibility is limited to the existing standard tactical MIRA and calibrated AUG. Small MIRA and an unavailable weapon reject the local adjustment and retain their ordinary shots. Cross-height shots cannot use this posture. Standing on an upper deck with same-height supports is possible under the code's checks, but no authored upper-deck shot has been visually certified.

Sources include [CombatRules](../../systems/combat_rules.gd), [SurfaceNavigation](../../systems/grid/surface_navigation.gd), [battlefield variants](../../systems/generation/battlefield_catalog.gd), [tactical presenter](../../presentation/tactical/tactical_character_adapter.gd), and [preview text](../../presentation/overlays/tactical_feedback_text.gd).

## Survey

The read-only tool uses seed 16 on three authored sites. It pairs supported stops at each elevation with up to twelve fixed horizontal relative vectors. It checks both direct and contextual possibilities independently so the diagnostic can count lanes where both are possible. Gameplay takes the direct solution immediately when one is available. These counts describe only the sampled bearings and distances on a lightly occupied board.

| Battlefield | Both available | Direct only | Contextual only | Neither | Unique contextual-only stops | Candidate checks |
|---|---:|---:|---:|---:|---:|---:|
| Service Depot | 10,613 | 1,714 | 20 | 1,119 | 20 | 16,915 |
| Freight Yard | 11,501 | 1,986 | 20 | 937 | 20 | 18,095 |
| Fleet Station | 11,862 | 1,559 | 8 | 769 | 8 | 17,205 |

Rejections include the same-cell bound, continuous support and body sweep, weapon envelope, occupancy, muzzle obstruction, edge margin and pitch cone. The survey reports one terminal rejection per unsuccessful pair and runs as a standalone diagnostic. [Survey script](evidence/contextual-03b/survey.gd).

## AI discovery and counterplay

03A's ordinary short-plan selector required a legal target from the current tile before running the Move-then-Attack comparison. Thus recognizing a hypothetical shot in the position scorer did not itself make the planner seek that shot. 03B lets the same selector compare a zero-value starting position with legal destinations on the opted-in maps. It uses its existing AP and SP budget, hit and damage valuation, doctrine-based exposure gate, squad exclusions, and yield/cancellation boundaries. It receives no contextual scoring bonus. The ordinary comparison can still prefer a stronger direct shot or reject an exposed advance. Discovery from a blocked start compares the legal same-level adjacent cells. At least one must offer a useful contextual shot to activate the comparison. Longer advances use the existing route and position evaluator.

The controlled cautious enemy begins at Depot cell `(17, 0, 22)`, with a target at `(11, 0, 25)`. Its opening shot is blocked. It chooses `(16, 0, 22)` and takes an ordinary Attack using a discovered side step. The fixture replays the real turn, Move, and Attack records from the named configuration. The player-side fixture uses the same position forecast and performs the move and shot through ordinary battle controls. A second Depot lane from `(23, 0, 15)` to `(30, 0, 15)` has a valid incoming attack and verifies ordinary Guard retaliation with the selected contextual shot. Alpha's original Service Depot shot remains blocked even in the enabled variant.

Most sampled opportunities are geometrically selective. The encounter retains direct flanking lanes and alternate approaches. The focused evidence establishes one autonomous advance and shot, with neighboring cases where the AI preferred a direct angle or held. Cautious squad coordination around contextual positions and the balance of returning to cover at ordinary Attack cost still need human playtesting. [Battle fixture](../../tests/contextual_battlefield_test.gd) · [AI discovery probe](evidence/contextual-03b/seek.gd).

## Gameplay certification

The final rendered fixture passed **42 checks** at normal speed and observed four muzzle releases. Every observed muzzle-to-selected-sample ray cleared the authoritative obstacle. The maximum position and direction deviations among these releases were **8.16 mm** and **1.56°** against the reference limits of 20 mm and 2.5°. These measurements certify alignment in the exercised positions with this rig, weapon and tested readiness states.

| Scenario | Muzzle position error | Angular error |
|---|---:|---:|
| Depot cautious AI after its own Move | 8.16 mm | 1.55° |
| Depot player after the corresponding Move | 8.16 mm | 1.55° |
| Depot Guard retaliation | 8.16 mm | 1.27° |
| Freight Yard opposite-side Player Attack | 8.16 mm | 1.27° |

The Freight witness used `(3, 0, 13)` to `(10, 0, 13)`, requiring the opposite relative side from the Depot Guard case. Testing a target 0.5 m above its resting height rejected the local posture. A nearby same-height body denied the Depot shot and invalidated the cached display coverage. On removing it, coverage returned. The original bay passes separately. The scoped fixture verified three replay records, including the actual side step, and retained the original tracker's asymmetric truck case. The focused Ironclad checks and project import passed.

[AI screenshot](evidence/contextual-03b/depot-ai.png) · [Player screenshot](evidence/contextual-03b/depot-player.png) · [Guard screenshot](evidence/contextual-03b/depot-guard.png) · [Freight Yard screenshot](evidence/contextual-03b/freight-opposite.png). The automated evidence camera repositions for the images. The playable scenario keeps the normal camera and interaction path.

## Performance

Windows, Ryzen 5 5500, RTX 5060 and Godot 4.7.2. The matched pairs use identical Depot mission, seed, geometry, squad sizes and engine settings. The variant ID adds the 03B ability and short-plan use. The headless probe runs at 12×. Rendered runs used normal speed, 1280×720 and OpenGL Compatibility on a shared desktop. Other desktop activity and background throttling can affect the intervals, so use the frame figures as diagnostic observations. The frame probe records setup, pre-first-transaction frames, action windows and other battle frames separately. It also records elapsed wall time between RenderingServer draw callbacks for slow frames. A frame which began outside an action window may still include rendering, so its label alone cannot attribute a stall to the planner.

During diagnosis, a 359 ms first-transaction warm-up interval contained 355 ms between draw callbacks. A later 376 ms interval occurred in the **disabled** Depot control at transaction 47, with 295 ms between draw callbacks. The enabled pass measured no 300 ms sustained interval in that run. Those observations locate the large render component. Attribution within the render segment remains open across shader compilation, scheduling and GPU synchronization. Scene initialization separately consumed roughly 1.9–2.1 seconds before the initial process frame.

Contextual authority resolves live data. The Guard **display** cache keys named variants on map revision, canonical support, supported equipment, stance and nearby body positions, so distant same-height moves can reuse coverage. Actual Guard queries evaluate the live state. On ordinary maps the existing direct cache rules still apply. The survey counts attempted posture candidates. Enabled live fallback is bounded at two candidates, each with up to five sample rays and the extra padded check of the selected sample. The cache comparison below measures repeated queries at one station.

### Matched headless planning

| Depot Eliminate | Profiled decisions | P95 CPU | P95 uninterrupted slice | P95 decision wall | Completed result |
|---|---:|---:|---:|---:|---|
| 3v3 disabled, seed 950507647 | 48 | 59.09 ms | 13.99 ms | 87.58 ms | Victory, four rounds, 50 decisions |
| 3v3 enabled, same seed | 48 | 58.02 ms | 14.10 ms | 76.38 ms | Victory, four rounds, 50 decisions |
| 5v5 disabled, seed 16 | 123 | 88.47 ms | 15.89 ms | 113.43 ms | Victory, ten rounds, 124 decisions |
| 5v5 enabled, same seed | 123 | 106.62 ms | 17.14 ms | 145.78 ms | Victory, ten rounds, 124 decisions |

All four completed without rejected actions. The original unrestricted 5v5 discovery pass evaluated 3,409 short plans and finished in 22.03 seconds at 12×. The bounded pass evaluated 1,457 and finished in 20.94 seconds versus 1,134 and 19.93 seconds in its disabled control. The focused Depot replay still verifies all three records after limiting discovery. In the matched final 5v5, CPU median moved from 40.07 to 45.15 ms, P99 from 107.55 to 129.49 ms and max from 132.98 to 135.02 ms. Slice max increased from 20.95 to 24.08 ms. Wall P95 for 5v5 is close to the earlier 150 ms planning reference. The 5v5 tail still costs more with contextual fire and warrants measuring again before making the mechanic the default across all maps.

### Preview costs and coverage scheduling

Matched reads at Depot cell `(16, 0, 22)` put target-query median at 0.71–0.73 ms disabled and 1.74–1.75 ms enabled. Move legality plus its destination summary took 4.37–4.46 ms disabled and 5.79–6.22 ms enabled. Each comparison used 128 samples after warm-up and alternated disabled/enabled/enabled/disabled on the same board. An already computed coverage scan returned in 0.007 ms disabled and 0.009–0.011 ms enabled at the median.

A cold full coverage scan took 87–89 ms disabled and 150–151 ms enabled at the median. Enabled Attack and Guard overlays now fill across process frames. Selection changes discard old jobs, and revision or occupancy changes discard results computed against the older board. The exact coverage scanner uses a 4 ms work target and yields between cells. Two cold passes computed the full 213-cell result in 33 and 38 slices. Longest measured scanner work was **6.01 ms**, with **217–261 ms** to complete the diagnostic's full result including yields. An actual shot or reaction revalidates immediately through the existing action service. Target hover stays independent of overlay completion. [Matched preview probe](evidence/contextual-03b/query_cost.gd).

### Completed rendered comparison before display slicing

The table excludes scene setup and pre-first-transaction warm-up. All three runs finished in four rounds with no rejected actions. The engine in this measurement series stayed near a 10 ms background frame cadence.

| Normal-speed match | Sustained samples | Median | P95 | P99 | Max | P95 planner CPU / slice / wall |
|---|---:|---:|---:|---:|---:|---|
| Depot Crossfire 2v2, cautious enemy | 3,157 | 10.00 ms | 10.14 ms | 14.36 ms | 67.93 ms | 76.82 / 18.33 / 114.80 ms |
| Depot 3v3, disabled | 6,392 | 10.00 ms | 10.18 ms | 15.01 ms | 105.55 ms | 57.15 / 13.59 / 99.18 ms |
| Depot 3v3, enabled | 6,392 | 10.00 ms | 10.21 ms | 15.38 ms | 92.71 ms | 59.59 / 14.35 / 90.23 ms |

The final showcase duplicated the cold draw hitch at **364.82 ms**, with **360.20 ms** between draw callbacks and no transaction started. The warmed Depot pair had pre-first-transaction maxima of 17.02 ms disabled and 16.93 ms enabled. The largest sustained interval in each 3v3 was near transaction 47. The enabled run spent only 1.49 ms within the timed draw interval at its 92.71 ms spike, so those shorter spikes still warrant targeted attribution if they prove disruptive. This is a diagnostic comparison, without a repeat distribution across machines or an isolated GPU driver profile.

Local artifacts are under `artifacts/contextual-03b/`. The final paired logs are `bounded-perf-headless.log` and `bounded-perf-render.log`. The initial unrestricted comparisons are in `performance-headless.log` and `performance-rendered.log`. The final rendered verification log is `sliced-cert-render.log`, and `survey-final.log` records the candidate census and witness coordinates.

The post-slicing rerun completed the 2v2 showcase in four rounds with 26 decisions and zero rejected actions. Its sustained median, P95, P99 and maximum intervals were 10.00, 10.21, 14.79 and 76.12 ms. The final rendered certification and matched preview probe completed. The remaining rendered comparison was stopped at the owner's direction. Further performance optimization is deferred.

## Regression runs

Ironclad passed 106 of 106 in the complete combat, AI, actions and replay selection, including the 48-case curated mission/replay matrix. Nine supplemental presentation and geometry tests also passed. This broad run tested the generalized combat feature before the final display-scheduling refinement. After slicing, project import and ten focused tests passed again. The rendered regression verifies that cancellation discards an unfinished selection, a completed scan matches synchronous geometry, and the sliced Guard preview contains the already-validated contextual lane. Each run used the production project and Ironclad's test isolation. The unrelated complete ordinary tier was outside this run.

## Current rollout boundary

The certified family is a level side step to either side. Stationary leaning, over-cover postures, additional rigs and weapons, and upper-deck certification are separate work. Service Depot and Freight Yard have opt-in rules variants. Fleet Station remains a survey site. The exact sample-based exposure during a step is preserved in the firing origin and replay receipt. The same existing reaction rules apply throughout. The campaign has a controlled cautious advance and a complete rendered 2v2, with human counterplay and wider squad coordination still to evaluate. Keep the opt-in rollout while testing the larger-match planning tail and whether returning to cover feels fair.

### Follow-up design question

A head-height sight origin can stand in for eyes on the MIRA model. Explore it separately from the firing origin. A simple prototype can ask whether the unit sees the opponent's head or core from the proposed firing posture, and whether the calibrated muzzle can engage from that same posture. Authorizing a shot would require both checks to pass. Use the original Depot incident as a control because the only exposed sample was on Alpha's side. Another useful control is a head visible over a low obstacle with the weapon still blocked. Changing target samples changes both legal engagement and current obstruction penalties, so the prototype needs its own balance and replay review.

## Reproduction

```powershell
.\tools\run_tests.ps1 check
.\tools\run_tests.ps1 subsystem -Subsystem combat,ai,actions,replay
.\tools\run_tests.ps1 select -Test contextual_battlefield_test,contextual_firing_bay_test,tactical_decision_feedback_hud_test,combat_guard_coverage_cache_test
godot_console --headless --path . --script res://docs/quality/evidence/contextual-03b/survey.gd
godot_console --headless --path . --script res://docs/quality/evidence/contextual-03b/query_cost.gd
godot_console --headless --path . --script res://docs/quality/evidence/contextual-03b/seek.gd -- profile-ai
$captures = Join-Path $PWD "artifacts/contextual-03b/captures"
godot_console --path . --rendering-method gl_compatibility --resolution 1280x720 --script res://tests/contextual_battlefield_test.gd -- "$captures"
godot_console --headless --path . --script res://docs/quality/evidence/contextual-03b/performance.gd -- profile-ai
godot_console --path . --rendering-method gl_compatibility --resolution 1280x720 --script res://docs/quality/evidence/contextual-03b/performance.gd -- profile-ai
```
