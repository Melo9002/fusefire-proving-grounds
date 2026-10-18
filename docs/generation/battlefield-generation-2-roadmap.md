# Battlefield Generation 2.0 Roadmap

Status: active, living roadmap

Baseline reviewed: `3a6b995` (`establish industrial generation handoff`)

Review date: 2026-10-15

## Goal

Build a deterministic assembly system for believable, tactically useful places. `MapData` remains authoritative for movement, cover, line of sight, elevation, traversal, deployment and objective suitability. Environment scenes present that state; they never create a second tactical map.

The installed Kenney library is a construction source, not a generator. The Industrial Warehouse is an authored integration experiment and test fixture, not the final generation architecture.

## Verified foundation

### Complete and reusable

- `MapData` stores cells by three-dimensional grid coordinate, column surfaces, zones, traversal links and generated structure summaries.
- `MapGraphBuilder`, `Pathfinder`, `MissionZonePlanner`, `MapValidator` and `MapQualityEvaluator` already operate on generated or authored `MapData`.
- Generated buildings, platforms, hills, bridges, stairs and ladders demonstrate authoritative elevated surfaces and vertical connectivity.
- `GeneratedTerrainPresenter` renders authoritative structures separately from simulation.
- `EnvironmentAssetPlacement` now measures complete imported hierarchies, applies rotation before fitting, preserves proportions with uniform scale, and floor-aligns assets inside authored envelopes.
- Camera occlusion supports ordinary physics geometry plus opted-in visual bounds. Roof cutaways are presentation-only and share camera focus with selection and cinematics.
- Floor picking derives available levels from walkable `MapData` surfaces. Optional elevation labels describe a layout without hard-coding warehouse levels into the UI.
- Generation seeds, preset identity, action recording and replay validation are established.

### Working but narrow

- The Industrial Warehouse has coherent tactical geometry, a loading yard, cargo lanes, machinery, a raised walkway, a walkable roof and two vertical links. Its geometry and asset choices are fixed constants.
- Roof cutaway uses one authored rectangular interior and roof volume. It is suitable for this building, but multiple overlapping buildings need explicit membership or separate cutaway volumes.
- The Asset Laboratory browses all 315 GLBs and inspects bounds, pivots, scale, rotation, grid alignment, a runtime MIRA reference and neighbor seams. It now resolves a general fallback, semantic category presets and persistent per-asset overrides; review state supports progressive catalog calibration. Fourteen representative assets have additional orientation/anchor metadata and measured source bounds.
- Existing generated buildings and refinery equipment are useful prototypes, but their layout and presentation descriptions are separate code paths.
- Map quality measures cover, routes, openness, clusters, lanes and deployment exposure. It does not yet understand roads, entrances, parcel adjacency or vertical access quality.

### Missing

- Mission requirements that reserve layout space before assembly.
- General quality scoring for open module seams, multi-intersection road networks and alternate vertical routes.

## Reference findings from the local XCOM 2 SDK

The War of the Chosen SDK was inspected locally under `XComGame/Config`, `Development/SrcOrig/XComGame/Classes`, and its map content. Its configuration exposes plot types, parcel maps, parcel objective tags, plot exclusions and biome-specific visual substitutions. Floor/building visibility classes separate floor membership and presentation groups from tactical state, with prioritized camera focus and reliable restoration.

FuseFire should adopt the division of responsibility rather than reproduce XCOM's native implementation:

1. A battlefield plot describes large-scale boundaries, routes and required regions.
2. Reusable modules fill compatible areas through explicit connectors and tags.
3. Mission requirements participate before final placement through suitability tags or reserved regions.
4. Visual variants may change presentation while the selected module's tactical footprint remains authoritative.
5. Floor and cutaway metadata remains presentation data linked to authoritative elevations.

## Capability areas

### 2.0 — Astra Handoff & Foundation Integration — demonstrated

The warehouse, imported assets, multilevel picking, cutaway behavior and replay integration have been inspected and validated. Shared asset fitting and data-driven floor labels are extracted from warehouse-only code. Remaining warehouse constants are deliberately retained until a real second module proves the correct schema.

### 2.1 — Asset Pack Integration & Calibration — demonstrated

All 315 retained GLBs import, instantiate and are searchable by pack and review state in the standalone Asset Laboratory. Project-local JSON persists category presets, per-asset scale/yaw/anchor/offset overrides and reviewed IDs using `asset override > category > fallback` resolution. Fourteen representatives retain additional source bounds, orientation, anchor conventions and compatibility notes. Rendered road, entrance, machinery and Space Kit assemblies verify seams and expose incompatible scales. Tactical footprints remain deliberately unauthored until Goal 2.2.

### 2.2 — Modular Environment Components — demonstrated (expanded catalog)

The lightweight component records separate logical footprints, layered ground/occupant/overhead reservations, clearances, tactical cell effects, explicit module types, elevation-aware semantic connectors, mission suitability, elevated surfaces, vertical links, and visual references. Twenty-two definitions now cover Factory walls, corners, doors, windows and floors; road intersections and alleys; a shop front, courtyard and loading dock; cargo, machinery and cover clusters; plus stairs, a road ramp, platform and walkway. Four deterministic opt-in presets validate overlap rejection, road continuity, doorway access, mission candidates, vertical traversal, authoritative cell translation, and shared presentation dispatch. `MapData` remains the committed tactical result.

Rendered inspection confirms the tactical foundation and also exposes visual overhang where logically adjacent machinery, cargo, or catwalk pieces can intersect. The [Goal 2.2 completion report](goal-2.2-completion-report.md) records this as an explicit Goal 2.3 input rather than making vendor mesh bounds authoritative.

### 2.3 — Coherent Layout Assembly — demonstrated (first procedural foundation)

A hierarchical opt-in assembler now selects an industrial, commercial, or mixed-service identity; builds a connected seeded crossroad or T-junction plot; derives road-facing parcels; and fills them with rotated authored storefront, workshop, loading, yard, alley, and courtyard templates. Parcel placement uses bounded transactional alternatives and an explicit open-ground fallback. Tactical footprints, same-layer placement clearances, and calibrated visual envelopes are separate contracts; candidate conflicts are rejected without making meshes authoritative. `EnvironmentLayoutPlan` retains deterministic decisions and diagnostics on `MapData`.

The Map Editor exposes authored and procedural layouts together, draws road and parcel boundaries, and reports topology, rejection, fallback, and tactical validation status. Multi-seed tests cover determinism, variation, road connectivity, termination, spatial conflicts, alternative selection, deployments, and shared presentation. The [Goal 2.3 implementation guide](coherent-layout-assembly.md) records architecture and inspection commands; the [completion report](goal-2.3-completion-report.md) records validation and current limits.

### 2.4 — Verticality & Geometry Occlusion — partial

Traversal, stacked surfaces, walkable roofs, camera cutaways and generic level selection exist. Multiple buildings, irregular floor volumes, smooth fades, per-building floor membership and validation of alternate vertical routes remain open.

### 2.5 — Mission-Aware Battlefield Generation — partial

Modules now expose spawn, objective and extraction candidate cells, and regressions resolve them against authoritative traversal. Missions still place zones after graph construction; future assembly should reserve required regions before modules are committed. Existing post-generation placement remains the compatibility fallback.

### 2.6 — Tactical Quality & Validation — partial

Connectivity, spawn capacity, objectives, traversal integrity and broad tactical metrics exist. Extend them when modules exist so checks are grounded in real metadata: connector closure, entrance access, road continuity, vertical-route redundancy and mission-specific approach quality.

### 2.7 — Designer Tools & Debug Views — partial (asset and module inspection demonstrated)

F3 map inspection, grid overlays, floor controls, seed reproduction and screenshot fixtures exist. The 2.1 Asset Laboratory adds family/search/review filters, orbit/zoom, native and calibrated bounds, pivots, grid/MIRA comparison, snapping, neighbor seams, assembly previews, persistent overrides, editable category/fallback presets, unsaved-state reporting and next-unreviewed navigation. The Map Editor switches among authored presets and procedural identities, regenerates by seed, supports click selection plus temporary transform adjustment, draws road/parcel plans, and summarizes rejection/fallback diagnostics. Per-socket, clearance-volume, visual-envelope, and rejected-candidate geometry overlays remain later tooling.

### 2.8 — Integrated Battlefield Generation Release — not started

Requires representative authored, procedural and hybrid presets using the shared module foundation, deterministic replay, mission completion, validation metrics and documented editing workflows.

## Next implementation slice

Grow the demonstrated 2.3 grammar with multi-intersection blocks, secondary roads, deeper building parcels, and more calibrated visual envelopes. Then begin 2.5 by letting mission requirements reserve suitability regions before parcel commitment. Keep procedural coherent layouts opt-in while broader tactical-quality thresholds are established.

## Constraints and deferred ideas

- Preserve replay, deterministic RNG ownership and existing mission behavior.
- Do not let imported collisions or mesh bounds decide tactical legality.
- Do not force slopes and continuous terrain into named building floors.
- Defer destruction, projectile interception, localized damage and additional biomes until the assembly foundation is proven.
