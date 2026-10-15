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
- The Asset Laboratory browses all 315 GLBs and inspects bounds, pivots, scale, rotation, grid alignment, a runtime MIRA reference and neighbor seams. Fourteen representative assets have curated visual profiles and measured source bounds.
- Existing generated buildings and refinery equipment are useful prototypes, but their layout and presentation descriptions are separate code paths.
- Map quality measures cover, routes, openness, clusters, lanes and deployment exposure. It does not yet understand roads, entrances, parcel adjacency or vertical access quality.

### Missing

- Typed module definitions with footprints, connectors, compatibility tags and presentation references.
- Plot/parcel or equivalent layout grammar for roads, lots, buildings and open spaces.
- A tactical module definition that links calibrated presentation assets to authoritative footprints and connectors.
- Mission requirements that reserve layout space before assembly.
- Validation for module seams, entrances, road connectivity and alternate vertical routes.

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

All 315 retained GLBs import, instantiate and are searchable in the standalone Asset Laboratory. Fourteen representatives across all packs have persisted source bounds, categories, uniform scales, anchor conventions and compatibility notes. Fixed-scale placement preserves authored pivots for connected families; fit-to-envelope remains available for standalone authored prop reservations. Rendered road, entrance, machinery and Space Kit assemblies verify seams and expose family-specific scale. Tactical footprints remain deliberately unauthored until Goal 2.2.

### 2.2 — Modular Environment Components — not started

Define the smallest module resource from two real examples, likely a warehouse bay and a loading-yard or road segment. It should pair authoritative footprint operations with presentation references, entrances/connectors, allowed rotations, elevation surfaces and suitability tags. Keep `MapData` as the committed result.

### 2.3 — Coherent Layout Assembly — not started

Assemble plots from compatible modules using seeded ordering. Begin with one industrial grammar: road edge → loading yard → warehouse entrance → interior/service space. Prove rotation, connection matching, clearance and deterministic rejection diagnostics before adding city districts.

### 2.4 — Verticality & Geometry Occlusion — partial

Traversal, stacked surfaces, walkable roofs, camera cutaways and generic level selection exist. Multiple buildings, irregular floor volumes, smooth fades, per-building floor membership and validation of alternate vertical routes remain open.

### 2.5 — Mission-Aware Battlefield Generation — partial

Missions currently place zones after graph construction and validate reachability. Future assembly should expose objective/deployment suitability and reserve required regions before modules are committed. Existing post-generation placement remains the compatibility fallback.

### 2.6 — Tactical Quality & Validation — partial

Connectivity, spawn capacity, objectives, traversal integrity and broad tactical metrics exist. Extend them when modules exist so checks are grounded in real metadata: connector closure, entrance access, road continuity, vertical-route redundancy and mission-specific approach quality.

### 2.7 — Designer Tools & Debug Views — partial (asset calibration demonstrated)

F3 map inspection, grid overlays, floor controls, seed reproduction and screenshot fixtures exist. The 2.1 Asset Laboratory adds search, orbit/zoom, native and calibrated bounds, pivots, grid/MIRA comparison, snapping, neighbor seams, assembly previews and JSON copy-out. Module connector and rejection overlays should arrive with 2.2–2.3.

### 2.8 — Integrated Battlefield Generation Release — not started

Requires representative authored, procedural and hybrid presets using the shared module foundation, deterministic replay, mission completion, validation metrics and documented editing workflows.

## Next implementation slice

Define two small 2.2 module records from the now-verified road/paving and Factory entrance assemblies. Keep their authoritative footprints, clearance and connectors separate from the visual calibration profile. Then replace a fixed portion of the warehouse with seed-selected compatible variants while preserving the same authoritative entrances and mission reachability.

## Constraints and deferred ideas

- Preserve replay, deterministic RNG ownership and existing mission behavior.
- Do not let imported collisions or mesh bounds decide tactical legality.
- Do not force slopes and continuous terrain into named building floors.
- Defer destruction, projectile interception, localized damage and additional biomes until the assembly foundation is proven.
