# World surroundings: tactical isolation and replay

Roadmap 03, step 7. Surroundings remain fixed, editable content belonging to their plot. No new generator, authoring step or replay schema was introduced.

## Boundary correction

The new controlled edge regression initially reported **24 failures**: at each of four edges in both Depot layouts, a deliberately misplaced registered enemy remained shootable and mouse-selectable, and an outgoing shot prediction accepted an off-map firing cell. Normal deployment did not reproduce this invalid placement; the test intentionally creates it to verify the boundary contract.

CombatRules now requires both firing and target cells to exist in MapData, including predicted positions. The action service reports `outside_battlefield`; mouse unit picking excludes actors on missing cells. Legal inside shots and moves retain their existing rules. Scenery meshes still do not supply tactical cells or become targets.

The final regression passed **eight edge cases with zero failures**. It checks the outside ring for absent map/pathfinding cells, rejects outside movement and attacks without changing AP/HP/occupancy, and rejects outside floor picking. Inside move, shot and mouse-picking controls remain legal. Controlled extraction-zone queries check boarding eligibility beside every edge; these queries do not claim to simulate a complete transport departure there.

## Fixed scenery and reconstruction

- Sixteen Depot presentations (seeds 16–23, population on/off) retain the same Peripheral/Distant scenery within each plot. Both plots are exercised and retain their distinct frontage.
- The comparison includes actual mesh geometry, transforms, materials, labels and visibility. A deliberate scenery transform change must change the comparison, preventing vacuous equality.
- The ordinary current mission/replay matrix passed **48 cases**: three sites, seeds 16/17, eight mission kinds. Each checks deployed actors, deployment/objective/extraction zones, terminals and transport footprints against the tactical map/graph. Existing initialization validation and action/replay assertions remain intact.
- Each matrix case serializes a committed Aim action, reconstructs the accepted manifest, compares the initial surrounding scenery and atmosphere, and verifies playback. This is bounded initialization/reconstruction coverage, not 48 complete battles.
- Four graphics captures cover live/replay pairs for both Depot layouts. Direct review found matching surrounding layouts and appearance; HUD and actor presentation differ between live and replay. Captures: `artifacts/world-scenery-replay-review/`.

Fixed scenery reconstructs through the existing recorded plot identity/revision and installed authored scenes. These recordings do not bundle historical art. Future meaningful scenery changes must use the existing content revision policy; adding variation would require recording its resolved deterministic choices. No unrecorded scenery randomness was added.

## Verification

| Check | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: |
| Focused edge regression | 8 edge cases | 0 | 0 |
| Current mission/replay matrix | 48 cases | 0 | 0 |
| Combat subsystem | 25 | 0 | 1 |
| Movement subsystem | 14 | 0 | 0 |
| UI subsystem | 25 | 0 | 1 |
| Replay subsystem | 15 | 0 | 0 |
| Explicit graphics matrix capture | 2 cases / 4 images | 0 | 0 |

Counts overlap and should not be added as unique tests. The combat skip is the explicit-only map-quality diagnostic; the UI skip is the explicit-only parcel-editor capture. The full suite was not rerun. No script/parse errors appeared in these subsystem logs. The allied-faction smoke retained its existing four-ObjectDB-instance/one-resource exit warning, also present in earlier full-run logs; certificate-store diagnostics remain environmental. Passing assertions do not mean those warnings were fixed.

Evidence is under `artifacts/world-isolation-*.txt` and `artifacts/test-results/20261115-214420-subsystem-combat`, `20261115-215322-subsystem-movement`, `20261115-214844-subsystem-ui`, `20261115-214833-subsystem-replay`.

Reproduce from the repository root:

```powershell
godot_console --headless --path . --script res://tests/world_tactical_isolation_test.gd
godot_console --headless --path . --script res://tests/current_mission_replay_matrix_test.gd
godot_console --path . --script res://tests/current_mission_replay_matrix_test.gd -- capture artifacts/world-scenery-replay-review
```

Without capture arguments, the matrix always runs all 48 cases. Explicit graphics capture runs only the two Depot Eliminate cases while retaining their per-case assertions. The edge test is included in generation subsystem discovery.

Step 7 is complete for the bounded Depot proof, with current-site mission/reconstruction coverage. This does not establish every seed, full-mission playthrough, arbitrary future collision-bearing scenery or visual correctness from headless results. Next is the planned performance measurement; broader scenery rollout remains separate.
