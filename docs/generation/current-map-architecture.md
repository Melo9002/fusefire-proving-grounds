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

`BattlefieldCatalog` owns stable selectable identities, labels, fixed sizes, map construction and special presentation. Historical replay booleans remain compatibility inputs only; new code must not add another per-map boolean or numeric UI branch.

`BattleLoadingScreen` keeps Match Setup intact while battle initialization runs. `BattleLevel` reports real preparation stages and only becomes the current scene after tactical validation succeeds. A failure returns an actionable diagnostic and never activates a partial battle. The screen is a transition, not permission for unbounded runtime search.

## Supported map sources

| ID | Source | Status |
| --- | --- | --- |
| `generated_cover` | Generator 1 seeded cover | Supported default generated map |
| `legacy_refinery` | Generator 1 Refinery | Supported compatibility map |
| `industrial_warehouse` | Authored Generator 1 vertical slice | Supported compatibility map |
| `refinery_2` | Fixed authored Godot scene | Supported authored map |
| `loading_yard` | 16x32 authored parcel centred in a 40x48 battlefield | Foundation proof; technical validation exists, owner visual/playability review remains |
| `refinery_family` | Two fixed 64x64 plots resolving registered authored parcels | Active Generation 2.0 proof; Reach/replay and agent visual validation pass, owner review remains |

## Authored content boundary

`AuthoredSceneMapCompiler` is the only shared scene-to-`MapData` compiler. It reads explicit tactical metadata such as `solid_size`, decks, ladders and deployments. The same scene is instantiated for presentation.

`ParcelTransform` maps parcel-local cells and scene transforms through supported quarter turns. `ParcelConnection` declares a real boundary cell, outward direction, type and usable width. A parcel scene owns its dimensions, revision and connections as metadata. Connections must validate before later plot composition may use the parcel. Standard parcel footprints are 16×16, 16×32 and 32×32 tactical cells; a supported quarter-turn provides 32×16.

Do not duplicate the compiler in a new layout adapter. Do not derive cover from mesh collision. Do not stretch imported assets to fill a parcel.

## Deliberate limits

- No active general plot solver, WFC, arbitrary packing or procedural building constructor.
- The active **Parcel Editor** is an isolated inspection and visual-draft tool for registered standard-footprint parcels. It owns camera, footprint-grid, tactical-overlay and revision-bound visual transform history; it cannot mutate runtime scenes or tactical contracts. Future authoring work must remain inside this boundary. It has no runtime generator, publication framework or retired dependency graph.
- No runtime semantic-catalog scan. Authored scenes resolve direct stable assets; later bounded plot choices must use a small registered list.
- New layout content must be an authored, registered parcel with measured interfaces and focused tactical/visual evidence; catalog membership alone does not make it eligible for a plot.
- Generator 1 remains until a replacement demonstrates equivalent gameplay and replay behavior and the owner explicitly retires it.
- The quarantined code is reference material, never a runtime dependency.

## Current evidence

- Loading Yard battle initialization, including imported presentation and tactical validation: 873 ms in the focused headless check on 2026-11-02.
- Loading Yard Reach mission: completed in two rounds with 20 AI decisions; its 24 recorded actions replayed 24/24.
- Rendered overhead, oblique and service views were inspected. The parcel is a sparse technical proof, not a finished battlefield or owner-approved visual target.
- Refinery Family Site A seed 16, including its level-4 maintenance gallery, completes Reach in three rounds and replays 47/47 actions. Site B seed 17 completes in five rounds and replays 94/94 actions. Both preserve exact plot, parcel, population and revision choices.
- The legacy generation tier contains deliberately broad multi-seed tests that take tens of seconds. Performance analysis is deferred; normal battle entry now has a visible loading transition.

## Adding a battlefield

1. Author or reuse a normal Godot scene with explicit tactical metadata.
2. Add focused validation for dimensions, connections, access and tactical compilation.
3. Register one stable ID in `BattlefieldCatalog`.
4. Verify battle initialization and replay identity.
5. Capture and inspect normal rendered views. Headless success is not visual approval.

If adding a battlefield requires touching Match Setup indexes, adding a configuration boolean, or copying a compiler, stop and extend the catalog/shared boundary instead.
