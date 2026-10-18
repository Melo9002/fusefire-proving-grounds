# Modular Environment Components

Goal 2.2 introduces a small, opt-in industrial module system. It proves that reusable environment pieces can assemble one coherent region without replacing the existing procedural generator.

## Architecture

`EnvironmentModuleDefinition` describes a stable component ID, logical footprint, clearance, allowed quarter-turn rotations, explicit connections, tactical cell effects and presentation references. It also records a semantic tactical role, placement layer, and visual snapping convention. `EnvironmentModulePlacement` records one deterministic placement. `EnvironmentModuleLayout` rotates footprints and connectors, rejects same-layer overlaps and invalid clearances, and validates connector compatibility.

The boundary is deliberate:

- Tactical cell effects are copied into `MapData`. These determine traversal, cover and line of sight.
- Visual references are stored with the definition and instantiated by `ModularEnvironmentPresenter`.
- Mesh bounds, imported collisions and visual overlap never change tactical legality.

Placement reservations are layered. `ground` modules reject other ground modules in the same cells, while `occupant` modules reject other occupants. Ground and occupant footprints may overlap, so a container, barrier, machine, or building section can sit on concrete without removing the concrete surface. `overhead` is reserved for future presentation pieces that need independent placement. Tactical effects are still applied once from every placed definition; layering does not merge or infer gameplay rules.

The first explicit tactical roles are `ground`, `structure`, `solid_obstacle`, `vaultable_obstacle`, and `visual_only`. Cell interactions refine this into `open`, `blocked`, `vault`, and `walk_over`. These labels explain authored intent; the copied `MapCellData` remains authoritative.

- Roads and paving are ground presentation. They add no blocking cells.
- Containers are solid tactical obstacles. Their authored cells block movement and line of sight and provide full cover.
- The construction barrier is vaultable. Its cell uses FuseFire's existing low-cover contract: traversable, non-stoppable, movement cost 2, and the presentation path selects the `vault` animation.
- A future walk-over prop can use the explicit `walk_over` interaction without receiving low-cover or forced-vault behavior.

The resulting placement list is retained on `MapData` as presentation metadata. Replay and tactical simulation continue to consume the authoritative cells.

## Connections

The first vocabulary is intentionally small: `road`, `sidewalk`, `structure_edge`, `interior_access` and `exterior_access`. Connections include a footprint-edge cell, an outward direction and an elevation. Quarter-turn placement rotates both the cell and direction. Identical types connect; sidewalk and exterior-access connections are also compatible. Elevations must match.

Wall edges do not become entrances. A doorway has explicit interior and exterior access connectors, and the industrial builder verifies both connector matches and clear approach cells before committing its tactical effects.

## Industrial catalog

The first catalog contains:

- Factory straight wall, corner, wide doorway and interior floor.
- Straight road, road corner and paved ground.
- A cargo-container obstacle.
- A one-cell vaultable construction barrier.

The sample uses a constrained frontage template: connected road and paving, an interior floor, a wall run with a wide entrance, and seed-selected cargo variants. One container and the vaultable barrier are deliberately layered over the paving surface. It is deterministic for the same dimensions and seed. This is a working assembly fixture rather than a general parcel grammar.

The presentation uses the developer-reviewed calibration: City Kit Roads surfaces use a ten-unit pitch, Factory structure pieces use the scale-2 baseline and integer visual anchors, containers use their scale-5 overrides, and the construction barrier uses scale 5. Factory facades retain source-origin anchoring and join on the kit's native two-unit rhythm. Runtime Factory structure meshes use a 2.01 presentation scale (a 0.5% seam bleed) so their closed end-cap faces do not z-fight; logical footprints and connections remain on integer boundaries. These values are copied deliberately into module definitions; loading a map never edits Asset Laboratory calibration or review state.

The current authored footprints are deliberately different from raw visual bounds where the tactical meaning demands it:

| Component | Logical footprint | Visual convention | Tactical meaning |
| --- | ---: | --- | --- |
| Straight road / paving | 10 × 10 | 10-unit integer pitch | Open ground |
| Road curve | 20 × 20 | Two road pitches | Open ground |
| Factory wall run | 4 × 1 | Two 2-unit wall bays | Blocking full cover |
| Wide doorway | 4 × 1 | One 4-unit entrance bay | Blocking jambs, two open center lanes |
| Factory corner | 2 × 2 | Scale 2 on the intended integer junction | Blocking junction |
| Container | 2 × 5 | Scale 5; the visual slightly exceeds four cells in length | Solid obstacle |
| Construction barrier | 1 × 1 | Scale 5 | Vaultable low cover |

Visual placement may use half-unit offsets for props whose authored pivots require them; the scale-two Factory structure family aligns on integers. Module origins, connections, and tactical effects remain integer grid cells. Thin road and paving meshes use a shared 0.02-unit presentation lift above the preview base plane; this removes z-fighting without changing their tactical elevation or introducing collision.

## Inspecting the sample

From the repository root:

```powershell
godot --path . res://tools/modular_environment_preview.tscn
```

Press `R` to rebuild the same seed. Press `[` or `]` to change the seed. A seed can also be supplied after `--`:

```powershell
godot --path . res://tools/modular_environment_preview.tscn -- 7319
```

The preview reports map validation status and presents entrances, wall runs, connected ground, cargo obstacles, and the vaultable barrier. Its one-unit tactical grid makes visual overhang and authored footprints inspectable. Left-click any visible module to select it without disturbing the current camera; the selected meshes receive a thin amber outline. **Inspect corner**, **Inspect road seam**, and **Next piece** (`Tab`) select and frame useful targets. Right-drag orbits, middle-drag pans, and the wheel zooms. **Front**, **Side**, and **Top** (or `1`, `3`, and `7`) change angle without losing the current target.

The selected-piece controls are a visual authoring scratchpad. Choose a step and use the X/Y/Z buttons or the arrow and Page Up/Page Down keys to move the module. `Q` and `E` rotate it by 90 degrees. **Reset** restores its authored transform, while **Copy transform** puts the component ID, offset, and yaw on the clipboard for transfer into the catalog. These edits affect only the current preview session; they never modify `MapData`, calibration JSON, or tactical footprints. `C`, `G`, and `F` focus the corner, road seam, and whole map.

## Adding a module

1. Add a definition to `IndustrialModuleCatalog` with a unique ID and family.
2. Declare its logical footprint and any extra clearance cells.
3. Assign the narrowest tactical role and add effects only for cells that must alter gameplay. Low obstacles intended for crossing should use the established vault contract rather than becoming solid blockers.
4. Add edge connections using the small semantic vocabulary.
5. Add a visual reference with explicit scale, yaw and offset. Keep uncertain assets behind placeholders until inspected.
6. Place it through `EnvironmentModuleLayout.try_add()` so bounds, overlap and clearance checks run.
7. Add a focused test for its connection or tactical contract.

## Current limitations

- Assembly is a single authored grammar with seeded visual variation; it does not search parcels or backtrack.
- Connections validate declared neighbors but open boundary connectors are not yet globally required to close.
- Only ground-level industrial pieces are supported. Multi-floor modules and vertical connectors remain separate work.
- Factory and Space Kit dimensions are not normalized or treated as interchangeable.
- The reviewed visual scales are available, but more structural assets still need authored footprints and connector decisions before joining the runtime catalog.
- Layering currently distinguishes ground, occupant, and overhead reservations. More complex compatibility masks are deferred until a real component needs them.
- Objective and spawn suitability metadata is not part of module definitions yet.

