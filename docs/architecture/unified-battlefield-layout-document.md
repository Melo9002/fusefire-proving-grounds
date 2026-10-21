# Unified Battlefield Layout Document

Task 4.1 introduces `BattlefieldLayoutDocument`, a compact, versioned record of battlefield construction intent. It can describe a representative coherent generated district and a representative authored Phase 3 composition without making the document a gameplay map, scene graph, or duplicate asset catalog.

## Pipeline audit

Before this task, the relevant state crossed several boundaries:

| Concern | Existing owner | Authority | Previous lifecycle result |
| --- | --- | --- | --- |
| Tactical cells, traversal, cover, LOS and zones | `MapData` | Runtime tactical authority | Preserved only in the compiled map instance |
| Hierarchical district identity, seed, topology, roads and parcels | `EnvironmentLayoutPlan` | Generation-plan intent | Attached to coherent `MapData`; lost by Map Editor copy/save |
| Module identity and transforms | `EnvironmentModulePlacement` / `EnvironmentModuleLayout` | Environment construction intent | Preserved by editor JSON |
| Visual/tactical placement contracts | `EnvironmentModuleDefinition` | Catalog authority | Re-resolved by stable component ID |
| Imported geometry and calibration | asset/calibration catalogs | Presentation dependency authority | Previously absent from layout persistence |
| Certified Phase 3 assemblies | `EnvironmentAssemblyContract` and `InitialEnvironmentAssemblyLibrary` | Reusable assembly contract | Previously absent from layout persistence |
| Authored Map Editor JSON | `MapEditorLayoutStore` schema 1 | Editor-local persistence | Stores only layout ID, map size and placement transforms |
| Presentation mode | presenter configuration | Derived presentation choice | Previously implicit |

`MapEditorLayoutStore` is the main lossy boundary. It retains enough data to recreate module placement but loses environment identity, authored/generated provenance, generator configuration, parcel/template and assembly relationships, resolved assets, dependency revisions, zones, and presentation intent. “Edit copy” has the same limitation because it copies only module placements and size.

The coherent generator already publishes exact road and parcel planning in `EnvironmentLayoutPlan`. The plan does not currently associate every produced placement with its owning parcel, nor does it retain a general access graph. Task 4.1 preserves the parcel/template relationships that exist and records that limitation rather than synthesizing ownership.

The current editor can preserve `MapZoneData` when a compiled `MapData` is supplied, but it cannot author general mission or objective definitions. Documents created only from an authored module layout therefore use `mission_context.status = "not_represented"`. They do not invent deployments or objectives.

## Schema version 1

The top-level fields are:

- `schema_version`, `document_id`, and `environment_id` establish identity.
- `provenance` records `authored`, `generated`, or `edited` origin, generator ID, the presence and value of a seed, generation configuration, and known algorithm revisions.
- `spatial_layout` records map size, the fixed FuseFire X/Z grid convention, one-unit cell scale, and ordered module placements.
- Each placement records a stable placement ID, component ID, origin, quarter-turn rotation, variation, elevation, assembly reference, and the imported assets resolved for that variation.
- `relationships` records assembly instances, certified authored templates, and generated parcel/template assignments.
- `dependencies` pins imported asset geometry and calibration signatures, assembly certification signatures, and the parcel-grammar revision.
- `mission_context` either preserves existing zones or explicitly reports that mission information was unavailable.
- `presentation` records the requested asset-first or legacy road presentation path.

The document preserves source placement order. Both current producers already produce deterministic order, so this retains fidelity without changing overlap precedence or creating a second canonical sorter.

Examples generated through the production conversion helpers are checked in at:

- [Generated industrial seed 2208](examples/generated-industrial-layout-document.json)
- [Authored certified service pad](examples/authored-service-pad-layout-document.json)

## Authority and reconstruction

The document owns intended construction identity, provenance, placement transforms, stable references, dependency expectations, and any preserved zone definitions. `to_module_layout()` reconstructs only the module placement layout and reuses `IndustrialModuleCatalog`; it does not instantiate meshes, compile tactical effects, repair deployments, or recalculate objectives.

`EnvironmentModuleMapWriter` remains responsible for compiling explicitly authored module effects into `MapData`. `MapData` remains authoritative during gameplay for traversal, stopping, cover, LOS, occupancy, elevation, and zones. Imported meshes and their bounds remain presentation inputs. The document's asset references make rendering reproducible and stale dependencies detectable; they never create gameplay collision.

Assembly placements reference the established Phase 3 contracts. The document stores a compact certification signature instead of copying component definitions, sockets, clearances, or tactical footprints. Asset dependencies similarly reference stable asset IDs and record current geometry/calibration revisions instead of embedding catalog data.

## Validation

Validation returns structured failures with `code`, `field`, `reference`, and `message`. It checks:

- supported schema, environment, grid convention, cell scale, presentation mode, and dimensions;
- consistent authored/generated provenance;
- unique placement IDs, catalog references, origins, supported rotations, bounds, clearances, and visual reservations through the real module layout contract;
- relationship referential integrity;
- required asset, assembly, and template dependencies;
- current geometry, calibration, assembly-certification, and parcel-grammar revisions;
- preserved zone identity, shape, and horizontal bounds.

Validation never substitutes a default environment and never recompiles tactical state.

## Remaining integration work

Task 4.1 does not replace Map Editor JSON or gameplay entry points. Later integration needs to:

1. migrate Map Editor save/load and “Edit copy” through the document while preserving schema-1 compatibility;
2. define the edited-origin provenance transition and whether generated plan detail remains attached after a user edit;
3. connect document validation to authoring diagnostics;
4. decide how full mission definitions are represented once the editor can author them;
5. add explicit placement-to-parcel ownership and general frontage/access relationships when those contracts exist;
6. compile a validated document through existing writers without changing `MapData` authority.

These are integration tasks. The Task 4.1 conversion helpers are deliberately narrow and have no runtime consumer.
