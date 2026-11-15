# Generation 2 cleanup and verification history

Historical evidence below records what was tested at each stage. For current instructions use [the everyday guide](generation-2.md). Earlier limitations may have been resolved by a later entry.

## Cleanup verification — 2026-11-14

- The full Ironclad run completed with **109 pass, 2 fail, 14 explicit-only skipped**. Both failures were stale test fixtures for retired menu maps, not ignored failures: `parcel_gallery_picking_test.gd` now exercises the retained range/garage decks, and `replay_file_workflow_test.gd` uses Service Depot. Both passed focused reruns with their picking, movement, save/load and replay assertions preserved. The replay test now exits explicitly if its expected loading screen is absent.
- At that cleanup stage, no further full run was made. The later audit batch has a complete rerun recorded below; the original raw result remains 109/2/14. Final smoke: **11 pass, 0 fail, 0 skip** in 36.42 seconds (`artifacts/test-results/20261114-153932-smoke/`).
- Service Depot seed 17 completed a real Reach battle; saved-file playback verified **28/28 actions** and the same victory. The exact saved content was reconstructed and rewatch/return-to-setup checks passed.
- Rendered inspection of Service Depot seeds 16 and 17 preserved their existing road, building and equipment presentation. Grid overlays were disabled; ordinary HUD remained. The internal range also completed its terminal interaction. This is bounded inspection, not blanket visual approval or an asset-boundary fix.
- Full logs: `artifacts/test-results/20261114-152548-full/`. Focused follow-ups: `artifacts/cleanup-gallery-picking.log` and `artifacts/cleanup-replay-file-final.log`. Images: `artifacts/cleanup-views/`. Local diagnostics are ignored by Git.
- The archive's 7,262 retired files and 23 original-file snapshots were verified against their SHA256 records. It includes 47 superseded Markdown documents, 23 retired-map test/diagnostic scripts, research and old captures/logs. Reusable content, core mechanics and imported/calibrated assets remain. Five pre-existing texture import edits were excluded from the cleanup.

Commands for the corrected tests:

```powershell
godot_console --headless --path . --script res://tests/parcel_gallery_picking_test.gd
godot_console --headless --path . --script res://tests/replay_file_workflow_test.gd
```

Direct sandboxed Godot launches reported certificate-store/user-settings access errors; the isolated Ironclad project scan passed. These environment messages are separate from the corrected fixture failures. No final script parse/compile failures remained.

## Independent audit follow-up — first batch

Completed scope: active-shape consistency, environment initialization ownership, and the obsolete refinery recipe. No draft-format, replay-schema, configuration-selection or automatic-boundary redesign is included.

- **Clearance:** both warehouse variants now exclude revision-2 envelopes from current obstacle collection and population bounds. Their shell and planter still block their authored regions. Historical compiler revisions are unchanged. The new regression reproduced four failures before correction and passes afterward.
- **Ownership:** atmosphere receives the owning battle's explicit environment. Geometry toggles stay inside its authored environment, and hazards stay inside its battle root. The extended isolation test reproduced ten failures before correction and now passes with unrelated environment/group nodes plus two overlapping Depot battles. Own hazards still stamp correctly. Rewatch also checks the replacement's atmosphere while the original battle remains alive.
- **Quarantine:** the obsolete `refinery_2_author.py` recipe is at `C:/Users/Blue/Documents/Codex/quarantine/fusefire-audit-cleanup-2026-11-14`. Recovery hashes and an inventory of its four retained shared-component outputs are included. Current component scenes were not regenerated or changed.
- **Rendered inspection:** Depot seeds 16/17 and saved-file replay rewatch were captured and inspected. Grid overlays were disabled; normal HUD/objective markers remain. The warehouse's current compound shapes were inspected separately. No geometry/visual approval beyond these bounded checks is claimed.
- **Evidence:** focused logs are `artifacts/audit-focused-*.log`; baseline failures are `artifacts/audit-clearance-baseline.log` and `artifacts/audit-isolation-before.log`. Captures are in `artifacts/audit-batch1-depot/`, `artifacts/audit-batch1-replay/` and `artifacts/refined-warehouse-*.png`.
- **Verification:** seven focused suites passed. The full Ironclad rerun passed **113 suites, 0 failures, 14 explicit-only skips** in 597.50 seconds. Logs: `artifacts/test-results/20261114-192237-full/`. Saved-file replay verified **28/28 actions** and the same victory. The full run had no script parse/compile/runtime errors; the pre-existing four-ObjectDB-instance warning in `allied_faction_smoke.gd` also appears in the earlier full log and remains outside this batch. Direct sandboxed render/focused runs retain the known certificate-store warning.

Reproduce the key checks:

```powershell
godot_console --headless --path . --script res://tests/parcel_active_shape_clearance_test.gd
godot_console --headless --path . --script res://tests/battle_dependency_isolation_test.gd
godot_console --path . --script res://tests/compact_battlefield_test.gd -- capture artifacts/audit-batch1-depot
godot_console --path . --script res://tests/replay_file_workflow_test.gd -- capture artifacts/audit-batch1-replay
```

At that stage, geometry-derived default boundaries and reusable object extraction were still pending; both later batches are recorded below. Those remaining audit items are addressed by the November 15 follow-up below; genuinely historical regression fixtures remain classified separately. Legacy authored-fixture `MapBuilder` discovery and some camera group scans have not been redesigned in this batch; these checks establish scoped environment initialization, not universal multi-battle isolation.

## Reusable object extraction — 2026-11-14

The crate, containers A/B/C, delivery truck, sedan, SUV and taxi now have ordinary editable scenes in `art/environments/authored/objects/`. Loading Yard, its alternate/painted variant, and the office parking parcels instance them directly. Parcel-specific names, transforms, visibility and population sockets remain on the parcel instances. Editor creation and parking templates use those same object scenes; neither needs to instantiate an example parcel or find a named node inside it.

This extraction preserves mesh calibration, tactical metadata, asset IDs, seeded vehicle ordering, parcel revisions and historical/current truck shapes. It adds no placement workflow, asset registry, boundary format or replay schema. Independently authored objects elsewhere remain untouched. The extraction itself introduced no automatic mesh boundaries; the November 15 step below adds that editor fallback.

Export now preserves ownership of instanced container children. Reassigning those children to the exported parcel duplicated visual/tactical parts on reopening and leaked objects; the focused regression checks exactly one visual and volume per container. Combined export also checks all three current truck parts and its historical volume.

`tests/reusable_occupant_test.gd` protects independence from example parcels and compares the extracted meshes, transforms, visibility and metadata against fingerprints captured from commit `4c465f2` before extraction. These fingerprints protect this unchanged-content contract; intentional future content revisions must review and update the corresponding baseline, rather than treating it as an immutable art specification.

Verification: six focused suites passed. The full Ironclad run passed **114 suites, 0 failures, 14 explicit-only skips** in 594.29 seconds (`artifacts/test-results/20261114-220224-full/`), including editor save/load, combined export/reopen, generation and replay. Before the fix, the new independence check failed for both example-parcel dependencies; the new container export assertion reproduced duplicate children. Both now pass. No script parse/compile/runtime errors or new object leaks were found in the full logs; the existing four-instance warning in `allied_faction_smoke.gd` remains. Sandboxed runs also retain certificate-store/editor-settings permission diagnostics.

Rendered inspection covered Service Depot seeds 16/17 and the internal garage's ground cutaway. The rendered compact-battlefield check also completed the range terminal mission. Captures are under `artifacts/occupant-extraction-depot/` and `artifacts/occupant-extraction-parking/`. These are bounded visual checks, not full UI or animation approval. The five pre-existing texture-import edits are outside this commit.

## Automatic starting boundaries — 2026-11-15

In Parcel Editor, open **Objects**, choose an ordinary ground prop and press **Place**. The calibrated visible mesh parts get starting box boundaries automatically. The existing blue/red ghost, overlap checks, Undo/Redo, selected-object tactical overlay, combined preview and scene export all use those parts. The browser labels the source as **Mesh boundaries** or **Authored boundaries**; these are filters, not new roles the owner must assign. Existing decoration entries remain available, and complete ground cargo/equipment can now use the same fallback. Roads, floors, structural fragments and new building/open-structure families have not been added to this fallback palette.

The editor creates ordinary `solid_size` parts from each visible `MeshInstance3D`'s geometry bounds, including nested calibration transforms. Hidden and flat meshes without volume are ignored. It does not use renderer culling bounds or combine the whole object into one large box. An existing explicit solid anywhere in the object prevents replacement, including historical revision parts. Root movement, rotation and scale affect the visible object and its shapes together.

The compiler keeps the existing movement and cover rules. New parts also reserve a standard **two-tile standing clearance** beneath raised geometry, preventing a soldier from standing inside a body that starts above ground. Shot bounds remain at the visible height. A safely overhead part does not reserve ground movement; overhead structures and elevated surfaces still need their authored contracts. Grid-cell padding accounts for part scale, so shrinking a prop at a cell corner does not make its tactical footprint disappear. Existing authored solids default to zero standing clearance and retain their previous compilation. No generator, manifest or replay schema was replaced.

Derived parts are saved in exported scenes, and their transforms/metadata contribute to export identity. Battles compile those saved parts through MapData; they do not load editor code or regenerate boundaries from meshes during replay. Draft save/open recreates added objects through the same placement library. Complete parcel Save/Open preserves both editing drafts; Test battle exercises them directly. Publishing to the normal map catalog remains separate.

Limitations: **these are per-mesh box approximations, not exact polygons**. A concavity, doorway or empty space inside one mesh can still be filled by its box; gaps between separate mesh parts remain separate. Movement still reserves whole tactical cells. The fixed standing clearance is the prototype's standard envelope, not a per-character capsule test. Existing truck/building shapes and already published maps are not automatically replaced. Dropping a raw imported mesh directly into an arbitrary Godot scene bypasses the placement library and does not add these shapes. Editing a model or its internal mesh transforms after baking does not refresh saved parts: recreate the placed object and export/review the new content. No manual hull fitting, clipping or new boundary-export workflow is introduced.

Focused coverage is `tests/mesh_boundary_test.gd`: real imported placement, low/full cover, scaled corner footprints, transformed multi-part bodies, open gaps, raised-body shots, ground clearance, save/open, export/reopen, derived content identity, legal/illegal editor ghosts and Undo/Redo. Run it headless for assertions, or render the editor check with:

```powershell
godot_console --headless --path . --script res://tests/mesh_boundary_test.gd
godot_console --path . --script res://tests/mesh_boundary_test.gd -- capture artifacts/mesh-boundaries-editor
```

Verification: seven focused suites passed. The final full Ironclad run passed **115 suites, 0 failures, 14 explicit-only skips** in 588.27 seconds (`artifacts/test-results/20261115-063044-full/`). The boundary suite also passed a focused rerun with the final same-cell shot-gap assertions. Reproductions failed before the ordinary-object, raised-body and scaled-footprint fixes; a negative control excluding derived shapes from export identity failed the new rebake-identity assertion. No assertion was weakened. The existing four-instance warning in `allied_faction_smoke.gd` and sandbox certificate/editor-settings diagnostics remain; no new script errors or object leaks were found. Rendered editor inspection passed for the placed box and its selected tactical overlay (`artifacts/mesh-boundaries-editor/ordinary-box-boundaries.png`); this is not visual approval of every newly eligible model. The five pre-existing texture-import edits remain outside this batch.


## Audit completion — 2026-11-15

The editor now has one complete Save/Open operation and one Preview/Test path. Preview and local battle both consume exported current rules through the existing Generation 2 resolver; there is no separate preview density algorithm. Permission/protection filtering, mixed parking/container rules and occupancy survive save, scene export and tactical compilation. Tests compare accepted population and tactical geometry at densities 0/65/100 across seeds 17/18.

Battle configuration now normalizes once, uses one named battlefield identity internally, and supplies replay configuration through the existing codec. Old boolean selectors are translated only at compatibility inputs; an explicit named identity wins over stale flags. Historical combat-rule flags and replay semantics remain supported. New simulation runs default to Service Depot.

Seven generator-independent mechanics suites now use the shared empty-grid builder directly. Generator-specific historical fixtures remain under `tests/fixtures/legacy_generation/`; removing their useful assertions is not a cleanup requirement. `current_mission_replay_matrix_test.gd` covers both Depot plots and all eight mission types, with population on/off and a recorded/replayed action. This checks initialization and reconstruction, not AI success at every objective. The explicit current-map AI Eliminate check completed in six rounds with 53 decisions.

Obsolete absolute-coordinate metadata (`deck_rect`, `ladder_bottom`, `ladder_top`, `faction`, `grid_origin`) no longer has compiler branches. Content containing it is rejected explicitly before partial compilation. Retained scenes have no producers; a read-only inventory of the two existing user parcel exports found none. Relative deck, ladder and deployment contracts remain supported, along with historical solid revisions.

Rendered handoff captures are under `artifacts/report-cleanup-handoff/`: editor preview, local battle, replay return and restored editor. This bounded inspection does not establish visual correctness for every asset or a complete battle playthrough. Final full verification passed **122 suites, 0 failures, 14 explicit-only skips** in 631.59 seconds (`artifacts/test-results/20261115-083347-full/`). The current AI battle and 300-seed container sweep passed separately. Full evidence, failure diagnoses, known warnings and skipped scope are in [Project Ironclad](quality/project-ironclad.md#audit-follow-up-coverage--2026-11-15).
