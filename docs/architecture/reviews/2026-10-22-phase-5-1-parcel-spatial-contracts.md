# Phase 5.1 parcel spatial contracts

Date: 2026-10-22

## Pipeline audit

`CoherentEnvironmentAssembler` retains the existing hierarchy: it creates the macro road plot, reserves non-overlapping 20×20 parcels, fills remaining 10×10 lots, chooses one bounded authored recipe, and commits the recipe's module placements through `EnvironmentModuleLayout.try_add()`.

Before this task, three lifecycle boundaries discarded useful facts:

- `_road_edges_for_macro_rect()` retained only a cardinal direction when any adjacent macro road cell existed. It could not describe a partial or disconnected frontage.
- The accepted placement batch was appended to the layout, but the parcel did not retain ownership of those placements or distinguish required occupants from optional dressing.
- The Phase 4 document serialized each parcel's template and bounds as a relationship, but did not serialize ownership or positioned frontage geometry.

Road/module connectors remain physical adjacency contracts between modules. They are not reused as parcel access relationships.

## Contract

The existing plan now records, for every parcel:

- Stable parcel identity and grid bounds.
- Accepted occupant placement signatures and whether each is required.
- Exact frontage spans calculated from actual road-module footprint cells.
- The road placement signatures contributing to each span.

Frontage spans use world-grid X/Z coordinates and half-open boundary endpoints. A span records an outward cardinal direction, `start`, `end`, `width_cells`, a one-cell initial clearance depth, and all adjacent road references. Contiguous cells merge into one interval; gaps always create separate intervals. Multiple boundaries are independent.

`BattlefieldLayoutDocument.spatial_layout.parcels` resolves plan signatures to stable document placement IDs. It stores parcel bounds, recipe identity, rotation, owned placements, road references, frontage spans and validation state. This is an additive part of the existing unified document, not a second layout format.

The bounded relationship vocabulary is:

- `frontage_to_street`: a measured frontage span and an adjacent road placement.
- `pedestrian_access`: a parcel and its selected frontage region.
- `loading_access`: a loading-oriented parcel and frontage region.
- `service_clearance`: an equipment parcel and frontage region used as the external service approach.
- `required_occupant`: parcel ownership of a required or optional occupant, distinguished by the record's `required` value.

These records describe construction intent. Task 5.1 validates identity, geometry and referential integrity; it does not prove a walking route, reserve mission space, retry recipes, or enforce every functional relationship.

## Validation behavior

Document validation rejects:

- Missing or duplicate parcel/frontage identities.
- Empty or out-of-map parcel bounds.
- Missing occupants and ambiguous ownership by multiple parcels.
- Non-cardinal, reversed, off-boundary or incorrectly sized frontage intervals.
- Frontages without an adjacent road.
- References to non-road placements.
- A claimed interval containing a cell that is not covered by one of its referenced road modules.
- Functional relationships with unresolved or incorrectly typed endpoints.

Editing retains parcel and relationship identity. A changed layout marks parcel records and dependent relationships `requires_revalidation`. Moving or removing an owned placement makes its stale ownership reference visibly invalid until a later relationship-aware operation repairs or reauthors it.

## Compatibility and observed behavior

The tracked industrial seed 2208 has the same 28 module placement signatures before and after this change. The new records do not alter template selection, tactical placement, traversal, cover, LOS or presentation.

Documents created before Phase 5.1 remain valid because parcel records are additive. Newly generated documents pin `coherent_parcel_grammar_v2`. The tracked generated and edited examples were rebuilt with ownership, frontage, functional relationships and current dependencies.

## Verification

Focused regression coverage in `parcel_spatial_contract_test.gd` independently exercises:

- Full, partial and disconnected frontage.
- Multiple street-facing boundaries.
- No frontage.
- Asymmetric geometry on a vertical/quarter-turned boundary.
- Stable and unique ownership.
- Missing occupants, duplicate ownership and invalid road references.
- Deterministic generation and document serialization.
- Schema-2 encode/decode preservation.
- Explicit invalidation after editing an owned placement.

Relevant commands:

```powershell
godot_console --headless --path . --script res://tests/parcel_spatial_contract_test.gd
godot_console --headless --path . --script res://tests/battlefield_layout_end_to_end_test.gd
godot_console --headless --path . --script res://tests/coherent_layout_assembly_test.gd
godot_console --headless --path . --script res://tests/map_editor_layout_store_test.gd
.\tools\run_tests.ps1 subsystem -Subsystem generation
.\tools\run_tests.ps1 subsystem -Subsystem ui
```

Results:

- Parcel spatial contract suite: 0 failures.
- Phase 4 three-identity editor lifecycle: 0 failures.
- Coherent layout assembly: 0 failures.
- Map Editor persistence: 0 failures.
- Generation subsystem: `PASS=28 FAIL=0 SKIP=11` in 661.89 seconds. Skips are the documented visual/stress-only scripts.
- UI subsystem: `PASS=16 FAIL=0 SKIP=1` in 113.89 seconds. The skip is the explicit Debug Draw capture.

## Task 5.2 boundary

Task 5.2 can use these records to validate specific pedestrian, loading and service routes and to reserve their cells before conflicting content is committed. It will need a bounded policy for selecting among multiple frontage spans and for updating ownership after intentional placement moves. Mission reservations, local retry orchestration and furniture sequencing remain outside Task 5.1.
