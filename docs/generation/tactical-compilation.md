# Tactical compilation contract — T02

Implemented 2026-10-26 in `EnvironmentModuleMapWriter.apply`. This is the shared path for document compilation, coherent generation and modular presets. `MapData` remains authoritative. No new writer or runtime map representation was introduced.

## Passes and conflicts

1. Collect declarations with placement-ID diagnostics (legacy/generated placements without IDs use their signature for diagnostics only).
2. Establish elevated surfaces from existing or newly declared lower support cells. Relative elevation must be positive. Matching declarations at one coordinate are allowed only when support and complete surface properties agree, supporting the existing stairs/platform shared edge. Different support/properties reject. Existing target surfaces must agree; they are never silently replaced. World position derives from support and the existing cell-size convention.
3. Apply sparse cell effects to existing surfaces. Missing surfaces reject instead of silently dropping effects. Within a placement layer, unequal explicit claims for the same field reject; identical claims or disjoint fields combine. Across layers and the baseline map, use the reductions below.
4. Validate traversal endpoints against the resulting cells. Both must exist and be walkable. They need not be stoppable (the existing vault traversal contract). Existing traversal declarations and directionality are retained.
5. Commit only when every pass succeeds. Callers then perform deployment/mission binding, graph/LOS rebuilding and their existing validation. A failed writer call changes neither cells nor traversal lists; the document compiler returns no partially compiled map.

| Effect | Composition with the surface/baseline and other layers |
| --- | --- |
| `walkable`, `can_stop` | Logical AND; nonwalkable cells cannot be stopped on |
| `blocks_los` | Logical OR |
| `cover_type`, `cover_height` | Maximum (existing NONE/LOW/FULL order; height scaled by cell size) |
| `movement_cost` | Maximum, retaining the existing minimum of one |
| Omitted field | No contribution |

These are restrictions/additions, not overrides: an effect cannot reopen a blocked baseline, remove cover/LOS blocking, or lower its movement cost. Changing the source restriction and recompiling is the supported edit. Explicit override operations are deferred; insertion order is never an override. Surface declarations establish complete defaults, unlike sparse effects. Non-tactical metadata such as `interaction` remains with its existing consumers; it is not a new `MapCellData` field.

All claim conflicts reject with codes, coordinates and source references. Commit ordering is canonical for cells and links; sorting does not determine which claim wins. Existing cell objects, world position, elevation and hazard references are preserved when applying effects. Spatial placement legality, elevated occupancy volumes and whole-column policy remain T03, rather than being duplicated in this writer.

## Regression evidence

`tests/modular_environment_map_writer_test.gd` checks six permutations (including ID ordering that defeats a sorting-only fix), sparse effects, blocked baseline preservation, upper-floor consumers before their surfaces, shared surface declarations, incompatible surfaces/effects, missing surfaces/support/endpoints, blocked endpoints, transactional rejection, and rejection propagation through the real document compiler. Surface/effect unit fixtures bypass spatial reservation so these checks do not accidentally depend on T03.

Existing modular presets, rotated street-frontage, Generation 2 tactical gameplay and edited-map replay suites provide compatibility checks. Results and commands are recorded in the redesign progress ledger. Headless results establish tactical contracts, not visual correctness.
