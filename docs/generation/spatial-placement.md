# Spatial placement contract — T03

Implemented 2026-10-26. `EnvironmentSpatialQueries` owns pure construction-space geometry. Module layout, reservation ledger, document validation, editor acceptance and the existing tactical writer consume it. Canonical module rotation remains in `EnvironmentModuleDefinition`; there is no second tactical writer.

## Coordinates and extents

- Positions and elevations remain integer cells; rotations remain supported quarter turns. Continuous visual envelopes use the existing cell-center convention. A cell centered at X/Z covers ±0.5, rather than the ledger's previous asymmetric X..X+1 approximation. The existing 0.01 visual seam tolerance remains.
- Footprints reserve `[placement.elevation, elevation + occupancy_height)`. Default height is one cell, a bounded legacy construction reservation, **not** an inferred mesh measurement. Calibrated visual envelopes are checked separately. New content must declare an appropriate occupancy height and envelope; T03 does not certify missing asset measurements.
- Clearance cells reserve `[elevation, elevation + clearance_height)`, default two cells. Both intervals must be finite; clearance must be positive. Zero occupancy is only valid for modules declaring surfaces. Negative base elevations are unsupported in the pilot.
- Ground remains a composable surface layer. Occupants and overhead content cannot evade collision by choosing different layers. Occupancy, visual envelopes and clearance are checked symmetrically; touching interval boundaries are allowed. Clearances may overlap each other.
- The existing platform/walkway definitions now explicitly declare zero solid-column occupancy. Their elevated surfaces still prevent an object or clearance volume from passing through a floor. Matching surface declarations at the stairs/platform edge retain T02's agreement rule.

## Support and headroom

Incremental `try_add` checks geometry, not whether a future placement will supply a floor. Completed-layout validation resolves positive elevated-surface dependencies in elevation order, rooted in the pilot's bounded ground plane. Every footprint and clearance cell needs a surface at its placement elevation. Matching X/Z on different supported floors is legal.

Document validation and editor edit acceptance use that completed-layout query. Unsupported editor edits reject before changing the current document/layout. Tactical compilation also verifies support against its actual existing and staged MapData surfaces, including visual-only occupants. Thus standalone population cannot silently place floating props.

The pilot requires at least **two cell units between floor planes**. A floor cannot cut through another placement's occupied span, visual envelope or clearance. Existing elevated MapData floors are respected when adding occupants. The writer remains transactional on rejection. A component's own declared surfaces are internal to its authored contract; this is not a general structural engineering or arbitrary stacking solver.

Error codes include `MISSING_PLACEMENT_SUPPORT`, `MISSING_SURFACE_SUPPORT`, `INSUFFICIENT_HEADROOM`, and `SURFACE_INTERSECTS_VOLUME`. Source validation now catches unsupported documents before the older missing-effect-surface failure; the T02 regression assertion was updated to this intentional earlier rejection.

## Reservations and semantic policy

Reservation records retain their existing cells, roles and ownership. Two scopes are supported:

| Scope | Geometry |
| --- | --- |
| `whole_column` | Every elevation at the listed X/Z cells |
| `floor` | Explicit nonnegative integer `elevation` and positive finite `height` |

JSON encoding preserves scope/span; integral JSON numbers are normalized on load. Missing scope in a supported legacy record means `whole_column`, preserving protection without inventing any approval. Mission-generated records now specify whole-column scope explicitly. Floor reservations can overlap in X/Z when their height intervals are disjoint; incompatible roles still reject where volumes overlap.

`contains_at(role, Vector3i)` is elevation-aware. Existing `contains(role, Vector2i)` intentionally remains a projected query for two-dimensional parcel planning. Ground permission, same-owner exceptions and role compatibility remain ledger policies; they were not merged into the geometry utility. Parcel relationship validation reuses the shared footprint transform while retaining its own access rules.

## Existing preset corrections

Stricter envelope checks exposed previously accepted intersections:

- Loading-yard machinery cluster moved from `(18,4)` to `(17,4)` to clear the neighboring cargo service reservation.
- Vertical-works machine moved from `(8,14)` to `(7,14)` so its 2.7-cell envelope no longer passes through the level-two platform edge.

Other fixture assertions, floor coordinates, traversal endpoints and gameplay expectations remain intact. An intermediate visual/cell comparison exposed a rotation-dependent false positive in the equipment fixture; correcting the shared cell-center convention removed it, rather than changing that fixture or weakening its assertions.

## Verification and limits

`modular_elevation_spatial_test.gd` covers both insertion orders and all rotations of a 2×3 footprint, supported floors, independently calculated rotated cells/traversal endpoints, playable traversal paths, intersecting occupied/visual volumes, symmetric headroom rejection, unsupported visual occupants, existing-map floor protection, transactional rejection, rejected editor edits, explicit mission columns, and actual reservation JSON round trips.

See the redesign progress ledger for compatibility results and commands. No fresh visual approval is claimed for the two moved props. No arbitrary polygons, mesh-derived tactical occupancy, unrestricted stacking, basement support, new editor undo UI or general structural solver was introduced. T04 must include these spatial fields in its behavior-sensitive dependency/resolution audit.
