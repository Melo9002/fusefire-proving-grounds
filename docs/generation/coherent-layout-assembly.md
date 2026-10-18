# Coherent Layout Assembly

Goal 2.3 adds an opt-in hierarchical generator above FuseFire's Goal 2.2 module catalog. It plans a recognizable place before placing individual objects:

1. Select an environment identity.
2. Build one connected macro-scale road plot.
3. Divide the remaining macro cells into parcels and record their road-facing edges.
4. Fill each parcel from a small authored template grammar.
5. Reject templates that violate tactical footprints, placement clearance, or calibrated visual envelopes.
6. Commit the completed module layout into authoritative `MapData` through the shared module writer.

The first identities are `industrial_district`, `commercial_street`, and `mixed_service`. They choose different parcel-template sets and therefore produce different structure and obstacle densities. Crossroads and rotated T junctions vary with the seed. Every road approach continues to a map boundary, so the initial grammar does not create unexplained internal dead ends.

This path is opt-in through `FlatMapGenerator.generate_coherent_environment()`. Existing flat, cover, refinery, warehouse, and authored modular generation remain available.

## Architecture

`CoherentEnvironmentAssembler` owns planning and bounded placement. `EnvironmentLayoutPlan` records the selected identity, seed, topology, macro road cells, parcel bounds, template choices, rejected candidates, search attempts, fallback use, and deterministic signature. `EnvironmentModuleMapWriter` is the single translator used by authored and procedural layouts to copy tactical effects, elevated surfaces, and vertical links into `MapData`.

The generator uses authored parcel templates rather than selecting unrelated modules wherever cells happen to be empty. Current templates describe a storefront, loading bay, industrial yard, workshop frontage, service alley, and courtyard. Their rotation is derived from a parcel's adjacent road edge. The templates reuse the same 22-component catalog and do not contain a separate tactical representation.

The base flat generator still establishes authoritative ground cells and faction ownership. If a newly placed obstacle claims an existing deployment cell, coherent assembly moves only that invalid deployment position to the nearest deterministic walkable stopping cell. The shared map validator then verifies capacity and hostile-faction connectivity.

## Three spatial contracts

Module placement distinguishes three kinds of space:

- **Tactical footprint:** integer cells and authored effects that become movement, stopping, cover, line-of-sight, and occupancy state in `MapData`.
- **Placement clearance:** rotation-aware cells reserved for entrances, machine service space, access lanes, and seams. A later same-layer footprint cannot intrude into them, and a new clearance cannot cover an existing same-layer footprint.
- **Visual envelope:** an optional calibrated `AABB` in local cell/world units. Same-layer envelope intersections reject the candidate, but the envelope never changes tactical state.

Ground, occupant, and overhead placement layers remain independent. A container can legally sit on paved ground, and future elevated pieces can cross ground space. Deliberate structural seams continue to use authored connection sockets; touching visual-envelope boundaries are accepted.

Container and machine-cluster envelopes cover the overhang that caused the Goal 2.2 clipping reports. More catalog assets should receive envelopes only after their useful assembly bounds are measured. Raw vendor bounds are not automatically promoted to gameplay or placement authority.

## Bounded alternatives

Parcel placement is transactional. The assembler clones the accepted prefix, tries a candidate template, and retains it only if every member passes all placement contracts. A failed candidate records its reason and the assembler tries another seeded choice. Each parcel has a fixed attempt limit and falls back to explicit open ground if no candidate is legal. This guarantees termination and makes degraded output visible rather than silently accepting a broken composition.

Seed 7 in the industrial identity is a regression fixture: one yard candidate is rejected because its machine envelope would intersect a neighboring container, then a valid alternative is selected without requiring the open-ground fallback.

## XCOM reference findings

The locally installed War of the Chosen SDK was inspected for design ideas, especially `XComParcelManager.uc`, `XComParcel.uc`, and `XComParcelEntrance.uc`. Its useful concepts are hierarchical plot/parcel selection, parcel size and facing metadata, entrance slots, objective eligibility, randomized input ordering, and bounded/exhaustive search for a valid arrangement.

FuseFire adopts the division of responsibility, not XCOM code or content. `EnvironmentLayoutPlan` is the macro plot, parcel dictionaries are the lots, Goal 2.2 definitions are the reusable pieces, and `MapData` remains the tactical authority.

## Map Editor

Launch from the repository root:

```powershell
godot_console --path . res://tools/map_editor.tscn
```

The layout selector now contains both authored Goal 2.2 fixtures and the three procedural identities. You can also launch a fixed seed directly:

```powershell
godot_console --path . res://tools/map_editor.tscn -- 2208 industrial_district
godot_console --path . res://tools/map_editor.tscn -- 7319 commercial_street
godot_console --path . res://tools/map_editor.tscn -- 11027 mixed_service
```

Procedural views show cyan road-plot boundaries and amber parcel boundaries above the tactical grid. The status line reports topology, road-tile and parcel counts, rejected candidates, fallback use, component count, and general map validity. Existing orbit, pan, zoom, seed controls, direct module selection, outline, framing, and transform scratchpad remain available.

For repeatable rendered evidence:

```powershell
godot_console --path . --resolution 1440x900 --script res://tests/coherent_layout_capture.gd -- C:/path/to/captures
```

## Verification

`coherent_layout_assembly_test.gd` protects:

- deterministic plan, placement, and tactical signatures;
- meaningful variation across three identities and four representative seeds;
- connected road graphs whose approaches reach map boundaries;
- assigned parcel templates and bounded search termination;
- clearance and visual-envelope conflict rejection;
- successful alternative selection after a real rejected candidate;
- tactical map validation and repaired deployment legality;
- shared procedural presentation and Map Editor plan diagnostics.

The capture helper renders one representative seed per identity for human inspection. Headless tests establish logic and scene behavior; they do not establish visual quality.

## Current limits

- The first road grammar produces one crossroad or T junction with straight boundary approaches. Curves, multiple intersections, blocks, and secondary streets remain future extensions.
- Parcels use a fixed ten-cell macro size and a compact authored template catalog. Building depth, roofs, full interiors, and multi-parcel structures are limited.
- Only known overhanging occupant modules have calibrated visual envelopes. Other modules still depend on authored template spacing and visual review.
- The current fallback is deliberate open ground. Future quality scoring should distinguish useful civic/open space from excessive low-density output.
- Mission requirements validate against the completed map. Goal 2.5 should reserve objective and extraction needs during planning.
- Procedural vertical districts are deferred; the authored `vertical_works` fixture continues to validate elevated module translation and traversal.
