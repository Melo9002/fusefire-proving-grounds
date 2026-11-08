# Current map architecture

This is the active map-system reference. Historical Generator 2 documents and the superseded 2026-11-01 map-plan draft are in the local quarantine described in [generation status](status.md).

## One runtime path

```text
Match Setup
  -> BattleConfiguration.battlefield_id
  -> BattleLoadingScreen
  -> BattlefieldCatalog
  -> selected map source
  -> MapData
  -> BattleController / missions / AI / replay
  -> GeneratedTerrainPresenter
```

`MapData` is authoritative for movement, stopping, cover, line of sight, elevation, traversal, deployment and mission zones. Imported meshes never create tactical rules implicitly.

`GroundTileLayers` handles the path, movement range, Guard, objective and cursor fills. It projects each fill onto the visible depth-writing surface within half an elevation step of its tactical cell, so minor road, curb and terrain height changes need no per-map overlay offset. One fill wins per cell and elevation. From highest to lowest priority the order is path, cursor, Guard preview, range, active Guard and objective. Tab still toggles the separate debug grid lines.

`BattlefieldCatalog` owns stable selectable identities, labels, fixed sizes, map construction and special presentation. Historical replay booleans remain compatibility inputs only; new code must not add another per-map boolean or numeric UI branch.

`BattleLoadingScreen` keeps Match Setup intact while battle initialization runs. `BattleLevel` reports real preparation stages and only becomes the current scene after tactical validation succeeds. A failure returns an actionable diagnostic and never activates a partial battle. The screen is a transition, not permission for unbounded runtime search.

## Supported map sources

| ID | Source | Status |
| --- | --- | --- |
| `service_depot` | Two 40×40 service sites with interchangeable loading parcels | Default battlefield |
| `tactical_test_range` | One 32×32 authored range with optional tactical population | Mechanics playtest map |
| `refinery_2` | Fixed authored Godot scene | Supported authored map |
| `loading_yard` | 16x32 authored parcel centred in a 40x48 battlefield | Foundation proof; technical validation exists, owner visual/playability review remains |
| `refinery_family` | Two fixed 64x64 plots resolving registered authored parcels | Active Generation 2.0 proof; Reach/replay and agent visual validation pass, owner review remains |
| `urban_family` | Fixed 64x64 service street or signal courtyard selected by seed | Match Setup preview with Reach and replay evidence |
| `parking_garage` | One fixed 32x32 two-level parcel with optional parked vehicles | Match Setup proof with Reach/replay, Rescue and rendered camera evidence |

### Tactical Test Range

In Match Setup, open **Battlefield** and select **Tactical Test Range**. Open [tactical_test_range.tscn](../../art/environments/authored/parcels/tactical_test_range.tscn) in Godot or select the range in the Parcel Editor. The fixed scene owns the deployments, approach, cover volumes, decks, traversal links and five mission zones. The battle supplies the units, actions, missions and UI. The range opens with **Tactical Population** off. Turn it on to vary the occupied parking and cargo bays with the battle seed.

- **Control gallery** has a ramp, stairs and ladder. The upper ladder links to the observation deck. Use **Alt + wheel** to choose between ground and the two decks at the same position. Choose **Terminal** to activate the control gallery console or **Reach** to take the observation deck.
- **Cover course** offers a vaultable barrier row and loose crates for directional cover, Aim and Guard reaction tests. The vehicle and container bays provide full blockers. Select a unit behind the fixed sedan and orbit low to test the local camera cutout and tactical shot preview together.
- **Mission stations** place Rescue at the cargo side of the range, friendly extraction at the southern gate and enemy evacuation at the north edge. These stations stay fixed across population seeds.

### Service Depot

Select **Service Depot** and enter seed `16` for the loading crossing or `17` for the service spine. Seeds `18` and `19` exercise the second loading parcel on those sites. Both use the existing refinery/urban/garage resolver and parcel compiler. Vehicles and containers use authored population regions and sockets, and the saved manifest records exact placements and headings. Unchecked **Tactical Population** keeps the selected plots and parcels with movable occupants removed.

The old Small, Medium and Large cover layouts, original Refinery, Industrial Warehouse and prototype traversal scene are no longer in Match Setup. Direct fixture paths still serve existing regression tests. The in-game file picker reports older recordings for those battlefields as retired.

## Authored content boundary

`AuthoredSceneMapCompiler` reads explicit tactical metadata for solids, decks, ladders, movement costs, fixed deployments and objective zones. Authored `ElevationPath` nodes specify the playable ramp and stair cells. The same scene is instantiated for presentation. The original prototype fixture exercises the separate legacy `MapBuilder` path in tests.

`ParcelTransform` maps parcel-local cells and scene transforms through supported quarter turns. `ParcelConnection` declares a boundary cell, outward direction, type and usable width. A parcel scene owns its dimensions, revision and connections as metadata. The resolver checks slot bounds, overlap with other slots or roads, and the full rotated entrance against the declared plot approach. After compiling the chosen population, the shared layout checks both sides of each in-bounds seam for walkable stopping cells at the declared height. An explicitly external driveway ends at the playable boundary. Standard parcel footprints are 16×16, 16×32 and 32×32 tactical cells. A supported quarter-turn provides 32×16.

Do not duplicate the compiler in a new layout adapter. Do not derive cover from mesh collision. Do not stretch imported assets to fill a parcel.

The urban service street uses the registered `industrial_office_parking_a` parcel. Both urban plots and the garage use the same resolver, slot contract and tactical compiler as the refinery family.

## Deliberate limits

- No active general plot solver, WFC, arbitrary packing or procedural building constructor.
- The **Parcel Editor** supports inspection, revision-bound visual drafts, population fields and validated parking-scene exports for registered standard footprints. Exports go to a separate scene for manual review and registration.
- No runtime semantic-catalog scan. Authored scenes resolve direct stable assets; later bounded plot choices must use a small registered list.
- New layout content must be an authored, registered parcel with measured interfaces and focused tactical/visual evidence; catalog membership alone does not make it eligible for a plot.
- Direct Generator 1 calls remain for existing regressions. Match Setup uses the authored catalog, with one shared resolver for all procedural plot, parcel and population choices.
- The quarantined code is reference material, never a runtime dependency.

## Current evidence

- Loading Yard battle initialization, including imported presentation and tactical validation: 873 ms in the focused headless check on 2026-11-02.
- Loading Yard Reach mission: completed in two rounds with 20 AI decisions; its 24 recorded actions replayed 24/24.
- Rendered overhead, oblique and service views were inspected. The parcel is a sparse technical proof, not a finished battlefield or owner-approved visual target.
- Refinery Family Site A seed 16, including its level-4 maintenance gallery, completes Reach in three rounds and replays 47/47 actions. Site B seed 17 completes in five rounds and replays 94/94 actions. Both preserve exact plot, parcel, population and revision choices.
- The legacy generation tier contains deliberately broad multi-seed tests that take tens of seconds. Performance analysis is deferred; normal battle entry now has a visible loading transition.
- `compact_battlefield_test.gd` checks both depot sites, fixed and populated range layouts, exact manifest reconstruction, deployment capacity, tactical occlusion and a live Terminal mission. Capture normal rendered views with `godot_console --path . --resolution 1360x860 --script res://tests/compact_battlefield_test.gd -- capture artifacts/compact-battlefields`.

## Adding a battlefield

1. Author or reuse a normal Godot scene with explicit tactical metadata.
2. Add focused validation for dimensions, connections, access and tactical compilation.
3. Register one stable ID in `BattlefieldCatalog`.
4. Verify battle initialization and replay identity.
5. Capture and inspect normal rendered views. Headless success is not visual approval.

If adding a battlefield requires touching Match Setup indexes, adding a configuration boolean, or copying a compiler, stop and extend the catalog/shared boundary instead.
