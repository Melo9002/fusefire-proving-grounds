# Spatial Transform Convention

FuseFire module rotations are quarter turns on the tactical X/Z grid. `EnvironmentModuleDefinition` is the authoritative owner of the module-local to placed-grid transform. Tactical data, presentation code, diagnostics, and authoring tools must use its transform methods rather than defining another rotation convention.

## Axes and quarter turns

Grid and world axes correspond directly:

| Grid direction | Grid vector | Godot world direction |
| --- | --- | --- |
| Right | `(+1, 0)` | `+X` |
| Left | `(-1, 0)` | `-X` |
| Down | `(0, +1)` | `+Z` (`Vector3.BACK`) |
| Up | `(0, -1)` | `-Z` (`Vector3.FORWARD`) |

Rotation values have the following authoritative meaning:

| Rotation | Local `+Z` becomes | Local `+X` becomes | Godot Y yaw |
| ---: | --- | --- | ---: |
| 0 | `+Z` | `+X` | `0°` |
| 1 | `-X` | `+Z` | `-90°` |
| 2 | `-Z` | `-X` | `-180°` |
| 3 | `+X` | `-Z` | `-270°` (equivalent to `+90°`) |

Positive module rotation follows the existing grid convention used by `rotate_cell()` and `rotate_direction()`. Godot's positive Y rotation turns the opposite way in X/Z, so a module quarter turn becomes a negative Godot yaw. Authored rotation meaning is preserved; presentation performs the sign conversion.

## Authoritative operations

`EnvironmentModuleDefinition` provides the shared operations:

- `rotate_cell()` rotates discrete footprint, occupancy, clearance, suitability, elevated-surface, and connector cells within the module's rectangular lattice.
- `rotate_point()` rotates continuous module-local X/Z coordinates with the same convention and rectangular pivot.
- `rotate_direction()` rotates direction vectors without translation.
- `placement_yaw_radians()` converts a module rotation into the corresponding Godot Y yaw.

For a module of cell dimensions `(width, depth)`, continuous points transform as follows before placement-origin translation:

| Rotation | Transformed point `(x, z)` |
| ---: | --- |
| 0 | `(x, z)` |
| 1 | `(depth - 1 - z, x)` |
| 2 | `(width - 1 - x, depth - 1 - z)` |
| 3 | `(z, width - 1 - x)` |

This pivot matches the discrete cell transform. It also handles rectangular and offset geometry; repeated square-only quarter-turn formulas are invalid.

## Placement and presentation order

Module visuals use this order:

1. Rotate the authored `local_cell` with `rotate_point()`.
2. Translate it by the placement's grid origin through the authoritative `MapData` cell world position and `cell_size`.
3. Add authored placement elevation in world Y.
4. Rotate module-local visual and calibrated anchor offsets using `placement_yaw_radians()`; then add them to the world anchor.
5. Apply the module yaw to the imported wrapper.
6. Compose any visual `yaw_quarters` as an asset-to-module normalization before the same module-yaw conversion.
7. Add the Asset Lab's calibrated `yaw_degrees` as an asset-local Godot correction.
8. Let `EnvironmentAssetPlacement` resolve the requested visual anchor from the fully rotated imported mesh bounds.

The three angles have distinct meanings:

- `placement.rotation` describes the authored module's orientation in the tactical grid.
- `visual.yaw_quarters` normalizes a particular source mesh to the module's local axes. For example, the straight-road mesh requires one source-to-module quarter turn.
- Asset Lab `yaw_degrees` is a saved correction inside the imported asset's visual calibration. It does not change module connectors, footprints, or tactical orientation.

Do not move an asset-local correction into `placement.rotation`, or use calibration yaw to repair a module contract. Y rotations can be numerically added, but their ownership must remain separate so metadata and authored gameplay meaning do not drift.

## Consumers

- `EnvironmentModuleMapWriter` rotates tactical effects, elevated surfaces, and vertical links through `rotate_cell()`.
- `EnvironmentModuleLayout` rotates occupied cells, clearance, connections, suitability, and every visual-envelope corner through the definition contract.
- `CoherentEnvironmentAssembler` rotates authored furniture and obstacle slots through `rotate_cell()`.
- `ModularEnvironmentPresenter` uses `rotate_point()` for anchors and derived geometry, and `placement_yaw_radians()` for imported meshes, boxes, and module-local offsets.
- The Map Editor reads the same layout and presentation results for spatial diagnostics.

Direct `rotation.y = quarter * PI / 2` calculations are not valid for environment-module placement. Systems with unrelated orientation semantics, such as character aiming or extraction-transport presentation, are outside this contract.

## Visual-envelope coordinates and reservation

`visual_envelope` is an optional module-local continuous `AABB`. Its X/Z values use the same cell/world-unit authoring coordinates as visual anchor points; they are not a set of occupied grid cells. Cell centers span `(0, 0)` through `(width - 1, depth - 1)`, and an envelope may extend beyond those centers or begin at a negative offset. Y is a continuous height relative to the module's base elevation.

`EnvironmentModuleLayout.world_visual_envelope()` transforms all eight AABB corners with `rotate_point()`, preserves each corner's Y, translates by placement origin and elevation, and encloses the transformed points. This is required for rectangular modules and offset envelopes; rotating only AABB size or repeatedly applying one stale dimension is invalid.

After the enclosing bounds are calculated, the reservation shrinks by `0.01` on every face when all three dimensions exceed `0.02`. This intentional seam epsilon permits authored envelopes that merely touch at their boundaries. Same-layer bounds with positive volume intersection are rejected by `try_add()`.

Visual reservations do not add tactical cells, clearance, collision, traversal, cover, or line-of-sight behavior. Tactical footprint checks run separately, and visual envelopes on different placement layers do not conflict.

## Protected invariants

This transform does not infer gameplay geometry from meshes. `MapData` remains authoritative for occupancy, traversal, cover, line of sight, elevation, and movement. Imported bounds and calibrated transforms remain presentation and placement-validation data.

`tests/coherent_geometry_contract_test.gd` protects the explicit direction/point/yaw table, connector placement, asymmetric building frontage, imported road openings, and final-world streetlight facing. `tests/coherent_visual_envelope_test.gd` independently protects rectangular and offset visual-envelope transforms, seam tolerance, and placement reservations.
