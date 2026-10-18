# Modular Environment Components

Goal 2.2 provides an opt-in modular environment system. Reusable components now assemble industrial, road, commercial/open-space, and vertical test regions without replacing the existing procedural generator.

## Architecture

`EnvironmentModuleDefinition` describes a stable component ID, explicit module type, logical footprint, clearance, allowed quarter-turn rotations, connections, tactical cell effects, elevated surfaces, vertical links, mission-suitability cells, and presentation references. It also records a semantic tactical role, placement layer, and visual snapping convention. `EnvironmentModulePlacement` records one deterministic placement and base elevation. `EnvironmentModuleLayout` rotates footprints and connectors, rejects same-layer overlaps and invalid clearances, validates elevation-aware connector compatibility, and resolves suitability cells into world coordinates.

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

The connection vocabulary includes `road`, `sidewalk`, `structure_edge`, `interior_access`, `exterior_access`, `alley`, `loading`, and `vertical`. Connections include a footprint-edge cell, an outward direction and an elevation. Quarter-turn placement rotates both the cell and direction. Identical types connect; sidewalk, alley, or loading access can connect to a compatible exterior entrance. Elevations must match.

Wall edges do not become entrances. A doorway has explicit interior and exterior access connectors, and the industrial builder verifies both connector matches and clear approach cells before committing its tactical effects.

## Component catalog

The catalog contains:

- Factory straight wall, inner corner, wide doorway, window wall, interior floor, and composite shop front.
- Straight road, road corner, T intersection, crossroad, paving, and a narrow alley.
- Courtyard and loading-dock spaces with authored mission-suitability cells.
- Cargo containers, individual machinery, a machinery cover cluster, and a vaultable construction barrier.
- Catwalk stairs, service ramp, maintenance platform, and elevated walkway with authored surfaces and vertical links.

Four constrained presets exercise the catalog: `industrial_frontage`, `loading_yard`, `road_and_shops`, and `vertical_works`. They cover connected road approaches, entrances, open spaces, layered cargo and machinery, and movement from ground to authored elevated surfaces. Every preset is deterministic for the same dimensions and seed. These remain working assembly fixtures rather than a general parcel grammar.

Suitability metadata identifies candidate spawn, objective, and extraction cells without creating mission zones automatically. Generation and tests resolve those candidates against the final authoritative `MapData`, require them to remain stoppable, and verify representative spawn-to-objective paths. Mission-aware assembly can later consume the same metadata before committing its layout.

Vertical modules add explicit elevated `MapCellData` surfaces and `TraversalLinkData`; meshes never create walkability. The stair and service-ramp definitions declare local endpoints, elevations, traversal kinds, and bidirectionality. Platforms and walkways declare their elevated cells. The shared translator rotates and places that data into the map, while the presenter renders calibrated models and neutral authored-surface markers.

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

## FuseFire Map Editor prototype

From the repository root:

```powershell
godot --path . res://tools/map_editor.tscn
```

Choose any implemented preset from the selector. Press `R` to rebuild the same seed. Press `[` or `]` to change the seed. A seed and optional preset can also be supplied after `--`:

```powershell
godot --path . res://tools/map_editor.tscn -- 7319
godot --path . res://tools/map_editor.tscn -- 7319 vertical_works
```

The Map Editor reports map validation status and presents all four presets through the same renderer. Its one-unit tactical grid makes visual overhang, elevated surfaces, and authored footprints inspectable. Left-click any visible module to select it without disturbing the current camera; the selected meshes receive a thin amber outline. **Inspect corner**, **Inspect road seam**, and **Next piece** (`Tab`) select and frame useful targets. Right-drag orbits, middle-drag pans, and the wheel zooms. **Front**, **Side**, and **Top** (or `1`, `3`, and `7`) change angle without losing the current target.

The selected-piece controls are a visual authoring scratchpad. Choose a step and use the X/Y/Z buttons or the arrow and Page Up/Page Down keys to move the module. `Q` and `E` rotate it by 90 degrees. **Reset** restores its authored transform, while **Copy transform** puts the component ID, offset, and yaw on the clipboard for transfer into the catalog. These edits affect only the current preview session; they never modify `MapData`, calibration JSON, or tactical footprints. `C`, `G`, and `F` focus the corner, road seam, and whole map.

## Adding a module

1. Add a definition to `IndustrialModuleCatalog` with a unique ID and family.
2. Declare its logical footprint and any extra clearance cells.
3. Assign the narrowest tactical role and add effects only for cells that must alter gameplay. Low obstacles intended for crossing should use the established vault contract rather than becoming solid blockers.
4. Add edge connections using the small semantic vocabulary.
5. Add a visual reference with explicit scale, yaw and offset. Keep uncertain assets behind placeholders until inspected.
6. Place it through `EnvironmentModuleLayout.try_add()` so bounds, overlap and clearance checks run.
7. Add a focused test for its connection or tactical contract.

## Validation

The component regression suite assembles every preset twice, compares deterministic signatures, reruns placement validation, checks published suitability cells, runs the general map validator, builds a tactical path between representative spawn and objective candidates, and verifies presentation dispatch. Focused assertions protect road rotation, layer overlap, doorway access, cover translation, vault behavior, and ground-to-elevated traversal.

## Current limitations

- Assembly uses four authored recipes with seeded visual variation; it does not search parcels or backtrack.
- Connections validate declared neighbors but open boundary connectors are not yet globally required to close.
- Logical non-overlap does not yet guarantee clean visual seams. Goal 2.3 must add authored socket transforms, clearance reservations, and diagnostic visual-envelope rejection for meshes that overhang their tactical footprints.
- Vertical links are demonstrated, but multi-floor buildings, stacked module placement, alternate-access requirements, and camera floor membership remain later work.
- Factory and Space Kit dimensions are not normalized or treated as interchangeable.
- The reviewed visual scales are available, but more structural assets still need authored footprints and connector decisions before joining the runtime catalog.
- Layering currently distinguishes ground, occupant, and overhead reservations. More complex compatibility masks are deferred until a real component needs them.
- Suitability metadata supplies candidates; mission planners do not yet reserve those cells before layout assembly.

