# Engineering response: battlefield and environment generation

Date: 2026-10-20. Review baseline: `044fc24`. This response records the first repair batch prompted by the independent battlefield assessment.

## Disposition

| Finding | Status | Response |
| --- | --- | --- |
| F1 — straight-road source axis | Resolved | Direct mesh inspection established model-local X as the carriageway axis. `road_straight` now carries one explicit source-to-module quarter-turn, and all four rotations are checked against logical openings. The Asset Lab description now records the actual source axis. |
| F2 — logical/rendered quarter turns | Resolved | Continuous points, cells, directions, envelopes, boxes, offsets and imported visuals now share the module's counter-clockwise grid convention. Godot presentation yaw is derived once with the required opposite sign. A real asymmetric shell is checked through the presenter at rotations 0–3. |
| F3 — rectangular envelope rotation | Resolved | Envelope corners use the canonical direct point transform rather than repeated turns with stale dimensions. An offset 2×5 fixture protects all rotations with independently calculated expected AABBs. |
| F4 — calibration/assembly drift | Deferred | The batch did not introduce a resolved versioned asset contract. Existing calibrated shell profiles remain duplicated authoring data and still need invalidation/version support. |
| F5 — parcel relationship validation | Deferred | Frontage spans, pedestrian/loading access and parcel ownership remain the next assembly concern. The apparent colored machinery intersection on `building-t` was confirmed as geometry inside the source GLB, not a separate procedural placement. |
| F6 — validation boundaries | Partially resolved | The Map Editor now says `TACTICAL VALID`. Final-world frontage, road openings and road-owned lamp facing have independent regressions. `semantic_district_generation_test.gd` is included in the generation tier. Assembly certification remains future work. |
| F7 — shared layout document/gameplay | Deferred | Edit-copy provenance, environment identity, deployments and gameplay opt-in were intentionally left for a later architectural batch. |
| F8 — visible fallback geometry | Partially resolved | Normal roads now render only the downloaded City Roads meshes. Derived asphalt, sidewalk, curb and marking boxes require explicit presenter diagnostic mode. The derived loading canopy remains and needs either a certified kit assembly or a documented exception. |

## Canonical transform contract

`EnvironmentModuleDefinition` owns the local-to-placed transform:

- `rotate_cell()` transforms discrete tactical cells.
- `rotate_point()` transforms continuous X/Z authoring coordinates with the same pivot and direction.
- `rotate_direction()` transforms logical connector and facing vectors.
- `placement_yaw_radians()` converts the logical quarter-turn into Godot's opposite-sign Y rotation.

Asset-local normalization remains separate in each visual's `yaw_quarters`. This is why the straight road has a one-quarter source correction while the curve has a half-turn and the T/cross assets require none.

## Verification

- `coherent_geometry_contract_test.gd`: initially reproduced 12 failures, then passed. It covers the offset rectangular envelope, real `building-i` frontage, straight/T/cross/curve openings through all rotations and final-world road-owned lamp facing.
- Generation subsystem: 19 passed, 0 failed, 6 explicit-only.
- Smoke tier: 10 passed, 0 failed.
- Rendered capture: 30 fresh views across industrial, commercial and mixed-service identities. Roads were inspected overhead, obliquely and at intersections with diagnostic overlays disabled. Kit-only roads are continuous and no derived road layer remains underneath them.

The next recommended batch is F4 plus a deliberately small part of F5: resolve one versioned asset contract and certify one building-frontage/loading parcel with explicit access relationships before expanding the district grammar.
