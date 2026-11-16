# Standing-point rollout — 2026-11-16

## What changed

The first delivery enabled supported standing points only in Surface Fit Range. The reported crate/container screenshots were from ordinary content, still using whole-cell reservations. The user explicitly requested enabling the workflow everywhere.

Compiler **6** now enables it automatically for all new current-map and editor compilations. No asset edits or opt-in flags are needed. Compiler 5 retains its old opt-in behavior for historical manifests; compilers 1–4 retain historical geometry. Current replay simulation is **prototype-1.5-surface-placement-7**; older simulation recordings reject explicitly. Restart existing matches to recompile.

## Failures found and corrections

| Finding | Classification / correction |
| --- | --- |
| AI waited with no reachable approach | Integration regression: AI planned into an occupied opponent's cell. It now chooses a reachable adjacent approach point; execution still rejects occupied bodies. The initial Freight/Fleet runs stalled, without crashes. Subsequent complete battles and replay passed. |
| Some compiled cells were unsafe before graph building | Integration regression: direct compiler callers had not finalized standing points. Graph construction now resolves pending geometry once. Later graph rebuilds preserve mission reservations instead of reopening cells. |
| Ladder links disappeared | Missing pilot capability: explicit authored support transitions now use a checked rise-outside/step-on route. Static clearance, live neighboring bodies and presentation use the same route; reverse traversal follows it downhill. |
| Ramp/stair edges could require a ladder detour | Missing capability: existing ElevationPath authorship now supplies explicit checked step connections, including entry/exit. The range has six step links plus its three existing ladder links. AP/cell identity remains discrete. |
| Exact corner seam became shootable | LOS regression: independently indexed part bounds discarded touching-edge tolerance. Closed probes now preserve it while retaining single-corner grazing and above-cover clearance. All 101 controlled combat checks passed again. |
| Rounded tanks would fill their enclosing rectangle | Conservative fallback regression avoided: movement retains their old stepped reservation and cover rather than filling the previously empty corners. Exact curved footprints are not implemented. |
| Garage asserted LOS flags on floor cells | Obsolete representation contract: retained blocked body occupancy and replaced the floor-flag assertion with a real blocking ray against independent geometry at that floor. No obstruction/occupancy assertion was removed. |
| Exhaustion coroutine resumed after freeing a battle | Lifetime defect exposed by the real ramp move/teardown: continuation now uses a bound frame callback, automatically canceled with its manager. |
| The gap between two containers had a safe point but no straight entry | Conservative route limitation: fit and sweep now share an enclosing box, and an edge can use a checked two-leg elbow with supported floor. Endpoints alone never authorize passage. |
| Low-cover vaults stopped working | Integration regression: preserve low cells as non-stoppable raised transit, validate the complete route, and avoid applying cover height twice in presentation. Thin low barriers can also be crossed only with checked overhead clearance. |
| Preview rebuilding left a previously freed runtime object | Lifetime defect: clear the reference when freeing the preview; a failed build now reports its error safely. |
| Population/surface/camera checks still assumed geometry lived on floor cells | Obsolete representation assertions: check independently indexed real obstruction and adjacent directional cover. Compare both reordered maps after the same resolution stage and additionally compare their point/geometry signatures. |
| Lifetime-safe exhaustion selection was one frame late | Regression in the callback fix: keep the bound one-shot callback synchronous with the frame signal, preserving existing post-action selection timing. Portrait and vertical teardown checks pass unchanged. |
| Repeated full-geometry sweeps inflated loading work | Implementation cost: immutable movement parts have a column index; geometry filtering happens once after graph construction; level-floor support checks visit each swept floor tile once. Native path search remains the fast path, with body-aware fallback and an admissible flat-map heuristic. Hypothetical planning vacates the explicitly named actor without repeating an anonymous detour. Static routes are cached; live bodies are always checked again. |

## Focused executed evidence

- **63 rollout checks:** ordinary crate and container at four rotations, no opt-in metadata, formerly blocked neighbor becomes reachable with a real standing offset and 0.04 body clearance; all three playable sites at seeds 16/17; rounded fallback corners and cover; a swept elbow route into the pocket between containers.
- **56 navigation checks:** fit/support/sweeps, body separation/detours, actual cover markers, own-cell shot geometry, thin edge walls, preview/Guard/live agreement, deterministic evidence and scale/rotation cases; static route caching never caches live unit occupancy and is reset by resolution.
- **10 vault checks:** non-stoppable low-cover transit, the real range barrier, matching presentation height, thin low edge barriers and ceiling rejection.
- **18 vertical checks:** real ladder climb/descent, direct ramp/stair edges, real ramp movement, presentation waypoints and teardown-safe exhaustion continuation.
- **101 controlled combat checks:** crate/truck/doorway/raised geometry, two-object corner seal, single corner grazing and exact reconstruction.
- The current generation check, authored parcel catalog, garage checks and complete Freight/Fleet battle/replay playthrough passed after their respective corrections.

Rendered regular-Depot checks completed **72 checks / 0 failures**, including real Moves beside `CrateA` and `ContainerEast`. Review images: `artifacts/surface-regular-depot/CrateA.png` and `ContainerEast.png`. The images were inspected; shader dithering and unfinished procedural pose fitting remain visible limits, deliberately deferred.

Logs use the `artifacts/surface-global-*` and `artifacts/surface-rollout-*` prefixes. Headless success does not establish complete visual correctness or finished animation. Wall-hand/foot IK, automatic mesh-derived climb surfaces and exact concave/curved collision remain future work.

## Broad verification

The earlier **144/0/14** result belongs to the pilot-only build.

The completed global diagnostic full run reported **142 PASS / 5 FAIL / 14 explicit-only SKIP**, 1456.93 seconds, at `artifacts/test-results/surface-global-final/20261116-181436-full/`. This is not a fully green full-run claim. The five failures were:

- `parcel_container_population_test`: obsolete floor cover and two-cells-away protection assertion. Now tests independent full-cover geometry and a rotated adjacent standing point; focused rerun passed.
- `parcel_population_surface_test`: compared a resolved graph with an unresolved compilation. Both are now finalized, with a stronger point/geometry signature equality assertion; focused rerun passed.
- `portrait_bar_smoke`: one-frame selection regression from the lifetime fix. Callback timing corrected; unchanged focused test passed, as did all 18 vertical teardown/traversal checks.
- `tactical_camera_aperture_test`: expected the column's floor object as blocker. Now identifies the real independently indexed column bounds; focused rerun passed, preserving all camera/occupancy/isolation checks.
- `ai_stalemate_recovery_smoke`: extraction reached the original 35-second deadline. After pathfinding/cache fixes, the isolated unchanged suite passed: Depot extraction completed Victory in 27.97 seconds (114 decisions), and the legacy elimination completed Defeat at 35.00 seconds (151 decisions). The latter is borderline: it reported the deadline text while already completed. This is limited timing headroom, not a comfortable performance margin.

No timeout was raised and no suite was skipped to hide these failures. The first interrupted diagnostic run and failed intermediate attempts remain under `artifacts/test-results/surface-global-rollout/` and the focused log prefixes. Windows root-certificate errors are an existing environment diagnostic, distinct from assertion results.

All five failing suites passed focused follow-ups. The added cache regression also passed: **56 navigation checks / 0 failures**. These follow-ups do not retroactively make the earlier full run green. Final unchanged Ironclad smoke: **11 PASS / 0 FAIL / 0 SKIP**, 62.23 seconds, at `artifacts/test-results/surface-release-smoke/20261116-184530-smoke/`.
