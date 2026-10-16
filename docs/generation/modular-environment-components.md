# Modular Environment Components

Goal 2.2 introduces a small, opt-in industrial module system. It proves that reusable environment pieces can assemble one coherent region without replacing the existing procedural generator.

## Architecture

`EnvironmentModuleDefinition` describes a stable component ID, logical footprint, clearance, allowed quarter-turn rotations, explicit connections, tactical cell effects and presentation references. `EnvironmentModulePlacement` records one deterministic placement. `EnvironmentModuleLayout` rotates footprints and connectors, rejects overlaps and invalid clearances, and validates connector compatibility.

The boundary is deliberate:

- Tactical cell effects are copied into `MapData`. These determine traversal, cover and line of sight.
- Visual references are stored with the definition and instantiated by `ModularEnvironmentPresenter`.
- Mesh bounds, imported collisions and visual overlap never change tactical legality.

The resulting placement list is retained on `MapData` as presentation metadata. Replay and tactical simulation continue to consume the authoritative cells.

## Connections

The first vocabulary is intentionally small: `road`, `sidewalk`, `structure_edge`, `interior_access` and `exterior_access`. Connections include a footprint-edge cell, an outward direction and an elevation. Quarter-turn placement rotates both the cell and direction. Identical types connect; sidewalk and exterior-access connections are also compatible. Elevations must match.

Wall edges do not become entrances. A doorway has explicit interior and exterior access connectors, and the industrial builder verifies both connector matches and clear approach cells before committing its tactical effects.

## Industrial catalog

The first catalog contains:

- Factory straight wall, corner, wide doorway and interior floor.
- Straight road, road corner and paved ground.
- A cargo-container obstacle.

The sample uses a constrained frontage template: connected road and paving, an interior floor, a wall run with a wide entrance, and seed-selected cargo variants. It is deterministic for the same dimensions and seed. This is a working assembly fixture rather than a general parcel grammar.

The presentation uses known integration conventions: City Kit Roads surfaces use the existing scale 9 calibration, Factory Kit structural pieces retain their known native modular convention, and the containers use the existing warehouse scale. No Asset Laboratory calibration or review state is changed.

## Inspecting the sample

From the repository root:

```powershell
godot --path . res://tools/modular_environment_preview.tscn
```

Press `R` to rebuild the same seed. Press `[` or `]` to change the seed. A seed can also be supplied after `--`:

```powershell
godot --path . res://tools/modular_environment_preview.tscn -- 7319
```

The preview reports map validation status and presents entrances, wall runs, connected ground and cargo obstacles. It does not start a battle or alter the default generation mode.

## Adding a module

1. Add a definition to `IndustrialModuleCatalog` with a unique ID and family.
2. Declare its logical footprint and any extra clearance cells.
3. Add tactical effects only for cells that must alter gameplay.
4. Add edge connections using the small semantic vocabulary.
5. Add a visual reference with explicit scale, yaw and offset. Keep uncertain assets behind placeholders until inspected.
6. Place it through `EnvironmentModuleLayout.try_add()` so bounds, overlap and clearance checks run.
7. Add a focused test for its connection or tactical contract.

## Current limitations

- Assembly is a single authored grammar with seeded visual variation; it does not search parcels or backtrack.
- Connections validate declared neighbors but open boundary connectors are not yet globally required to close.
- Only ground-level industrial pieces are supported. Multi-floor modules and vertical connectors remain separate work.
- Factory and Space Kit dimensions are not normalized or treated as interchangeable.
- The Factory structural pieces still need broader manual calibration before more wall families are added.
- Objective and spawn suitability metadata is not part of module definitions yet.

