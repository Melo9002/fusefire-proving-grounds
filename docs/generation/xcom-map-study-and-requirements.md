# FuseFire maps: XCOM 2 study and proposed requirements

Status: supporting research and bounded requirements, updated 2026-11-02. The active implementation contract is [Current map architecture](current-map-architecture.md). This document explains why plots, authored parcels and measured connections remain useful; it is not an instruction to restore quarantined Generator 2 systems.

## Where we are

- Generator 1, its original Refinery and the Industrial Warehouse remain playable. Generator 2 and its tools are in the local quarantine described in [generation status](status.md).
- Refinery 2 is a fixed authored 96 x 80 map, with real tactical data and replay integration. Its buildings and equipment do not rearrange with the seed. See [Refinery 2 handoff](refinery-2.md).
- We have reviewed Kenney assets, calibration, reusable catwalk components and the retained Asset Lab. We do not yet have an active replacement plot-and-parcel generator or a production-ready general map authoring workflow.
- The superseded broad map-plan draft is preserved in the local quarantine. Meaningfully different layouts remain a product goal, but composition must earn its complexity through reviewed authored content.

## What the XCOM 2 SDK actually shows

The installed base-game SDK was inspected read-only at `C:/Program Files (x86)/Steam/steamapps/common/XCOM 2 SDK/`. Evidence refers to its files, not necessarily War of the Chosen or every shipped map.

| Finding | Direct evidence | Implication for FuseFire |
| --- | --- | --- |
| A plot is the containing level that tells the game which maps to load; parcels are authored themed chunks. | `Documentation/Content/XCOM2Mods_LevelDesign.pdf`, pp. 5–6; map folders `XComGame/Content/XCOM_2/Maps/Plots` and `.../Parcels`. | Author layouts and meaningful areas separately. Let generation select and combine compatible content. |
| Standard parcel sizes are 16x16, 16x32 and 32x32 tiles. | SDK guide pp. 6 and 37; `XComParcelManager.uc`, lines 6 and 40–44. | Fixed sizes are a practical simplification, not a requirement to copy XCOM's dimensions. The code's parenthetical comments say 14x14 etc.; the guide explicitly states 16/32. We did not resolve that discrepancy. |
| Parcel definitions specify compatible plot and zone types, size, street-facing direction, entrances and objective tags. | `Development/SrcOrig/XComGame/Classes/XComParcelManager.uc`, lines 79–110; `XComGame/Config/XComParcels.ini`; guide p. 37. | Compatibility must include geometry and actual access, not tags alone. A loading yard should meet its service road and mission needs. |
| Plot-cover parcels (PCPs) fill spaces between/around parcels. Gameplay PCPs include road straights, corners and intersections. | SDK guide pp. 7, 39–40; `XComGame/Config/XComPCPs.ini`. | Streets and connecting terrain need ownership and matched edges. A refinery need not have a city street network. |
| The guide distinguishes near periphery—continuations and filler bordering the battlefield—from far periphery, a distant landscape map. | SDK guide pp. 8–9. `XComPlotCoverParcelManager.uc`, lines 141–163 selects and streams periphery pieces and stores their transforms. | Build scenery beyond the playable boundary. Match roads and terrain at the edge; keep distant decoration outside tactical simulation. Do not infer that all XCOM periphery is selected by the same algorithm. |
| The parcel manager has an explicit randomized-definition backtracking layout procedure and stores selected map names, positions, rotations and entrance data. | `XComParcelManager.uc`, lines 135–187 and 656–752. Some eligibility checks are declared `native` (for example lines 892–898), so their complete implementation was not established here. | Bounded search and recording actual choices are credible, but XCOM's exact native selection behavior remains unverified. A small game does not need an exhaustive general solver at the outset. |
| Plot types, zoning, biome swaps and lighting provide distinct dimensions of reuse. | SDK guide pp. 10–13; `XComParcels.ini` plot types/biomes. | Separate site layout, compatible content, surrounding setting and lighting where this saves content work. Do not build all swapping systems before a concrete need. |

The SDK maps exist as `.umap` files. This pass read the guide, definitions and source; it did **not** open individual maps in UnrealEd or run the XCOM game. The guide is evidence of the intended workflow; config and script establish specific structures/behaviors, not every runtime detail. In particular, the appearance, cost and exact assembly of a given horizon still need visual/editor inspection.

## What FuseFire needs

1. **Three modes:** a completely authored map; a fixed place with varied movable tactical content; and a generated arrangement of authored areas. All use the existing tactical game and support missions, save/replay and clear errors.
2. **Plot:** an authored site layout and playable boundary, with slots, fixed routes or terrain, mission/deployment/extraction capacity and a relationship to its surroundings. A plot may be a city block, refinery, or container yard; roads are not universal.
3. **Parcel:** an authored area such as a tank yard, loading yard, street corner or building. Define dimensions, allowed rotations, entry/connection geometry, ground/elevation, tactical surfaces and obstacles, mission suitability and asset dependencies. A human must be able to inspect and edit it. Start with owner-approved footprints of 16 x 16, 16 x 32 and 32 x 32 tactical tiles; allow a quarter-turn to make 32 x 16. Evaluate exceptions when real content demands them.
4. **Connectors:** the plot owns the required connection positions. Parcel interfaces declare what physically meets them, including direction and elevation. Verify that frontage, paths, pipe/road continuity and clearances actually align. Avoid automatic asset orientation based on names alone.
5. **Surroundings:** near-edge pieces continue roads, terrain or industrial structures past the boundary; a simpler distant backdrop establishes the horizon. The initial version can be authored with each plot and later made interchangeable if useful. Out-of-bounds scenery cannot be targeted or navigated. Visuals, ground and lighting should blend across the edge; camera behavior must be checked at normal and cinematic angles.
6. **Selection and failure:** choose compatible plot, mission-suitable slots and parcel rotations; use seeded deterministic ordering and bounded attempts. A missing required parcel/connection gives a clear reason, never a silent empty space. Produce resolved choices before activating battle.
7. **Tactical and replay:** reuse MapData and existing movement, LOS, cover and mission systems. Keep scenery separate from authoritative walkability and cover. Store map/content revisions, chosen parcels, transforms, population and mission choices; seed alone is insufficient if content changes. Reject incompatible saved data explicitly.
8. **Content and workflow:** build with calibrated downloaded assets and reusable custom components. Allow fully manual authoring, preview, editing and saving before registration for automatic use. Technical checks and the owner's visual/playability review are separate. Recover useful quarantined editor capabilities selectively; do not restore the old system wholesale.
9. **Quality and cost:** check reachable objectives and extraction, enough safe deployment cells, connected traversal, orientations and overlaps; inspect clean and diagnostic renders; test multiple known seeds. Measure generation time, battle size, turn pacing and rendering with representative maps. Give the owner a simple way to reproduce failures.

## First proof: one refinery family

Approved by Blue for implementation on 2026-11-02. This is a bounded proof, not a promise that the current Refinery 2 scene can immediately be used as a parcel.

- Author two distinct site plots with different circulation and slot arrangements. Use fixed layouts first; no procedural road graph.
- Prepare at least two compatible variants for one genuinely interchangeable slot, plus the minimum other areas required to make both sites coherent: process, tank/storage and loading/service areas. Reuse the existing refinery and components where practical; adapt its metadata deliberately rather than duplicating its map-specific runtime adapter.
- Add authored near surroundings that extend service roads/terrain into a larger industrial site, and one simple far landscape. Preserve the tactical boundary.
- Generate a fixed set of seeds and demonstrate different placements/layouts; retain an explicitly authored layout and a population-off mode. Check that actual parcel interfaces and objectives work, not just labels.
- Run reachability and replay checks; inspect overall, ground-level and edge/horizon captures; play full missions and compare travel time and tactical choices. Report failed seeds rather than silently replacing them.

A second urban proof should follow before generalizing the content model. Demonstrate two plot layouts and a few compatible parcels; evaluate whether the extra authoring effort creates enough variety for a small game. Layout composition is a goal, but unlimited layouts, general polygon packing, semantic AI assembly and a full custom editor are not prerequisites for the first proof.

## Owner decisions

1. **Initial scope — decided:** industrial proof first, urban second; use the existing refinery as reference, not automatically a finished parcel.
2. **Parcel sizing — decided:** start with 16 x 16, 16 x 32 and 32 x 32 tactical tiles, with quarter-turns where connections permit. Fit real pieces and measure movement pacing; revise the standard if evidence warrants it. A footprint includes its authored access and clearances, and assets must not be stretched to fill it.
3. **Periphery — decided:** authored near/far scene pieces per plot at first; interchangeability follows demonstrated benefit. These pieces are visual-only unless explicitly brought into the playable area.
4. **Editor — decided:** use Godot's existing scene editing and targeted validation initially; selectively recover the quarantined chunk editor as a small in-project **Parcel Editor** for the standard footprints. No second application and no restored runtime-generator dependency.
5. **Generator 1 — decided:** keep it and its replay compatibility until the replacement meets its obligations.

These five choices and the first refinery proof above are approved by the owner.

## Implementation progress — 2026-11-02

The owner authorized implementation and routine design decisions within this scope. The foundation is now intentionally smaller than the original proposal.

- `BattlefieldCatalog` replaces accumulating per-map runtime branches with stable identities while retaining old replay flags only for compatibility.
- `AuthoredSceneMapCompiler` is shared by Refinery 2 and the Loading Yard proof; no map-specific compiler duplication remains.
- `ParcelTransform` covers all cells of rectangular parcels under four rotations. `ParcelConnection` validates actual boundary cells, outward directions and widths and is consumed by the Loading Yard contract.
- Loading Yard remains the isolated 16x32 authoring proof. The selectable Refinery Family now composes the reviewed parcel family into two fixed plots; it is the active replacement proof, not a claim of a general generator.
- Runtime generation and battle initialization are measured in focused tests. Runtime catalog scans and unbounded search are prohibited.
- Next gate: play and replay both composed refinery sites across fixed seeds, replace the deliberately simple horizon blocks with authored industrial surroundings, and decide whether the parcel workflow needs the quarantined editor UX.

## Implementation ledger

This is the owner-facing progress record. A technical check and visual/playability approval are reported separately; “implemented” does not silently mean “artistically approved.” Update this table with each map-system checkpoint instead of creating a new roadmap.

| Requirement | State | Current evidence | Next acceptance gate |
| --- | --- | --- | --- |
| One runtime battlefield boundary | Implemented | `BattlefieldCatalog`, shared loading transition and explicit initialization failures | Keep new maps behind stable IDs; no new per-map booleans |
| Standard parcel geometry | Implemented | 16×16, 16×32, 32×32 policy; `ParcelTransform` exhaustively covers rectangular rotations | Add each new footprint to the same transform tests |
| Measured parcel connections | Implemented for pilot | `ParcelConnection` validates boundary cell, outward direction and width | Extend to multiple named interfaces only when process/storage content requires it |
| Loading/service parcel family | Technical and agent visual review complete; owner review pending | Two registered 16×32 variants share one measured 4-cell service interface, use different imported shells/layouts and compile under four rotations | Play both variants in composed plots and obtain owner review |
| Fixed place with varied content | Implemented for refinery proof | Runtime seeds select two reviewed loading variants; the accepted ID/revision/transform is stored in the map and replay configuration | Play/replay the fixed seed matrix |
| Process parcel | Technical and agent visual review complete; owner review pending | Open 16×16 process pad uses three calibrated machines, explicit tactical volumes and a measured 2-cell service interface | Validate within both plot circulation layouts |
| Tank/storage parcel | Technical and agent visual review complete; owner review pending | 16×16 storage pad uses calibrated tanks/container, explicit tactical volumes and a measured 4-cell service interface | Validate within both plot circulation layouts |
| Refinery plot resolver | Implemented and focused tests pass | Two fixed 64×64 site plans own exact process, storage and loading slots; seeded selection is bounded and records actual parcel IDs/revisions | Exercise negative runtime reconstruction and mission matrix |
| Refinery family compilation | Implemented; technical and agent visual review pass | Exact choices compile and present through shared boundaries; Match Setup starts a normal battle in about 2.1 s; clean captures show distinct split-yard and service-spine layouts | Owner visual review and full mission/replay matrix |
| Two refinery plots | Implemented | Site A uses split northern pads/southern loading; Site B uses a longitudinal service spine; both use the same parcel contracts | Refine sparse space only from play/visual evidence |
| Deterministic bounded resolver | Implemented | Fixed three-slot work, stable ordering, two loading candidates, no scans/backtracking, explicit stale/missing dependency errors | Keep this bounded unless the urban proof demonstrates a concrete need |
| Exact replay reconstruction | Implemented at configuration boundary | Replay JSON round-trips plot ID/revision, population mode, parcel IDs/revisions, origins and rotations; runtime records accepted choices, not seed alone | Execute full recorded battle playback on both sites |
| Near/far surroundings | Provisional visual implementation | Each plot owns fixed road continuation and visual-only horizon nodes outside tactical compilation | Replace crude horizon blocks with authored industrial scenery after play-space approval |
| Parcel Editor | Planned selective recovery | Retired editor UX inventoried in quarantine | Rebuild only standard-footprint placement, inspection, history and save workflow |
| Quality, mission and visual matrix | Partial | Loading Yard mission completes and replays 24/24; clean captures exist | Exercise both plots, fixed seeds, objectives, edge views and full missions |
| Post-generator simplification (“enxugar”) | Explicit future milestone | Current architecture and this ledger define ownership | After the refinery proof: remove stale code/docs, reduce concepts, and write an owner-oriented system guide |
