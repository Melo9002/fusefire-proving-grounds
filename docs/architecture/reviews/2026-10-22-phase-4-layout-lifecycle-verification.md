# Phase 4 layout-document lifecycle verification

Date: 2026-10-22
Scope: Generation 2.0 Task 4.4. This review validates the Phase 4 architecture and applies one narrow dependency-resolution correction. It does not activate a gameplay entry point or implement Phase 5 relationships.

## Tested lifecycle

`battlefield_layout_end_to_end_test.gd` drives the real Map Editor scene, document compiler, presenter and schema-2 layout store for this deterministic matrix:

| Environment | Seed | Generated configuration | Representative edit |
| --- | ---: | --- | --- |
| `industrial_district` | 2208 | T junction, macro size 10, coherent parcel grammar v1 | Place an authored vaultable barrier on a deployment cell, forcing deterministic deployment repair |
| `mixed_service` | 11027 | Stored topology and plan signature, macro size 10, coherent parcel grammar v1 | Change one contextual asset variation |
| `commercial_street` | 7319 | Stored topology and plan signature, macro size 10, coherent parcel grammar v1 | Change one contextual asset variation |

For each case the test generates and presents the environment, creates an independent editable copy, edits a real placement, recompiles it, saves through the Map Editor, clears the working state, reloads through the Map Editor, then reconstructs tactical and presentation state twice.

The checks establish that:

- Environment identity, generated source provenance, original seed/configuration, algorithm revisions and unchanged placement IDs survive.
- The representative edit survives and is not overwritten by regeneration from the preserved seed.
- Required parcel and assembly references survive. Relationships affected by an edit remain explicitly marked `requires_revalidation`; Phase 4 does not claim semantic parcel reapproval without a relationship solver.
- Deployment context changes from `requires_revalidation` to `validated` after successful compilation. The obstructed industrial spawn is moved, and repeated reconstruction chooses the same repaired deployment.
- Tactical cell state, authored module placements and deployment zones reproduce after disk reload.
- Presenter identity, module count, logical rotations and variations agree with the same reloaded document.
- Imported asset, calibration and assembly dependency records survive semantically unchanged.
- An impossible deployment produces `DEPLOYMENT_REPAIR_FAILED` rather than a partial map.

## Correction found during validation

Generated documents referenced several legitimate authored assemblies such as `city_industrial_shell_e` and `loading_canopy`. Phase 4 previously resolved only the three examples in `InitialEnvironmentAssemblyLibrary`. Other assembly dependencies received a literal `missing` signature, and validation incorrectly accepted them because the current resolver also returned `missing`.

Assembly resolution now has three explicit outcomes:

1. `certified_contract` for Phase 3 certified contracts.
2. `building_definition` for valid assemblies in `IndustrialBuildingCatalog`, with a deterministic signature covering structural classification, parcel/module bounds, authored wall/floor/roof/entrance/clearance cells, connections, source geometry and calibration.
3. `missing`, which produces `MISSING_ASSEMBLY_DEPENDENCY`.

Definition-only resolution does not claim Phase 3 technical certification or owner visual approval. It establishes that the referenced authored assembly exists and identifies the revision needed to reconstruct it.

## Persistence and failure evidence

The existing persistence and document suites, plus the new lifecycle matrix, cover:

- Missing required and optional assets.
- Stale geometry, calibration and assembly revisions.
- Missing assembly definitions.
- Broken required relationship references.
- Unsupported persistence and document schema versions.
- Invalid placements and overlaps.
- Corrupt and incomplete JSON.
- Schema-1 layouts with missing historical identity.
- Transactional editor behavior: rejected loads preserve the active document and layout.

The schema-1 starter remains accessible only through explicit `legacy_compatibility`. Loading does not rewrite it. The tracked schema-2 example at `docs/architecture/examples/persisted-edited-industrial-layout.json` now contains an actual placement edit and repaired deployment context.

## Rendered inspection

The rendered capture script performs the industrial generation/edit/save/clear/reload sequence before taking screenshots. Plan and spatial-contract overlays are disabled.

- `layout-lifecycle-overhead.png`: reloaded 61-module layout, connected road plan and parcel distribution.
- `layout-lifecycle-oblique.png`: complete asset-first district after reload.
- `layout-lifecycle-frontage.png`: close inspection of the reloaded `city_industrial_shell_e`, street frontage and street furniture.

The captured editor reports `TACTICAL VALID`, seed 2208 and `industrial_district` reload identity. Visual review found no lifecycle-induced loss, transform reversal, missing building, duplicate road presentation, or misplaced reload state. This is a review of one edited industrial fixture, not a claim that every seed is visually certified.

## Commands and results

```powershell
godot_console --headless --path . --script res://tests/battlefield_layout_end_to_end_test.gd
godot_console --headless --path . --script res://tests/battlefield_layout_document_test.gd
godot_console --headless --path . --script res://tests/battlefield_layout_lifecycle_test.gd
godot_console --headless --path . --script res://tests/map_editor_layout_store_test.gd
.\tools\run_tests.ps1 subsystem -Subsystem generation
.\tools\run_tests.ps1 subsystem -Subsystem ui
godot_console --path . --script res://tests/battlefield_layout_lifecycle_capture.gd -- <output-directory>
```

Results:

- Focused layout-document regression: 0 failures.
- Focused end-to-end lifecycle matrix: 0 failures.
- Focused shared lifecycle regression: 0 failures.
- Generation subsystem: `PASS=27 FAIL=0 SKIP=11` in 620.37 seconds. The skipped checks are explicitly visual or stress-only scripts; the lifecycle capture was run separately.
- UI subsystem: `PASS=16 FAIL=0 SKIP=1` in 113.02 seconds. The only skipped check is the explicit Debug Draw capture.
- Rendered lifecycle capture: completed with exit code 0.

A direct invocation of `map_editor_layout_store_test.gd` could not write its fallback `user://` file because this restricted execution environment also denied Godot's log directory and Windows certificate store. The same test passed in the UI subsystem runner, which deliberately provides a writable `FUSEFIRE_TEST_OUTPUT_DIR`. This was an execution-environment failure, not a persistence assertion failure.

Capture output is stored under `docs/architecture/reviews/evidence/layout-document-lifecycle-task-4.4/`.

## Compatibility and authority

- `EnvironmentModuleMapWriter` and compiled `MapData` remain authoritative for traversal, occupancy, cover and LOS.
- Presentation continues to consume imported geometry without deriving tactical state from meshes.
- Existing coherent, legacy modular and normal gameplay generators remain separate. `battle_level.gd` still uses the existing normal battle generation path; no new gameplay entry point is active.
- Existing authored layouts and the legacy starter remain accessible under their documented policies.

## Remaining limitations and Phase 5 readiness

Phase 4 is ready to support Phase 5's bounded parcel relationships. The document lifecycle itself no longer loses identity, placements, required references, dependency state or deployments.

Remaining limits are explicit:

- A preserved seed is provenance, not a permanent regeneration guarantee. The document pins current algorithm/content labels and exact placements, but it does not hash executable generator code.
- Definition-only building assemblies are resolvable and revision-pinned but are not automatically promoted to certified Phase 3 contracts.
- Edited parcel relationships stay invalidated because Phase 4 has no general frontage/access relationship validator. Phase 5 should re-establish only the relationships it can prove.
- The current editor preserves deployment zones but still records objective definitions as not represented.
- The three-identity matrix verifies lifecycle behavior for three seeds; it does not measure overall procedural visual quality.
