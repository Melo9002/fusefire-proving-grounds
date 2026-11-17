# Generation 2.0

This is the current map guide. Historical plans are reference only.

## What you can play now

There are **three curated 40 × 40 sites**, all using the same Generation 2 pipeline:

| Site | What is there | What varies |
| --- | --- | --- |
| Service Depot | Existing warehouse, process equipment and tank storage | Two site layouts, loading parcels, delivery truck and containers |
| Freight Yard | Container staging apron beside a fleet service apron | Aprons swap sides; container positions and parked vehicles vary |
| Fleet Station | Two small service offices and a vehicle court | Frontage faces north/south; occupied spaces and vehicle models vary |

New parking bays can spawn sedans, SUVs, taxis, **ambulances and vans**. Older authored bays retain their original vehicle set. These vehicles use the existing obstacle, sight and cover rules.

For controlled mechanics checks or a normal match on the existing range, choose **Tactical Test Range — Test map** in Match Setup. You can also open **Tactical Test Range** in the Parcel Editor and use **Test battle**. Both use the same authored range and generation path; no map was duplicated. The three curated sites remain the normal content-release set. See the [combat example stations and commands](combat-controlled-examples.md).

| Part | Authored or procedural? |
| --- | --- |
| Buildings, their shape and local arrangement | Authored in parcel scenes |
| Roads and surroundings | Authored in each plot scene, using imported roads |
| Site arrangement | Seed selects one of two authored layouts for the chosen site |
| Parcels | Seed selects the site’s declared parcel arrangement; Depot also varies its loading parcel |
| Vehicles and containers | Seed selects occupied positions and eligible models from authored rules |
| Tactical movement, shots and cover | Compiled from saved tactical shapes; the editor can derive starting shapes from ordinary objects' mesh parts |
| Background beyond the map | Visual scenery, outside tactical play |

The generator combines authored content; it does not invent buildings or generate arbitrary street networks. Increasing density does not create unlimited placements: available positions, bounds and clearance limit it.

## Reproduce and test

1. F5 opens Match Setup. Choose **Service Depot**, **Freight Yard** or **Fleet Station**, then your mission and forces.
2. Disable **Automatic New Seed**. Compare seeds **16** and **17**: Depot crossing/spine; Freight container apron west/east; Fleet Station frontage north/south.
3. Toggle **Vary vehicles / containers** to compare populated and empty areas on the same site.
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

- **Plots:** editable scenes in `art/environments/authored/plots/`. Depot uses its crossing/spine; Freight uses `freight_yard_site.tscn`; Fleet uses `fleet_station_north.tscn` and `fleet_station_south.tscn`. Slot definitions remain in `systems/generation2/generator.gd`.
- **New parcels:** `container_staging_apron.tscn` and `fleet_service_apron.tscn` are 16 × 32; `fleet_service_court.tscn` is 32 × 32. Open their Freight/Fleet labels in Parcel Editor.
- **Parcels:** ordinary Godot scenes under `art/environments/authored/parcels/`. Initial standard footprints are 16 x 16, 16 x 32 and 32 x 32, with supported quarter-turns.
- **Parcel Editor:** inspect/place/move objects and paint allowed population areas. The guides show intent; Preview shows one possible result. Illegal placement/paint gives a reason.
- **Asset Lab:** inspect imported models and adjust existing calibration. The manual boundary-baking tab was removed from the active workflow.

### The short editing loop

1. Open Parcel Editor and select a parcel. Guides show where movable content may appear; placed fixed objects remain visible. A gold footprint labeled **Reserved container/vehicle position** explains a collision with a currently hidden population guide. Empty guides reserve space for other seed outcomes.
2. Place/move objects and paint permitted or protected population areas. Invalid placement gives a reason.
3. **Save parcel** saves objects, population, seed and density together. **Save as…** makes a named copy; **Open parcel…** restores both drafts after confirmation if work is unsaved. The shared footer shows the active filename and saved/export status. Older separate draft files remain importable under **Import older drafts**.
4. Use **Preview** in the shared footer. **Next seed** compares arrangements; the seed is saved with the parcel. Tabs keep the preview visible. **Show guides** returns to editing. **Compare original** temporarily shows the starting layout; **Return to my parcel** restores your work.
5. **Test battle** opens this exact parcel as a local Eliminate battlefield through the existing Generation 2 resolver/compiler. It needs no export or catalog registration. The battle activates its own camera, independent of the editor angle. The return button, including after replay, restores the editing session and editor view. Save a named copy before restarting the application; in-memory edits alone are not recovery storage.

**What paint changes:** paint where that kind of object can appear on this floor. For example, **existing parking spaces outside your painted areas won’t spawn cars**. Multiple strokes combine. Parking controls car/ambulance/van spaces; trucks, containers and other floors keep their rules. Container and equipment paint work the same way for their own objects. Movable objects overlapping protected paint won’t appear. Density affects the painted type: 0% leaves its positions empty; 100% fills valid positions. It does not change unrelated population.

A local test does **not** publish the parcel into the normal selectable sites. Optional scene export remains available for Godot inspection; adding a reviewed scene to the normal parcel catalog is still an explicit content change. Save preserves editable work; Test battle exercises that work directly. They no longer require the export/register handoff just to test. A changed layout has a new content identity, so the same seed may choose different positions from the original comparison even where the original rules are retained. Preview and Test battle share the same single-parcel slot context. If later published into a different plot/slot, the same seed may choose a different arrangement because slot identity is part of deterministic population selection.

Local test recordings reference an immutable hash-named scene snapshot under `user://parcel_test_content`, plus hashes of its project dependencies. Keep that cache and the matching project content to reopen those replays. Missing snapshots or changed dependencies reject explicitly. A replay file alone does not bundle the local scene or assets for another computer. Published site recordings retain their existing reconstruction contract.

New ordinary objects placed through **Objects → Place** now get starting tactical boundaries automatically from their visible mesh parts. Moving, rotating or scaling the object carries those parts with it. Existing authored templates keep their current shapes, including historical replay shapes. Save and export use the existing workflow; no hull fitting, role assignment or separate boundary draft is required. This is a box approximation with the limitations below, not exact polygon collision.

## Generator boundary

`systems/generation2/` owns current composition and reconstruction. It shares the game's empty-grid builder, MapData, tactical validation, assets and presentation helpers. It has no dependency on Generator 1, old refinery/warehouse generators or the legacy procedural renderer.

Its entry point is `generator.gd`: generate validated tactical data plus exact accepted choices; present the same choices. `BattlefieldCatalog` and `BattleLevel` integrate it with the game. A future generator can replace that producer without replacing combat, missions or replay.

Exact reconstruction validates content/compiler revisions. This supports compatible current content; it does not guarantee that any historical seed works after arbitrary future content changes.

## Known limitations

- Automatic boundaries are **one box per visible mesh part, not exact polygons**. Separate parts retain gaps; a doorway, arch or concavity inside a single mesh may still be blocked by its box. Raised bodies reserve standing space underneath while shots use their actual height. Existing authored truck/building shapes remain unchanged.
- This automatic fallback covers ordinary props in the placement library. Raw meshes dropped directly into arbitrary Godot scenes do not gain boundaries. Floors, roads, structural fragments and multi-floor assemblies still need their existing authored traversal contracts.
- Changing a model's internal geometry after placement does not refresh baked boundaries. Recreate the placed object before saving/reviewing the changed content.
- The grid retains one unit per cell, with an automatically resolved safe standing point inside partly occupied cells. Swept body clearance and neighboring bodies also constrain routes. A visible narrow gap is not necessarily wide enough for a soldier. Restart existing matches to use the current compilation; see [asset-edge placement](asset-edge-placement.md).
- Local tests use an Eliminate mission. They validate a parcel alone, not every possible connection in a published full map. A unit can start behind a building from the current angle; select that soldier or rotate the camera to inspect it. Occlusion currently follows the active soldier rather than every squad member; camera presentation remains a separate playability check.

## What is complete and what needs testing

**Complete:** one parcel Save/Open, combined runtime-rule Preview, local Test battle without registration, canonical map selection and saved local-content action replay. Those are no longer future workflow tasks.

**Checked in this follow-up:** the saved ambulance parcel completed Eliminate and replayed all **53/53 actions** to the same defeat. A live-battle regression checks separate-part openings, combined-mesh concavity and raised bodies. See the [focused playtest record](quality/parcel-playtest-2026-11-15.md).

**Stopping point for this phase:** use the three sites for normal playtesting. The content release checks seed variation, both layouts, all eight mission starts, complete sample battles and saved replays. Further map work should follow concrete gameplay bugs or actual content needs; the next development phase can focus on tactical feedback and AI. See [content release evidence](quality/current-content-release.md). Technical checks do not establish that every asset's approximation feels right in play. Do not extend automatic boxes to structural assemblies on that assumption.

The three normal sites share one generator. Historical generators remain only as explicit regression fixtures, outside Generation 2's dependency path. Retired maps/documents and the refinery recipe are preserved in external quarantine; the recovery locations, audit changes and dated test evidence are in [cleanup history](generation-2-history.md). The current code map is [architecture.md](architecture.md); test commands and results are in [Project Ironclad](quality/project-ironclad.md).

World-beyond-the-map work is tracked separately in [World surroundings](world-surroundings.md). Normal plots now expose Tactical, Peripheral and Distant scene groups; this does not change their tactical generation rules.

Service Depot now demonstrates connected off-map industrial yards, extended roads and low-detail background placeholders. Yellow dashes mark its unchanged playable footprint. See the [Depot continuity proof](quality/depot-continuity-2026-11-15.md).
