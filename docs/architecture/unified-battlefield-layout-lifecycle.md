# Unified Battlefield Layout Lifecycle

Task 4.2 makes the Map Editor's coherent generated and edited-copy paths consume the versioned `BattlefieldLayoutDocument` introduced in Task 4.1. It does not migrate the editor's schema-1 save file or the normal battle entry point.

## Previous divergence

The coherent path was:

1. `FlatMapGenerator.generate_coherent_environment()` created flat tactical cells and initial deployment zones.
2. `CoherentEnvironmentAssembler` planned roads and parcels.
3. `EnvironmentModuleMapWriter` applied module-authored tactical effects.
4. The assembler moved invalid deployment cells onto the road-connected walkable region.
5. `GeneratedTerrainPresenter` presented `MapData.environment_modules` and inferred identity from `EnvironmentLayoutPlan`.

The edited path was materially different:

1. `_compose_current_layout()` copied only module component IDs and transforms.
2. `_build_custom_map()` generated a new flat map and therefore new flat deployment zones.
3. It reapplied module tactical effects but did not run coherent deployment repair.
4. It discarded environment identity, original generation provenance, parcel/template relationships, assembly dependencies, the plan, and repaired zones.
5. Presentation silently treated a map without a plan as `mixed_service`.

This made an unchanged editable copy semantically different from its source.

## Shared construction boundary

`BattlefieldLayoutDocumentCompiler` now performs editor tactical reconstruction:

1. Validate the document and its current content dependencies.
2. Create the base grid through `FlatMapGenerator` using the retained original seed for generated documents.
3. Restore preserved zone definitions when the document has them.
4. Reconstruct `EnvironmentModuleLayout` from stable placement records.
5. Apply tactical effects through the existing `EnvironmentModuleMapWriter`.
6. Revalidate deployment zones through `EnvironmentDeploymentResolver`.
7. Build and run the existing `MapValidator` checks.
8. Attach the validated document, modules, environment identity, reconstructed plan information, and zones to the compiled `MapData`.

The compiler does not inspect meshes for gameplay meaning. `MapData` remains authoritative for movement, stopping, cover, LOS, occupancy, and deployments.

## Edit-copy policy

`editable_copy()` is a deep document copy. It changes the current origin to `edited` while retaining `source_origin`, generator ID, original seed, configuration, environment identity, dependencies, placements, and relationships.

When the editor accepts a placement change:

- exact unchanged placements retain their stable IDs;
- changed and new placements receive new IDs;
- measured assembly-instance relationships are rebuilt against current placements;
- generated parcel/template relationships remain available but receive `requires_revalidation` because the current plan lacks exact placement-to-parcel ownership;
- dependencies are rebuilt from current resolved assets and assemblies;
- mission context is marked `requires_revalidation` until compilation succeeds.

The original displayed document is never mutated.

## Deployment policy

`EnvironmentDeploymentResolver` is the shared deterministic policy used by coherent generation and document compilation. It preserves every valid deployment cell. An illegal, duplicated, or disconnected cell moves to the nearest legal unused cell in the road-connected walkable region. Equivalent input order and geometry produce the same result.

The resolver reports `DEPLOYMENT_REPAIR_FAILED` when it cannot retain the required count. The document compiler treats that as failed construction. Other authored objective and extraction zones are never silently moved; the existing `MapValidator` reports them when an edit makes them invalid.

Schema-1 authored layouts have no persisted mission context. Until Task 4.3 migrates persistence, their documented legacy policy is to begin with deterministic flat deployments and pass them through the same resolver and validator.

## Presentation identity

The modular presenter now resolves identity in this order:

1. validated battlefield layout document;
2. existing hierarchical layout plan;
3. explicit `documented_legacy_fallback` for pre-document fixtures.

The selected identity and its source are attached to the `ModularEnvironment` root for inspection. An unsupported document or plan identity is an explicit failure and does not silently become mixed-service.

## Task 4.3 persistence requirements

Map Editor save/load intentionally remains on `MapEditorLayoutStore` schema 1. Task 4.3 still needs to:

- persist the full unified document rather than only module transforms;
- migrate existing schema-1 files to an explicitly identified legacy document;
- preserve edited provenance, placement IDs, relationships, dependencies, presentation configuration, and zones across restart;
- persist relationship validation states and deployment revalidation results;
- provide clear version migration and unsupported-version diagnostics;
- avoid treating the current in-memory lifecycle as proof of durable round-trip fidelity.

No normal gameplay generator or battle entry point changed in Task 4.2.
