# Milestone 06.02 — Support-aware surface placement

## Baseline and result

Integrated main was `8616b1862f41a5ea1d5c5565687a59ecaa696cd1` with PRs #95 through #101. The review work used an isolated checkout. The [06.01 support probe](evidence/movement-06/support_probe.gd) established the original 7 × 7 fixture. A new assertion on that baseline failed with `can_stop=false`, even though the audit's southern alternative at `(0, 0, 0.43)` independently passed floor, body and approach checks. The new compiler chooses `(0, 0, -0.42)` in logical cell `(3, 0, 3)`. The tested north and south candidates tie in distance and the established lower-Z tie-break chooses north. With eastern support restored the original `(0.33, 0, 0)` wins unchanged.

The final production revision is `57ff464d8aee2ca48f8c25674181d147c0c0829d` on `codex/support-aware-placement`. Follow-up commits record verification of that code.

## Placement and route lifecycle

1. The authored layout compiler builds logical cells and support columns from elevation and deck metadata, and stamps explicit component bounds into independent movement and shot geometry indexes. The shape compiler stays at revision 10; the authored-layout compiler revision identifies placement and reconstruction behavior.
2. `SurfacePlacement` proposes the existing cell-interior candidates from the desired point, cell boundaries, expanded box faces, curved contact projections and the existing curved-case lattice. It keeps the existing ordering by squared distance, then X and Z. `SurfaceNavigation` supplies a final predicate for an obstacle-clear candidate. It snaps to 1/10,000 cell, checks the same-height circular support footprint, then applies the existing constrained zero-length box sweep and curved clearance. If the candidate fails, the resolver continues within its existing budget. Previously accepted first candidates use the same tests and quantized XYZ.
3. A cell receives at most one canonical standing point. The grid retains the old low-cover transit fallback when no valid point is found. Missing same-height support and full-body obstruction both reject as placement failures. A valid point still requires an independent swept edge. The graph keeps its existing corner, stair, ladder and vault handling.
4. The action service uses the graph for logical distance and movement inventory, then revalidates live occupancy, clearance, AP and request revision. Path refinement expands the presentation path while keeping the same settled XYZ. Combat, cover, Guard and AI consume the same canonical point. The overlay remains keyed by logical tile identity.

Bounds remain 32 local parts and 256 ranked candidates, with the existing curved preferred-point fast path. The search is finite and does not create candidates at arbitrary floor intersections. The conservative swept box may reject clear-looking gaps. A valid point can be disconnected, occupied, or beyond budget independently of its static fit. The surface compiler uses the existing shared tactical body profile. This work does not certify different physical dimensions for alternate rigs.

## Matched census

Windows, Godot 4.7.2 Stable, one-meter cells, default map generation and identical seeds. The table lists logical cells, valid stops and transit-only cells. The [machine-readable comparison](evidence/movement-06/support-census-results.json) contains individual rows, exact standing/geometry signatures, box/curve/shot counts, changes to directed edges and timing distributions.

| Layout and seeds | Logical | Stops, baseline → corrected | Transit, baseline → corrected |
| --- | ---: | --- | --- |
| Service Depot, 16 / 17 / 950507647 | 1600 each | 1455 / 1455 / 1452, unchanged | 6 / 6 / 8, unchanged |
| Freight Yard, same seeds | 1600 each | 1510 / 1510 / 1513, unchanged | 16 / 16 / 16, unchanged |
| Fleet Station, same seeds | 1600 each | 1505 / 1511 / 1502, unchanged | 8 / 8 / 8, unchanged |
| Tactical Test Range, 16 | 1246 | 1095, unchanged | 12, unchanged |
| Contextual Firing Bay, 16 | 144 | 144, unchanged | 0 |
| Parking Garage, 16 | 2080 | 1519, unchanged | 0 |
| Controlled partial support, 16 | 49 | 47 → 48 | 0 |

No sampled authored map lost a legal stop, changed a previously legal XYZ, changed a static edge or changed its standing/geometry signature. The Test Range includes rounded geometry and multiple levels. The controlled fixture recovered one stop and admitted 12 directed edges. Eight connect to the stop, and four connect neighboring tiles where the recovered tile now permits the diagonal corner rule. The southern direct edge to the selected canonical point still intersects the obstacle and is rejected. No corrected stopping point in this census failed the independent support and body checks. These seeds do not estimate the frequency of the defect in shipped content.

Across Depot, Freight Yard, Fleet Station, Test Range and Parking Garage, median per-case compile time was 242–474 ms before and 246–484 ms after. Graph construction was 167–359 ms before and 168–361 ms after. Warm graph-only inventory was 0.65–0.82 ms before and 0.65–0.82 ms after. Targeted graph paths were 60–84 µs before and 60–84 µs after. Each case used five measured compiles after a warmup and 100 measured warm queries. The JSON provides the median and P95 for each case. An alternating same-process microbenchmark on the 49-cell fixture gave placement-only median/P95 of 1.512/2.369 ms before and 1.580/2.627 ms after, with 200 measured iterations per mode. Samples are small and include host variability. The timings measure synchronous work. The surveyed shipped layouts preserved their graph inputs and outputs. The recovered-route fixture compares actual AI planning-path and player Move legality. AI turn latency was outside the measured workload.

## Action, combat and replay evidence

The [surface-navigation regression](../../tests/surface_navigation_test.gd) covers the full-floor control, both same-height support and body checks, elevation mismatch, deterministic selection, a supported point with a blocked connecting route, cardinal and diagonal costs, and budget rejection. The [authored-deck regression](../../tests/surface_support_battle_test.gd) uses a real archived test parcel with the audit obstacle and a missing eastern deck tile. Alpha starts at `(8, 2, 18)`. The ordinary shared Move inventory, targeted preview and hypothetical AI planner agree on the cardinal approach to `(8, 2, 19)`. A hostile physically occupying the recovered tile prevents it from appearing in the legal inventory. The committed receipt costs one AP and one revision. The destination is exclusive and the actor arrives at the canonical transform. Combined-mode attack preview and execution geometry agree on selected aim and cover. A legal hostile Guard query against the prospective position agrees with its post-arrival query.

New authored recordings use compiler 11. Retained manifests at revision 10 and earlier reconstruct with their historical first-fit-then-validate placement. The exact same archived deck still rejects that tile under revision 10 and produces the earlier signature. Saved revision 11 reconstructs the corrected map and verifies the actual quantized Move receipt and state fingerprint. Existing replay checks still reject a mismatched signature. The seed-only Contextual Firing Bay retains its original geometry path. Combat and contextual firing defaults are inherited from #100 and their rules are unchanged by placement.

## Rendered sequence and reproduction

The test uses the real tactical viewport, level selector, F3 walkability, Move range, hover/inspection, ghost and action presenter. Fixture code places the initial actors on the deck and issues the normal Move service request. The same camera shows the unavailable tile with compiler 10 and the available tile with compiler 11. Alpha approaches and settles beside the pillar with the edge on the outside, no observed floating foot or body penetration in this sequence. The existing camera cutout can fade the near pillar after arrival. The actor floor and occupancy checks remain independent of that visual effect.

[Revision 10](evidence/movement-06/images/support-00-legacy-walkability.jpg) · [Revision 11 and pinned ghost](evidence/movement-06/images/support-02-preview.jpg) · [Approach](evidence/movement-06/images/support-02b-approach.jpg) · [Arrival](evidence/movement-06/images/support-03-arrival.jpg)

```powershell
.\tools\run_tests.ps1 check
.\tools\run_tests.ps1 select -Test surface_navigation_test,surface_support_battle_test,surface_curved_battle_test,surface_battle_replay_test,reactive_passenger_release_test -Import
$out = Join-Path (Get-Location) 'artifacts/0602/render'
$env:FUSEFIRE_TEST_OUTPUT_DIR = $out
godot_console --path . --rendering-method gl_compatibility --resolution 1280x720 --script tests/surface_support_battle_test.gd -- capture-legacy $out
godot_console --path . --rendering-method gl_compatibility --resolution 1280x720 --script tests/surface_support_battle_test.gd -- capture $out
```

For the census, copy [support_census.gd](evidence/movement-06/support_census.gd) to the corresponding path in an imported checkout at each commit. Run `godot_console --headless --path . --script docs/quality/evidence/movement-06/support_census.gd --log-file <absolute-output-path>` in each checkout. Pass both logs to [compare_support_census.py](evidence/movement-06/compare_support_census.py). The `-- placement-only` user argument runs the alternating microbenchmark on the corrected checkout.

## Verification results

- Ironclad catalog validation passed with 310 entries. Project import passed. [Hosted smoke passed on the production revision](https://github.com/Melo9002/fusefire-proving-grounds/actions/runs/46031334747).
- The focused dependency run executed 25 ordinary catalog scripts using their Godot options and isolated profiles while the full runner continued. It finished with 24 passes and one inherited failure. The unchanged `ladder_landing_test` reproduced four standard-MIRA descent overlap assertions for armed and unarmed posts/rails under [#64](https://github.com/Melo9002/fusefire-proving-grounds/issues/64).
- Passed coverage included both placement tests, both authored surface battle and replay tests, the new deck regression, surface vaulting, compound and curved geometry, diagonal movement and path refinement, action service, AI clearance and carrier reservations, Guard, both Rescue loss regressions including the checkpoint fallback, contextual firing on the Bay and authored fields, combat geometry, HUD, presentation authority and the 48-case current mission/replay matrix.
- Two actual revision-10 Depot recordings verified all their actions. The tracked `Test.json` verified 80/80 and retained its victory. The local Combined/contextual Crossfire seed-16 recording verified 50/50. The new deck record verified 1/1 with revision 11. Both matched renderer captures used the existing tactical action presenter in Compatibility mode at normal speed.
- Full Ironclad finished **RED** with 267 passes, six failures, zero timeouts and zero unexecuted selections in 3,515.69 seconds. All 273 ordinary scripts ran. Ironclad excluded 37 explicit-only scripts. The run began before the production commit, so its recorded Git revision is the baseline and the checkout contained the reviewed implementation. The new surface battle test passed again in this run. The final `results.json` and logs are in `artifacts/0602/full/20261127-130324480-5f74939f-full`.
- All six full-tier failures reproduced on a separately imported Git archive of exact integrated main, `8616b1862f41a5ea1d5c5565687a59ecaa696cd1`. Baseline controls are under `artifacts/0602/baseline-control`. The same archive also reproduced all 13 baseline census point, edge and signature records with the final diagnostic script.

| Full-tier failure | Exact-main control |
| --- | --- |
| `camera_environment_apertures_test` | Same Contextual Firing Bay aperture-compatibility assertion. |
| `core_objectives_smoke` | Same pre-pickup VIP incapacitation assertion intermittently failed on main. Two uncapped controls passed and one failed. The assertion also failed on main at low fixed FPS. This fixture checks the authored prototype scene, which has surface placement disabled. |
| `generation_retirement_test` | Same compact-Depot/explicit-seed setup default assertion. |
| `ladder_landing_test` | Same four regular-MIRA descent assertions under matched 60 FPS sampling. An uncapped baseline control tripped three of the four. The assertion source and tolerances were left intact. |
| `reusable_occupant_test` | Same four assertions for the three extracted loading-yard parcels and the delivery asset. |
| `tactical_archetype_lab_test` | Same four-tab Match Setup expectation. |

## Review boundary

Step 06.03 evidence covers routes, budget, live occupancy and shared queries for the recovered stop. Broader route and reaction parity remains open. Issue #7 remains open for separate owner reproductions. Issues #8 and #9 still concern mesh apertures and stale baked asset bounds. #64 remains the inherited ladder descent issue. The full-run failures reproduced on main. Recommend owner acceptance of this bounded correction before starting 06.04.
