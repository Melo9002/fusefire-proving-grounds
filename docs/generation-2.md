# Generation 2.0

This is the current map guide. Historical plans are reference only.

## What you can play now

**Service Depot** is the only normal Match Setup choice. It is a 40 x 40 battlefield built through one plot/parcel pipeline.

| Part | Authored or procedural? |
| --- | --- |
| Buildings, their shape and local arrangement | Authored in parcel scenes |
| Roads and surroundings | Authored in each plot scene, using imported roads |
| Site arrangement | Seed selects one of two authored plots |
| Loading area | Seed selects a compatible authored parcel variant |
| Cars and containers | Seed selects placements from eligible authored rules/positions |
| Tactical movement, shots and cover | Compiled from explicit tactical data, not guessed from mesh appearance |
| Background beyond the map | Visual scenery, outside tactical play |

The generator combines authored content; it does not invent buildings or generate arbitrary street networks. Increasing density does not create unlimited placements: available positions, bounds and clearance limit it.

## Reproduce and test

1. F5 opens Match Setup. Select your mission and forces.
2. Disable **Automatic New Seed**. Seed **16** selects the loading crossing; **17** selects the service spine.
3. Toggle **Vary cars / containers** to compare populated and empty areas on the same site.
4. Start Battle. Construction must validate before units can act; failure reports a reason.
5. After the battle, use Replay Battle or Save Replay. The recording keeps actual accepted choices rather than regenerating from the seed alone.

For repeatable automated checks, run from the project root:

```powershell
godot_console --headless --path . --script res://tests/current_generation_test.gd
.\tools\run_tests.ps1 subsystem -Subsystem generation
.\tools\run_tests.ps1 full
```

The focused test checks menu selection, deterministic resolution, population-off, recorded reconstruction, missing/stale dependencies, explicit retirement and real battle/presentation initialization. Parcel, camera, tactical and replay suites cover their own contracts. Automated checks do not replace visual/playability review.

## Where to edit

- **Plot:** `art/environments/authored/plots/depot_loading_crossing.tscn` or `depot_service_spine.tscn`. This owns fixed site scenery/routes. Slot definitions are in `systems/generation2/generator.gd`.
- **Parcel:** ordinary Godot scenes under `art/environments/authored/parcels/`. Initial standard footprints are 16 x 16, 16 x 32 and 32 x 32, with supported quarter-turns.
- **Parcel Editor:** inspect/place/move objects and paint allowed population areas. The guides show intent; Preview shows one possible result. Illegal placement/paint gives a reason.
- **Asset Lab:** inspect imported models and adjust existing calibration. The manual boundary-baking tab was removed from the active workflow.

**Important:** draft save, exported scene and registered battle content are different states today. A draft does not automatically become playable. Export must preserve tactical metadata and population rules; registering a reviewed scene in the existing parcel catalog is still a code step. This handoff is unfinished, not an intended permanent workflow.

Moving a tactical template in current draft preview moves its tactical bounds too. An ordinary imported mesh alone does not yet get automatic movement/shot/cover boundaries. The desired next simplification is **place a mesh -> automatic starting boundary**, with exceptional overrides discussed only when necessary. It has not been implemented by this cleanup. No hull fitting or boundary-draft export is required or offered as a replacement workflow.

## Generator boundary

`systems/generation2/` owns current composition and reconstruction. It shares the game's empty-grid builder, MapData, tactical validation, assets and presentation helpers. It has no dependency on Generator 1, old refinery/warehouse generators or the legacy procedural renderer.

Its entry point is `generator.gd`: generate validated tactical data plus exact accepted choices; present the same choices. `BattlefieldCatalog` and `BattleLevel` integrate it with the game. A future generator can replace that producer without replacing combat, missions or replay.

Exact reconstruction validates content/compiler revisions. This supports compatible current content; it does not guarantee that any historical seed works after arbitrary future content changes.

## What stays out of the normal workflow

Refinery 2, the large refinery family, the urban-family wrapper and standalone Loading Yard were retired. Their map scenes, adapters, map-specific checks and historical documents are in:

`C:/Users/Blue/Documents/Codex/quarantine/fusefire-stripdown-2026-11-14`

The archive contains `retired/`, pre-edit `originals/`, and a SHA256 `manifest.json`. Nothing was permanently deleted. Git baseline is `a3408e1`. Restore individual files deliberately, not the entire retired pipeline over the current one. Earlier Generator 2 experiments remain in the separate pre-simplification quarantine.

Reusable parcels, imported kits, calibration and semantic data remain. The internal Tactical Test Range, Parking Garage and Generator 1 mechanical fixtures remain for regression coverage; they are not extra menu maps. Legacy implementations are isolated in `tests/fixtures/legacy_generation/`, loaded only for explicit fixture requests. Retiring these remaining fixtures requires replacing the mechanics coverage they provide first.

## Remaining work, in order

1. Extract reusable cars, containers and trucks from example parcels into ordinary reusable scenes, preserving their current transforms and tactical data.
2. Make ordinary asset placement derive useful starting tactical boundaries automatically; keep movement, sight and cover behavior understandable.
3. Make one complete parcel edit/save/reopen/play workflow without manual registration chores.
4. Consolidate old selection flags at compatibility entry points, then migrate remaining legacy mechanics coverage deliberately.
5. Validate the simplified workflow with real missions, replay and clean visual inspection before adding content/variety.

The longer-term direction remains: fully authored places, fixed places with varied movable objects, and seeded arrangements of authored areas through the same pipeline. Catwalks belong to authored functional connections between important places, not arbitrary decoration. A future parking structure needs explicit multi-floor access and camera occlusion checks. Neither requires a new general solver now.

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

Remaining audit work includes reusable occupant scenes, geometry-derived default boundaries, unified parcel save/preview/test handoff, canonical configuration selection, and legacy coverage migration. Legacy authored-fixture `MapBuilder` discovery and some camera group scans have not been redesigned in this batch; these checks establish scoped environment initialization, not universal multi-battle isolation.
