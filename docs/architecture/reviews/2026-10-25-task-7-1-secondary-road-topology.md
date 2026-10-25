# Task 7.1 — Certified Secondary-Road Topology

## Outcome

Generation 2.0 now supports one bounded secondary street branching from its established primary road. The extension is deterministic, asset-first, reservation-aware, and transactional. It uses the already certified 10-cell straight and T-intersection assets; it does not introduce a general road grammar or a procedural road fallback.

The supported 60×50 reference configuration replaces one eligible interior straight segment with a correctly rotated T intersection and extends a perpendicular straight branch to a map boundary. Smaller established layouts retain their Phase 6 primary-road topology.

## Capability audit

| Module | Authored footprint | Certified openings | Current use |
| --- | ---: | --- | --- |
| `road_straight` | 10×10 | two-cell lanes at local north/south | primary and secondary runs |
| `road_intersection_t` | 10×10 | two-cell lanes at local west/east/south | primary intersection and secondary branch joint; all quarter turns |
| `road_crossroad` | 10×10 | two-cell lanes on all four boundaries | primary intersection |
| `road_corner` | 20×20 | north/east after source normalization | geometrically certified, but not used by this bounded expansion |

The imported straight mesh's source-local axis correction remains an asset normalization concern. Logical module rotations, connector directions, and presentation yaw continue to use the canonical Phase 1 transform. Existing geometry regressions inspect the actual imported surfaces in all supported rotations and verify that their physical openings agree with these connectors.

All four supported road assets share the certified imported pavement/curb/sidewalk presentation path and aligned seam heights. No duplicate procedural asphalt or sidewalk layer was reintroduced. There is no certified imported internal dead-end cap, so the new branch must reach a map boundary; an unmatched interior opening is invalid.

The 20×20 curve remains outside this extension. Its two-macro occupancy and termination choices need a separately bounded topology contract rather than being inserted opportunistically.

## Selected topology and rules

The selected target is a single side street because it adds another intersection, new frontage, and useful traversal lanes without requiring recursive search.

Candidate construction is deliberately limited:

- the map must be at least 60×50 cells;
- the joint must replace an interior primary `road_straight`;
- the branch must use one of the two perpendicular connector directions;
- its T rotation must be derivable from the three required logical openings;
- every branch macro must avoid the primary road and required mission/access reservations;
- a branch may not run immediately beside a parallel primary carriageway, which would create a cramped, purposeless strip;
- the branch must reach a map boundary using certified straight segments;
- among valid choices, the shortest branch is preferred to preserve contiguous 20×20 land for reviewed complete-building shells;
- the complete trial road set must be connected and every interior opening must mate before any placement is committed.

Candidate ordering uses an isolated RNG seeded from the map seed. Rejection cannot mutate the accepted layout. The parcel search remains independently bounded by its existing Phase 5 budget.

## Frontage, mission, and tactical integration

Road construction still precedes parcel derivation. Consequently the existing Phase 5 frontage calculation sees the accepted secondary-road cells and emits exact boundary intervals with references to the real road placement signatures. It does not assume that an entire macro boundary is frontage.

Required mission and access reservations are available before the branch is selected. A branch candidate touching one of those regions is rejected; optional roadside furniture remains subordinate to the resulting access reservations. A synthetic regression reserves every possible perpendicular corridor and confirms that no secondary street is selected.

`MapData` remains authoritative for traversal, cover, LOS, occupancy, deployment, and objectives. The road meshes continue to be presentation inputs only. The unified document records the accepted placements and pins `road_topology = certified_secondary_branch_v1`; it does not regenerate the branch during replay or edited-map loading.

## Representative matrix

The timings below are one local diagnostic run, not a performance benchmark. There was no comparable Phase 6 timing record, so no percentage improvement is claimed.

| Environment | Seed | Topology | Roads | Functional / buffer parcels | Attempts / rejected | Fallback / exhausted | Generation |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| industrial district | 17 | crossroad + branch | 12 | 11 / 1 | 13 / 1 | 0 / 0 | 4225.23 ms |
| commercial street | 7319 | crossroad + branch | 11 | 10 / 3 | 24 / 12 | 1 / 0 | 5592.17 ms |
| mixed service | 11027 | T junction + branch | 8 | 8 / 8 | 16 / 0 | 0 / 0 | 4620.15 ms |

Every rejection in this matrix was `RESERVED_REGION_BLOCKED`; required mission space retained priority. Commercial seed 7319 preserves its one explicit, proven mission-space incompatibility rather than concealing it with unrelated fallback content. No quantified improvement over Phase 6 is claimed because comparable timing and parcel-count baselines were not recorded.

The same matrix passed tactical validation, deterministic repeated generation, exact frontage-reference validation, unified-document validation, and document-driven tactical reconstruction. Industrial seed 17 also completed real Eliminate and Terminal missions. Its edited 35-action battle replay reproduced all authoritative outcomes and the same final victory.

## Regression coverage

`tests/coherent_secondary_road_test.gd` covers:

- primary-to-secondary construction across all three identities;
- the two-intersection network and all four T-intersection rotations;
- logical opening agreement and boundary-only termination;
- incompatible neighbor and missing termination rejection;
- required-reservation priority;
- transactional rollback;
- deterministic placement and document reconstruction;
- frontage references and multiple road-facing parcel boundaries;
- unchanged 50×40 primary-road compatibility.

Existing geometry tests continue to provide independent real-mesh opening and seam-height evidence. Existing parcel, lifecycle, battle, gameplay, and replay tests exercise the downstream contracts.

Final verification on 2026-10-25:

- Project Ironclad Generation subsystem: **35 passed, 0 failed, 17 explicit-only skipped**, 1264.00 seconds.
- The first broad run correctly exposed a loss of complete-building capacity in two catalog seeds. The assertion was preserved; branch selection was corrected to minimize parcel fragmentation, and the affected coherent-layout suite plus the entire Generation tier then passed.
- Generation 2.0 battle initialization: 0 failures.
- Generation 2.0 tactical gameplay (including real Eliminate and Terminal completion): 0 failures.
- Generation 2.0 edited-map replay (35 recorded/replayed actions): 0 failures.
- Rendered capture script: completed successfully through the normal D3D12 presentation path. Visual findings are manual evidence, not headless assertions.

Commands used:

```powershell
godot_console --headless --path . --script res://tests/coherent_secondary_road_test.gd
godot_console --headless --path . --script res://tests/coherent_geometry_contract_test.gd
godot_console --headless --path . --script res://tests/coherent_parcel_retry_test.gd
godot_console --headless --path . --script res://tests/battlefield_layout_end_to_end_test.gd
godot_console --headless --path . --script res://tests/generation_2_battle_preset_test.gd
godot_console --headless --path . --script res://tests/generation_2_tactical_gameplay_test.gd
godot_console --headless --path . --script res://tests/generation_2_replay_edited_map_test.gd
.\tools\run_tests.ps1 subsystem -Subsystem generation
```

## Rendered inspection

Normal captures have plan/spatial overlays disabled. The diagnostic capture is separate.

- [Industrial seed 17 overhead](evidence/secondary-road-task-7.1/industrial_district-17-overhead.png)
- [Industrial seed 17 secondary junction and seams](evidence/secondary-road-task-7.1/industrial_district-17-secondary-seam.png)
- [Industrial seed 17 frontage diagnostic](evidence/secondary-road-task-7.1/industrial_district-17-diagnostic.png)
- [Commercial seed 7319 overhead](evidence/secondary-road-task-7.1/commercial_street-7319-overhead.png)
- [Mixed-service seed 11027 overhead](evidence/secondary-road-task-7.1/mixed_service-11027-overhead.png)

Visual inspection found continuous imported pavement, curb, and sidewalk surfaces at the new T joint, correct lane orientation, no transverse road bands, no duplicate road layer, and useful parcel separation from parallel primary roads. The first render exposed an immediately parallel double-road candidate; that candidate class was then rejected and the final captures were regenerated.

## Remaining limitations for Task 7.2

- Exactly one secondary branch is supported on the certified 60×50 pitch.
- Internal dead ends remain unsupported because no end-cap contract is certified.
- Curved secondary streets, loops, multiple branches, and vertical roads are not orchestrated.
- Branches use straight-to-boundary termination only; they do not search for arbitrary reconnection.
- This matrix is representative, not proof of universal seed quality.
- Generation 2.0 remains opt-in; the default generator is unchanged.

## Changed files

- `systems/generation/coherent_environment_assembler.gd` — bounded branch selection, reservation-aware candidate filtering, transactional road commit, and strict opening/termination validation.
- `systems/generation/battlefield_layout_document.gd` — pinned road-topology algorithm revision.
- `tests/coherent_secondary_road_test.gd` — focused deterministic geometry, frontage, reservation, rollback, and persistence coverage.
- `tests/coherent_secondary_road_capture.gd` — explicit normal and diagnostic render workflow.
- `tests/battlefield_layout_end_to_end_test.gd` — road revision lifecycle assertion.
- `tests/coherent_parcel_retry_test.gd` — safe diagnostic handling for the existing commercial incompatibility contract.
- `tools/run_tests.ps1` — capture classified as explicit-only visual evidence.
- `docs/architecture/reviews/evidence/secondary-road-task-7.1/` — reproducible inspected captures.
