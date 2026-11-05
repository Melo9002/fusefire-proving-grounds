# FuseFire Generation 2.0: authored places, tactical population and composed maps

Status: active product direction and implementation ledger, updated 2026-11-05. The [Current map architecture](current-map-architecture.md) describes the smaller production architecture. The XCOM 2 study below supports one part of Generation 2.0—composing authored plots and parcels—but does not define the whole system or FuseFire's tactical identity.

## Where we are

- Generator 1, its original Refinery and the Industrial Warehouse remain playable. The former broad Generator 2 implementation is quarantined as described in [generation status](status.md); the new bounded Generation 2.0 refinery proof is active and intentionally does not restore it wholesale.
- Refinery 2 is a fixed authored 96 x 80 map, with real tactical data and replay integration. Its buildings and equipment do not rearrange with the seed. See [Refinery 2 handoff](refinery-2.md).
- We have reviewed Kenney assets, calibration, reusable catwalk components and the retained Asset Lab. The active refinery proof now resolves two authored plots and four standardized parcel roles through a bounded deterministic path. It is not yet a general map authoring workflow.
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

## Generation 2.0 product scope

Generation 2.0 is the complete authored-map pipeline, not merely an XCOM-like parcel selector. Its responsibilities are deliberately layered:

1. **Place composition:** authored plots establish the playable site, circulation, parcel slots and surroundings; compatible authored parcels provide recognizable functional areas.
2. **Tactical population:** authored regions describe which movable tactical elements may occupy meaningful locations within those places.
3. **Tactical compilation:** accepted authored choices compile into authoritative `MapData`; visuals never silently determine movement, cover or LOS.
4. **Reconstruction:** the exact accepted plot, parcels, population choices and revisions survive battle, save and replay boundaries.
5. **Authoring:** Godot scenes and focused in-project tools let a human build, inspect and approve content before it enters selection.

The XCOM comparison is most useful for the first layer. FuseFire should differ by making tactical population an explicit authored vocabulary instead of scattering generic cover props wherever free cells happen to exist.

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

## FuseFire tactical population regions

Parcels and plots may author named population regions. A region is a deliberate semantic location—not a generic rectangle that accepts arbitrary clutter. Examples include parking bays that permit cars, depot stacks that permit shipping containers, loading aprons that permit delivery vehicles, machinery pads that permit compatible equipment, and selected open areas that permit appropriate cover.

The initial contract should remain small and inspectable:

- Stable region identity owned by a plot or parcel.
- Local cells or bounded placement sockets, transformed with the owning content.
- An allow-list of population roles or curated candidate IDs; semantic tags alone do not prove geometric compatibility.
- Supported orientations, count or density bounds, clearances and required access that must remain open.
- Required, optional or population-off behavior.
- Deterministic seeded selection with bounded attempts and explicit rejection reasons.
- Exact accepted asset IDs, revisions and transforms recorded for replay; the seed alone is insufficient.
- Explicit tactical effects compiled into `MapData`. A spawned visual mesh does not acquire cover, occupancy or LOS authority automatically.

This restores the useful intent of Generator 1—designers decide *where* tactical variation is allowed and *what kind* belongs there—without restoring its unrestricted scatter logic. The first proof uses authored regions inside existing refinery parcels: depot container positions and parking/loading vehicle positions. The next authoring direction below extends this proven slice; painting and broader automatic placement are not implemented yet.

### Population authoring direction — 2026-11-05

Owner request: retain manual placement and allow the editor to mark or paint where particular tactical elements may spawn. Recommended initial workflow: select a floor, mark a bounded region, choose a curated population preset, set occupancy/count bounds, and preview a seed. A parking preset should place aligned bays/sockets with an aisle and protected approaches; a depot preset may use container sockets. Free painting suits permission and exclusion masks, while aligned objects still require authored placement geometry. Brush strokes must resolve against the selected tactical surface, not accidentally paint a roof above it. Show valid candidates, exclusions and rejected footprints; support erase and undo/redo.

Use three placement modes in the same scene: fixed manual occupants, optional procedural sockets, and explicit empty/protected regions. Manual occupants and required access take priority. Accepted procedural objects need explicit tactical contracts and cannot overlap reserved approaches, structural supports or another floor's clearance. Population-off removes procedural occupants only. Preview choices and exact accepted placements should be inspectable before use in battle.

One battle seed is enough. Derive independent random streams from a documented stable mixing function over the battle seed, plot/slot instance ID, region ID, socket ID and decision purpose (occupancy, asset, heading). These small streams are cheap; owners do not author individual parcel seeds. Stable identities, sorted candidates and bounded work keep a change in one region from unnecessarily rerolling every other region. Avoid runtime object IDs, collection order and unspecified string hashes. This is a proposed improvement: the current resolver still uses its simple seed/index arithmetic. Store accepted IDs, heading/transforms and content/algorithm revisions for reconstruction; the seed alone cannot preserve history after content changes.

### Next proposed family: a multi-storey parking structure

Use one fixed authored structure with a small number of floors and many population fields as the next focused content proof. A whole authored map is supported: it need not be partitioned just to exercise parcels. A reusable building may later become one parcel if its measured size and interfaces justify that choice. Measure real bays, aisle widths and travel distances before deciding the footprint; do not force a large garage into 32×32 or stretch assets to fill it.

Author slabs, columns, perimeter walls/rails, entry/exit routes and vertical connections together. Start with two playable floors and two distinct ground-to-upper-floor approaches using supported stairs/ramps or traversal links. Driving simulation is unnecessary. A visible route must agree with authored movement, elevation, cover and LOS. Audit available assets and reusable components first; any missing structural content must be acknowledged and authored deliberately.

Car fields represent real parking bays: each bay owns a supported vehicle envelope, nominal heading, floor, clearance and allowed car list. Deterministically choose empty/occupied, vehicle and forward/reverse parking (0°/180° relative to that bay). Preserve aisle access and align wheels with the supporting surface. Avoid unconstrained yaw or position jitter; small variation requires measured space. Wider vehicles require appropriate bays. Fixed owner-placed cars remain possible. Persist each accepted heading; compile its rotated tactical contract at the correct level. Population records now support an optional `yaw_turns` choice for sockets that explicitly permit it. Asset selection still references preauthored occupants. Current region rectangles have no floor field; explicit surface/elevation ownership is required before multi-floor painting.

### Visibility and floor dependencies

Owner direction: investigate a local camera cutaway around an occluded selected character, inspired by the supplied BG3 reference, together with Sims-like wall/floor hiding. This describes the desired result, not a verified account of either game's implementation. Existing FuseFire roof cutaways, terrain fading and inspected-floor selection are the starting points.

Keep three presentation controls understandable: selected/inspected floor visibility, authored wall/roof cutaway groups, and a local aperture or dissolve through geometry between the camera and selected friendly character. Prototype the local aperture on one wall before choosing a shader or broader renderer change. Use soft transitions and restore materials when selection, camera or floor changes. Upper slabs may hide independently of their supporting columns; hiding a parent node must not erase every lower floor. Test low camera pitch, overhead, stairs between floors and action/replay cameras.

Visual hiding must preserve MapData occupancy, LOS, cover, supports and traversal. A camera aperture must not reveal undiscovered enemies or create targeting permissions. Background scenery is separately owned and non-tactical, but may still obscure the selected character and need presentation-only fading. Floor membership must be authored explicitly rather than guessed from a node's height. Check visible floor edges, shadows, collision/raycast selection and HUD markers during cutaway review.

### Small delivery steps

1. Extend an existing parking region with forward/reverse bay choices and exact replay reconstruction; inspect a few seeds and population-off.
2. Add floor/surface ownership to population data and a targeted editor region/bay tool with manual placement, erase and undo. Validate preservation through saving and reloading.
3. Author a compact two-floor parking proof with two usable vertical approaches, before attempting a larger family or interchangeable structural floors.
4. Test one wall aperture and upper-floor cutaway, including background occluders and selected-character visibility. Preserve tactical concealment.
5. Combine parking population, deployment/objective reachability, mission/replay checks and owner camera/play review. Measure density and travel pacing before expanding the map.

These are recorded product directions and proposed implementation steps. A multi-storey parking family, painting tool and local aperture remain unimplemented. The first parking variation checkpoint is recorded below.

### Parking variation checkpoint — 2026-11-05

Implemented: the office parking parcel's three car sockets explicitly allow relative quarter-turns 0 and 2. The resolver chooses heading with SHA-256 over a JSON tuple containing battle seed, plot/slot instance, parcel, region, socket and `parking_heading_v1`. The first eight hexadecimal digest digits select from the ordered allowed turns. This decision does not consume global RNG or depend on another socket's order. Existing occupancy selection remains unchanged. No extra owner-managed seed is needed.

The accepted `yaw_turns` travels through replay JSON. Applying population rotates the complete occupant, including its authored tactical volume, once relative to its saved base orientation. Unsupported turns and malformed heading values reject; historical records without the field retain their original authored orientation. Fixed manually authored content and population-off retain their existing behavior. No asset/calibration changes are involved.

Verification: `parking_population_test.gd` exercises 16 street seeds, both headings, actual replay JSON with a different supplied reconstruction seed, all four parcel rotations using a real imported car, repeated application, invalid values and historical records. Urban/refinery layouts, catalog, replay schema and Parcel Editor suites pass. Five frontage captures include an explicit forward/reverse neighboring-bay case; overhead and street-front views were inspected. This is technical and agent visual evidence, pending owner visual review. Next: explicit floor/surface ownership for regions and sockets, then the editor field tool.

## Catwalk direction

Catwalks should initially be authored structural assemblies owned by particular parcels, not freely generated across unrelated parcels. Their value comes from deliberate elevation, sightlines, support geometry and access, all of which are easy to break with unconstrained procedural placement.

A catwalk-capable parcel should author the deck, supports, railings, stairs or ladders, and explicit elevated tactical cells and traversal links together. Where two parcels are intentionally designed to connect, they may expose measured catwalk interfaces containing boundary position, direction, elevation, width and clearance. The plot may only join interfaces known to be compatible. Cosmetic variants or small prop populations may vary inside the assembly, but the load-bearing route remains authored and certified.

The first catwalk proof should therefore be a dedicated 16×32 or 32×32 refinery parcel variant inspected in isolation and in one plot slot. A general procedural catwalk router is not a prerequisite and should not be introduced without a concrete content need.

## First proof: one refinery family

Approved by Blue for implementation on 2026-11-02. This is a bounded proof, not a promise that the current Refinery 2 scene can immediately be used as a parcel.

- Author two distinct site plots with different circulation and slot arrangements. Use fixed layouts first; no procedural road graph.
- Prepare at least two compatible variants for one genuinely interchangeable slot, plus the minimum other areas required to make both sites coherent: process, tank/storage and loading/service areas. Reuse the existing refinery and components where practical; adapt its metadata deliberately rather than duplicating its map-specific runtime adapter.
- Add authored near surroundings that extend service roads/terrain into a larger industrial site, and one simple far landscape. Preserve the tactical boundary.
- Generate a fixed set of seeds and demonstrate different placements/layouts; retain an explicitly authored layout and a population-off mode. Check that actual parcel interfaces and objectives work, not just labels.
- Run reachability and replay checks; inspect overall, ground-level and edge/horizon captures; play full missions and compare travel time and tactical choices. Report failed seeds rather than silently replacing them.

A second urban proof should follow before generalizing the content model. Demonstrate two plot layouts and a few compatible parcels; evaluate whether the extra authoring effort creates enough variety for a small game. Layout composition is a goal, but unlimited layouts, general polygon packing, semantic AI assembly and a full custom editor are not prerequisites for the first proof.

### Urban proof progress

Deployment correction (2026-11-04): shared family compilation now revalidates the flat generator's deployment zones after all authored tactical solids have been stamped. Legal connected cells stay unchanged; invalid cells move deterministically to the nearest free connected stopping cell in the same original column, with lower row as the distance tie-break. All replacement choices are committed together. Exhausted columns return `UNSATISFIABLE_DEPLOYMENT` before battle activation. Reconstruction uses the recorded manifest seed for the base map as well as recorded parcel/population choices. The regression covers real compiled terrain, rejection of an impossible column, idempotence and a fixed urban/refinery seed matrix. Earlier replay recordings have no compiler revision field; historical playback across this correction remains limited where a formerly invalid deployment would have existed.

Owner feedback (2026-11-04): the 64×64 previews feel too sparse for their size. Next composition work should fit more purposeful parcels within the current boundary and evaluate travel pacing before enlarging maps. Keep the courtyard catwalks for now; they suit the industrial/service setting better than ordinary urban streets. The new middle-mouse pitch control supports inspection from near ground level through overhead; comfort and sensitivity await owner play feedback.

The first isolated 32×32 urban parcel is registered as `industrial_office_parking_a`. It uses the reviewed complete `city_kit_industrial/building-a` exterior shell, an explicit eight-cell street frontage and a curated `visitor_parking` region for sedan/SUV/taxi sockets. The building remains an inaccessible sealed shell; parking population can be removed without deleting the fixed frontage. Four-rotation tactical compilation passes, and overhead/front/rear/side captures confirm the actual facade and complete shell geometry.

`urban_service_street_a` is the first fixed 64×64 plot foundation. It owns one five-cell east-west imported-asset road, exact adjacent interfaces for the office frontage plus existing process/storage parcels, four verified inward-facing streetlights and authored near/far continuation. Plot validation proves parcel/road non-overlap, interface adjacency, lamp-head orientation and valid tactical compilation; clean overhead/oblique/street captures were inspected.

`urban_signal_courtyard_b` is the genuinely distinct second 64×64 plot. It does not synthesize another street: a 32×32 signal/objective courtyard is enclosed by two mirrored 16×32 elevated gallery parcels and compact north-edge process/storage parcels, while a deliberately open southern approach preserves deployment and sightline space. The courtyard owns curated container/crate cover sockets and a fixed imported-screen landmark; the galleries own their decks, supports, rails, ladders and elevated tactical contracts. Exact interfaces, non-overlap, ground-to-gallery traversal and two independent approach paths pass focused validation. Clean overhead, approach, oblique and gallery views were inspected.

The concept-art goal is encoded as spatial grammar rather than claimed asset fidelity: compressed authored edges, a legible central landmark, elevated flanks, purposeful cover lanes and an open approach. Current Kenney content remains visually sparse and low-detail relative to that target. Both plots are now available through **Generated authored parcels — Urban family (preview)** in Match Setup. Even seeds select the street; odd seeds select the courtyard. The population checkbox controls only authored movable sockets.

Urban runtime checkpoint (2026-11-04): `UrbanFamilyLayout` supplies the urban catalog to the refinery proof's bounded resolver and shares its tactical compiler and presenter. Accepted plot/parcel IDs, revisions, origins, rotations and population choices are stored in the existing content manifest and replay JSON. Reconstruction preserves the original manifest seed and rejects stale revisions, missing slots, changed transforms and invalid population. Region counts cannot exceed available sockets. Standard map deployment still uses the existing edge-spawn policy; the courtyard's open south approach is not yet a mission-specific deployment assignment. Content revisions are explicit authoring revisions, not automatic geometry hashes.

Verification: seeds 16–21 pass deterministic layout/JSON/presentation/population-off and negative reconstruction tests. Reach missions on street seed 16 and courtyard seed 17 both complete in three rounds, with 47/47 and 50/50 replay actions verified respectively. Clean captures now use the actual runtime compilation/presentation path. These results cover Reach and exact reconstruction; owner play review, other urban mission types, action-camera visual review and final visual approval remain pending.

Reproduce with `godot_console --headless --path . --script res://tests/urban_family_layout_test.gd` and `godot_console --headless --path . --script res://tests/refinery_family_ai_smoke.gd -- urban`. The latter is an explicit longer gameplay/replay check. Existing refinery behavior uses the same test without `-- urban`.

## Owner decisions

1. **Initial scope — decided:** industrial proof first, urban second; use the existing refinery as reference, not automatically a finished parcel.
2. **Parcel sizing — decided:** start with 16 x 16, 16 x 32 and 32 x 32 tactical tiles, with quarter-turns where connections permit. Fit real pieces and measure movement pacing; revise the standard if evidence warrants it. A footprint includes its authored access and clearances, and assets must not be stretched to fill it.
3. **Periphery — decided:** authored near/far scene pieces per plot at first; interchangeability follows demonstrated benefit. These pieces are visual-only unless explicitly brought into the playable area.
4. **Editor — decided:** use Godot's existing scene editing and targeted validation initially; selectively recover the quarantined chunk editor as a small in-project **Parcel Editor** for the standard footprints. No second application and no restored runtime-generator dependency.
5. **Generator 1 — decided:** keep it and its replay compatibility until the replacement meets its obligations.

The first five choices and the refinery proof above were approved during the initial grounding pass. The owner subsequently approved the following FuseFire-specific directions:

6. **Tactical population — decided:** plots and parcels author meaningful spawn regions and curated eligible roles. Parking lots may receive cars; depots may receive containers. Exact choices are deterministic and replayed, while `MapData` remains authoritative.
7. **Catwalks — decided direction:** begin with parcel-owned authored catwalk assemblies and explicit elevated tactical contracts. Cross-parcel connections require measured compatible interfaces; unrestricted procedural routing is deferred.

## Implementation progress — 2026-11-03

The owner authorized implementation and routine design decisions within this scope. The foundation is now intentionally smaller than the original proposal.

- `BattlefieldCatalog` replaces accumulating per-map runtime branches with stable identities while retaining old replay flags only for compatibility.
- `AuthoredSceneMapCompiler` is shared by Refinery 2 and the Loading Yard proof; no map-specific compiler duplication remains.
- `ParcelTransform` covers all cells of rectangular parcels under four rotations. `ParcelConnection` validates actual boundary cells, outward directions and widths and is consumed by the Loading Yard contract.
- Loading Yard remains the isolated 16x32 authoring proof. The selectable Refinery Family now composes the reviewed parcel family into two fixed plots; it is the active replacement proof, not a claim of a general generator.
- Runtime generation and battle initialization are measured in focused tests. Runtime catalog scans and unbounded search are prohibited.
- Both composed sites now pass the fixed-seed Reach/replay proof. The next product gates are owner play/visual review, a small additional-mission matrix, and deciding whether real parcel authoring justifies recovering the quarantined editor UX.

## Implementation ledger

This is the owner-facing progress record. A technical check and visual/playability approval are reported separately; “implemented” does not silently mean “artistically approved.” Update this table with each map-system checkpoint instead of creating a new roadmap.

| Requirement | State | Current evidence | Next acceptance gate |
| --- | --- | --- | --- |
| One runtime battlefield boundary | Implemented | `BattlefieldCatalog`, shared loading transition and explicit initialization failures | Keep new maps behind stable IDs; no new per-map booleans |
| Standard parcel geometry | Implemented | 16×16, 16×32, 32×32 policy; `ParcelTransform` exhaustively covers rectangular rotations | Add each new footprint to the same transform tests |
| Measured parcel connections | Implemented for pilot | `ParcelConnection` validates boundary cell, outward direction and width | Extend to multiple named interfaces only when process/storage content requires it |
| Loading/service parcel family | Technical and agent visual review complete; preliminary owner visual direction accepted | Two registered 16×32 variants share one measured 4-cell service interface, use different imported shells/layouts and compile under four rotations. Both variants occur in the passing plot and replay matrix. The owner considers the current refinery maps decent and expects denser population later. | Owner play review; enrich population only through authored regions |
| Fixed place with varied content | Implemented for refinery proof | Runtime seeds select two reviewed loading variants; the accepted ID/revision/transform is stored in the map and replay configuration. Both fixed plot seeds complete and replay. | Extend variation only through another authored, reviewed need |
| Authored tactical population regions | First deterministic refinery slice implemented | Both 16×32 loading variants define bounded `depot_containers` and `loading_vehicles` regions with stable identities, curated allow-lists and certified occupant sockets. The resolver selects one or two containers plus the required loading vehicle within a fixed budget; exact choices drive presentation and tactical compilation and round-trip through replay. Population-off preserves the complete plot and parcels while omitting only socket occupants. Invalid or stale choices fail instead of being substituted. Match Setup exposes the mode only for the Refinery Family. | Add owner-reviewed parking/depot variants only when a parcel calls for them |
| Parcel-owned catwalk assemblies | First 16×32 parcel integrated and gameplay/replay validated; owner review pending | `maintenance_gallery_a` authors a level-4, two-cell-wide gallery from retained deck, support and ladder components, deliberate safety rails and two calibrated machines. All rotations preserve the elevated route and ladder access. Site A owns a measured southwest service-road slot with no road/parcel overlap; seed 16 completes Reach in 3 rounds and replays 47/47 actions with the gallery present. Clean plot captures show grounded supports and an open road approach. | Owner play/visual review; add cross-parcel interfaces only after a real second endpoint exists |
| Process parcel | Technical/agent review complete; included in preliminarily accepted visual direction | Open 16×16 process pad uses three calibrated machines, explicit tactical volumes and a measured 2-cell service interface; both fixed plots compile and play with it | Refine only from owner play evidence |
| Tank/storage parcel | Technical/agent review complete; included in preliminarily accepted visual direction | 16×16 storage pad uses calibrated tanks/container, explicit tactical volumes and a measured 4-cell service interface; both fixed plots compile and play with it | Refine only from owner play evidence |
| Refinery plot resolver | Implemented and focused tests pass | Two fixed 64×64 site plans own exact process, storage, loading and (for Site A) maintenance slots; seeded selection is bounded and records actual parcel IDs/revisions | Preserve explicit failures as new authored content is added |
| Refinery family compilation | Implemented; technical and agent visual review pass | Exact choices compile and present through shared boundaries; clean captures show distinct split-yard and service-spine layouts, imported road tiles and Site A's elevated maintenance route. Both fixed seeds complete and replay. | Owner visual/play review and additional supported mission kinds |
| Two refinery plots | Implemented | Site A uses split northern pads, southern loading and a road-facing maintenance gallery; Site B uses a longitudinal service spine. Shared contracts do not require identical slot counts. | Refine sparse space only from play/visual evidence |
| Deterministic bounded resolver | Implemented | Plot-owned fixed work (maximum four slots), stable ordering, two loading candidates, no scans/backtracking, explicit stale/missing dependency errors | Keep this bounded unless the urban proof demonstrates a concrete need |
| Exact replay reconstruction | Implemented and exercised on both refinery plots | Replay JSON round-trips plot ID/revision, population mode, parcel IDs/revisions, origins and rotations; runtime records accepted choices, not seed alone. Site A seed 16 replayed 47/47 actions and Site B seed 17 replayed 94/94 actions. | Extend the same contract to later authored plot families |
| Near/far surroundings | Implemented; preliminary owner visual direction accepted | Calibrated Kenney roads continue beyond the tactical boundary; each plot authors a second background service road and a bounded set of imported factories, stacks, towers and lights on visual-only terrain. The owner considers the overall result decent; richer population remains future authored work. | Inspect cinematic cameras during owner play and adjust only from observed problems |
| Parcel Editor | Inspection and visual-draft foundation implemented | Match Setup opens a compact tool that lists the active catalog, validates each scene, frames standard footprints, supports orbit/pan/zoom, isolates movable population, and overlays elevated/access versus solid tactical contracts. Authored visual nodes can be moved/quarter-turned with undo/redo and saved as revision-bound user drafts; runtime scenes and tactical metadata remain untouched. Rendered maintenance/loading captures were inspected. | Use it during owner parcel review; add an asset browser or source-scene application only for a concrete authoring need |
| First urban frontage parcel | Isolated technical and agent visual proof complete | Registered 32×32 parcel uses a complete sealed industrial building, measured street frontage and curated visitor-parking population. All rotations compile; all-side captures show the real shell and clear approach. | Add a compatible variant only after the first plot demonstrates the need |
| First urban street plot | Authored technical and agent visual foundation complete | Fixed 64×64 plot owns one imported road, three exact parcel slots, verified road-facing lights and near/far continuation. Shared slot validation also replaces the refinery resolver's duplicate compatibility logic. It compiles tactically and renders coherently but remains outside runtime selection. | Owner comparison against the courtyard plot; runtime registration remains deferred |
| Second urban courtyard plot | Runtime preview; Reach/replay verified | Fixed 64×64 plot composes a signal courtyard, two mirrored parcel-owned catwalk galleries and two compact industrial edge parcels around an open south approach. Seed 17 completes Reach in three rounds and verifies 50/50 replay actions. Urban family shares refinery resolution, compilation and presentation; seed 16 street verifies 47/47 replay actions. | Owner visual/play review, additional urban missions and deliberate deployment design |
| Quality, mission and visual matrix | Both plots pass Reach/replay plus a bounded additional mission matrix; preliminary owner visual direction accepted | Loading Yard replays 24/24. Refinery Family Site A seed 16 completes Reach in 3 rounds and replays 47/47 actions with the catwalk parcel, then completes Eliminate in 7 rounds/75 decisions. Site B seed 17 completes Reach in 5 rounds and replays 94/94 actions, then completes Rescue and extraction in 9 rounds/135 decisions. Clean overhead/oblique/ground captures cover both plots. The owner considers the current composition decent while explicitly deferring richer population. | Owner play review; add another mission only when it exercises an unproven map obligation |
| Post-generator simplification (“enxugar”) | Explicit future milestone | Current architecture and this ledger define ownership | After the refinery proof: remove stale code/docs, reduce concepts, and write an owner-oriented system guide |
