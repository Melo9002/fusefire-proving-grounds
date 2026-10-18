# Coherent Layout Assembly

Goal 2.3 turns the reusable Goal 2.2 modules into seeded places with roads, parcels, complete structures, functional open areas, and authoritative tactical connectivity. The procedural path remains opt-in and shares the same `MapData` authority and modular presenter as authored layouts.

## Generation hierarchy

`CoherentEnvironmentAssembler` builds a layout in seven bounded steps:

1. Select an environment identity: industrial district, commercial street, or mixed service.
2. Build a connected macro road plot from a crossroad or T-junction grammar.
3. Derive road-facing parcels, including one larger 20 × 20 district parcel where space permits.
4. Choose authored parcel compositions appropriate to the identity and parcel size.
5. Rotate each composition toward a compatible road edge and try bounded alternatives.
6. Add contextual street furniture after the road graph is known.
7. Commit accepted tactical effects to `MapData`, validate routes, and repair deployment candidates onto road-connected ground when necessary.

Identical inputs and seeds make the same decisions. Different seeds can change the road topology, district parcel location, parcel composition, component variation, and contextual details.

## Plot and parcel influence

The design adapts the useful division of responsibility from XCOM 2's Plot and Parcel system. Inspection of the installed War of the Chosen SDK found separate plot organization, parcel sizes and eligibility, street-facing entrance slots, objective tags, spawn density, deterministic parcel selection, backtracking records, and plot-cover parcels that close seams.

FuseFire uses the same broad lesson rather than copying XCOM code or data: the road plot establishes large-scale organization; authored parcels supply coherent functional places; explicit sockets and metadata join them; bounded alternatives prevent a failed candidate from corrupting the map. Small props decorate a resolved place instead of defining its structure.

## Spatial contracts

The assembler keeps four responsibilities distinct:

- **Tactical footprint** writes authoritative movement, stopping, cover, line-of-sight, occupancy, elevation, and traversal data.
- **Placement clearance** reserves physical or functional room around entrances, machinery, seams, and access routes.
- **Visual envelope** describes calibrated mesh extent for rejecting undesirable same-layer intersections. It does not create gameplay collision.
- **Connections** describe semantic access such as roads, paving, exterior entrances, and vertical links with position, facing, and elevation.

The presenter resolves catalog visual references through the saved Asset Lab calibration at runtime. A visual scale adjustment therefore does not silently rewrite a component's tactical footprint.

## Current compositions

The first grammar includes:

- Continuous road surfaces for every logical road and intersection cell.
- A large industrial shell parcel using a complete City Kit Industrial building asset.
- A validated, exact-geometry service building with a complete shell, roofed usable floor, and one road-facing entrance.
- Loading areas with calibrated containers and dumpsters.
- Machinery yards with perimeter fencing.
- Paved service alleys and courtyards.
- Road-context traffic signals, stop signs, streetlights, and utility poles.

Freestanding shop fronts and window walls remain valid catalog modules for authored assemblies, but the procedural generator no longer treats them as complete buildings.

## Map Editor inspection

Launch a representative layout with:

```powershell
godot_console --path . res://tools/map_editor.tscn -- 2208 industrial_district
```

Useful identities and seeds:

- `industrial_district 2208`
- `commercial_street 7319`
- `mixed_service 11027`

Use right-drag to orbit, middle-drag to pan, the wheel to zoom, and click a component to select it. Press `P` or use **Plan overlay** to hide the cyan road and amber parcel diagnostics for an unobstructed rendered view. Seed controls reproduce or vary the layout.

The automated capture fixture records overview, overhead, and street-level views:

```powershell
godot_console --path . --resolution 1440x900 --script res://tests/coherent_layout_capture.gd -- artifacts/goal23-quality
```

Rendered captures are inspection evidence; headless tests do not establish visual correctness.

## Adding a parcel composition

1. Build it from registered module definitions or add a small reusable definition to `IndustrialModuleCatalog`.
2. Give the composition a functional identity, required parcel size, and road-facing rule.
3. Reserve entrance and access clearances independently from tactical occupancy.
4. Add visual envelopes for assets that can overhang their logical cells.
5. Keep props subordinate to the parcel's purpose.
6. Add a fixed-seed regression for connectivity, legality, and important composition rules.
7. Inspect overview, overhead, and street-level renders.

## Current limits

- The road grammar has one intersection with straight approaches; lane markings, curves, secondary streets, and multi-block networks remain future work.
- The grammar currently creates at most one large district parcel per map.
- City Kit building shells are exterior-only tactical obstacles. Derived service buildings are enterable, but they do not yet have furnished interiors or gameplay-driven roof cutaways. See [Structural Building Assemblies](structural-building-assemblies.md) for the asset measurements and completeness contract.
- Contextual details use a small subset of the calibrated catalog. More authored parcel assemblies are needed before every seed can have the same visual density.
- Mission suitability is validated after assembly. Future mission-aware generation should reserve required parcels before commitment.
- Procedural vertical parcels remain deferred while the existing authored vertical fixture protects traversal behavior.
