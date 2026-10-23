# Phase 5.2: Mission and access reservations

Task 5.2 adds one bounded construction-time reservation ledger to coherent environment assembly. Reservations protect required space while modules are selected; they do not write traversal, cover, occupancy, or line of sight. `EnvironmentModuleMapWriter` and compiled `MapData` remain tactical authority.

## Placement-order audit

Before this task, coherent assembly committed content in this order:

1. road modules;
2. road signals, lights, poles, and optional barriers;
3. parcel discovery;
4. parcel buildings, machinery, and props;
5. tactical module effects;
6. deployment repair.

`FlatMapGenerator.generate()` already supplied deployment zones before coherent assembly began, but the assembler did not consult them. Objective and extraction zones are supported by `MapData` and layout persistence when a caller supplies them; the normal coherent generator does not author mission objectives. Consequently, required mission space could be consumed before the deployment resolver saw the completed tactical map. Frontage access was recorded only after a parcel was accepted, while furniture had already committed.

The coherent path now uses this order:

1. build the connected road topology;
2. reserve supplied deployment, objective, and extraction cells;
3. derive parcels and exact frontage spans;
4. evaluate each parcel on cloned layout and reservation state;
5. commit the parcel and its centered frontage approach together;
6. place optional road furniture around the accepted reservations;
7. compile tactical effects;
8. run the existing deterministic deployment resolver as final legality validation and narrow repair.

Furniture uses its own deterministic RNG stream. The parcel-planning stream is advanced by the same fixed variation draws consumed by the former ordering, preserving established parcel layouts while removing furniture's placement priority.

## Reservation contract

`EnvironmentSpatialReservationLedger` supports five roles:

| Role | Current source | Meaning |
| --- | --- | --- |
| `deployment_region` | preserved deployment zones | required faction deployment cells |
| `objective_region` | objective or extraction zones supplied by the caller | objective core or extraction space |
| `pedestrian_access` | building, forecourt, and alley parcel contracts | centered two-cell frontage approach, including the adjacent roadside cells |
| `loading_service_approach` | loading, staging, yard, and equipment parcel contracts | centered four-cell frontage approach, including the adjacent roadside cells |
| `circulation_clearance` | contract vocabulary for bounded authored use | shared circulation space; the current grammar does not synthesize a separate circulation network |

Ground-layer modules are compatible support surfaces. Occupant footprints and their authored clearances cannot consume a reservation. Pedestrian, loading/service, and circulation uses may overlap. Objective space may overlap access that provides its approach. Deployment may overlap pedestrian or circulation space, but it cannot overlap an unrelated loading/service reservation or a different mission core. Reservations from the same owner may overlap.

Reservation creation is transactional. A failed record never enters the ledger. Each parcel candidate uses cloned layout and reservation state, so rejection leaves neither modules nor orphaned access reservations. Optional parcel dressing and road-furniture failures are skipped without invalidating their required functional content or adding layout errors. Visual envelopes participate for `VISUAL_ONLY` furniture, whose one-cell marker does not fully describe poles and signal arms; structural and solid modules use their authored footprints and clearances so roof overhangs are not mistaken for blocked ground access.

## Layout-document lifecycle

Generated documents store compact reservation records under `spatial_layout.reservations`: stable identity, owner, role, purpose, required flag, source reference, cells, and validation state. Parcel access records reference the exact Task 5.1 frontage identity; mission records reference preserved zone identity. Cells are retained because they are the intended construction reservation used to reproduce and review an edited layout, rather than tactical occupancy inferred from a mesh.

Document validation checks role support, identity uniqueness, bounds, parcel/zone/frontage references, compatibility, and conflicts with non-ground placements. A placement edit retains reservation intent and marks it `requires_revalidation`. Compilation accepts a conflict-free edit and marks reservations validated with the mission context. An edit that places an obstacle in required deployment or access space fails with `RESERVED_REGION_BLOCKED`; it cannot silently move the mission around the new decoration.

The parcel grammar dependency is now `coherent_parcel_grammar_v3`. The generated and persisted edited reference documents were rebuilt with reservation records and current dependency signatures.

## Deployment repair policy

There is still one deployment algorithm: `EnvironmentDeploymentResolver`. Early reservations prevent coherent parcel occupants and optional furniture from invalidating preserved deployment cells. After tactical effects are compiled, the resolver validates actual `MapData` cells and performs its existing bounded nearest-cell repair only where supported. Failure remains `DEPLOYMENT_REPAIR_FAILED` and invalid construction is not reported as success.

Legacy documents without reservation intent retain the existing repair behavior. Reservation-bearing edited documents reject a newly introduced obstruction before compilation because their preserved construction intent is explicit.

## Verification

`coherent_mission_reservation_test.gd` covers:

- deployment and objective reservation creation;
- compatible and incompatible overlap;
- transaction rollback;
- exact frontage access bands;
- ground support versus occupant obstruction;
- deterministic fixed-seed assembly;
- furniture subordination;
- tactical deployment legality after compilation;
- an unsatisfiable mission overlap;
- generated-to-edited invalidation and rejection;
- save/load preservation and plan reconstruction.

Existing coherent assembly coverage now treats an unbuildable large parcel as valid only when it is an explicit mission-space buffer. The previous seed-2 regression was updated to protect the new contract: required parcel access wins and the conflicting optional fixture is skipped.

Executed checks:

- `godot_console --headless --path . --script res://tests/coherent_mission_reservation_test.gd` — pass;
- `coherent_layout_assembly_test.gd`, `parcel_spatial_contract_test.gd`, `battlefield_layout_lifecycle_test.gd`, `battlefield_layout_end_to_end_test.gd`, and `map_editor_layout_store_test.gd` — pass;
- `./tools/run_tests.ps1 subsystem -Subsystem missions` — 17 passed, 0 failed;
- the generation subsystem's first run passed 28 suites and exposed one obsolete editor edit-selection fixture; after making that fixture reservation-aware, its complete three-environment lifecycle rerun passed. The other 28 generation suites were not repeated without a new reason.

## Remaining scope for Task 5.3

- Enforce the Task 5.1 functional relationships across a broader parcel retry/orchestration policy.
- Decide how mission definitions request objective approach geometry before they create concrete `MapData` zones.
- Author dedicated circulation reservations only where a parcel contract needs them.
- Revalidate and repair relationship endpoints after supported editor moves instead of rejecting every conflicting edit.
- Integrate reservation-aware construction into any future gameplay generation entry point that bypasses coherent assembly. Legacy modular samples and authored layouts only gain reservation checks when their unified document contains reservation intent.
- Add elevation-aware reservation regions if future missions reserve stacked floors. The bounded Task 5.2 ledger intentionally protects X/Z columns used by today's ground-plane coherent generator.
