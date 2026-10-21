# Road Geometry and Streetscapes

FuseFire's coherent layouts use a shared street cross-section that joins the ten-cell road grammar to road-facing parcels. Reviewed City Kit Roads meshes own the normal visible straight, crossroad, and T-junction surfaces. `RoadPresentationMode.ASSET_FIRST` is the normal and generated-terrain path. Exact derived roadbed, sidewalk, curb, and marking geometry is available only through `RoadPresentationMode.DERIVED_DIAGNOSTIC`; it is not drawn underneath imported streets. The semantic catalog also supplies calibrated signals, signs, lights, poles, barriers, dumpsters, containers, fences, and parcel equipment.

## Street cross-section

Each straight street occupies a 10 × 10 tactical module:

| Region | Width | Presentation | Tactical meaning |
| --- | ---: | --- | --- |
| Carriageway | 6 cells | dark asphalt with center markings | ordinary open ground |
| Left sidewalk | 2 cells | raised concrete | ordinary open ground |
| Right sidewalk | 2 cells | raised concrete | ordinary open ground |
| Curbs | 0.12 units | raised seam at both road edges | presentation only |

Crossroads and T-junctions use the same widths. Their asphalt arms meet at exact centers and their sidewalk corner islands leave every active road approach open. Imported presentation surfaces sit slightly above the preview base plane to prevent z-fighting. The diagnostic cross-section's height and material never create movement, collision, cover, or line of sight.

The calibrated kit road tile occupies 5 × 5 world units and already has the desired 3:1:1 carriageway-to-sidewalk ratio. Each ten-cell module applies an authored 2× horizontal presentation adapter, producing the exact 6 + 2 + 2 cross-section without changing the saved calibration. Matching `road-straight`, `road-crossroad`, and `road-intersection` meshes are selected through semantic approval. `road-curve` and `tile-low` use the same adapter in their authored modules. This non-uniform module transform is visual only and leaves the source GLB, calibration, and tactical cells unchanged.

## Source orientation normalization

Road geometry is normalized once in each module's visual contract, before ordinary module placement rotation. The imported mesh openings were derived from the bounded gaps in the highest horizontal pavement triangles rather than from square AABBs or filenames:

| Module | Imported physical openings | Asset-local correction | Authored module openings |
| --- | --- | ---: | --- |
| `road_straight` | `-X`, `+X` | 1 quarter turn | `-Z`, `+Z` |
| `road_intersection_t` | `-X`, `+X`, `+Z` | 0 | `-X`, `+X`, `+Z` |
| `road_crossroad` | `-X`, `+X`, `-Z`, `+Z` | 0 | all four directions |
| `road_corner` | `-X`, `+Z` | 2 quarter turns | `-Z`, `+X` |

`yaw_quarters` expresses only this source-to-module correction. `EnvironmentModulePlacement.rotation` then rotates the normalized module through the canonical spatial transform. Asset calibration remains unchanged, and road meshes do not define tactical traversal.

## Frontage and placement rules

Road furniture uses explicit rotation-aware sidewalk slots:

- The outer sidewalk lane carries poles, lights, signals, signs, and occasional barriers.
- The inner sidewalk lane remains clear for pedestrians and tactical traversal.
- Straight-segment fixtures avoid the central frontage band used by entrances.
- Curved and square streetlight heads face model-local `-Z`; their authored slot yaw points that face inward over the carriageway on either side and rotates with the road.
- Each intersection receives one control asset per active approach. T-junctions therefore receive three rather than four.
- A tactical obstacle appears only when deliberately requested by an environment rule. Construction barriers retain their explicit vaultable low-cover contract; ordinary furniture remains visual-only.

Road modules occupy the ground placement layer. Furniture and tactical obstacles use the occupant layer, so a prop can stand on road or sidewalk presentation without deleting the ground underneath it. Parcel composition remains independent and cannot infer gameplay rules from mesh overlap.

The bounded `asset_first_frontage` engineering fixture certifies one complete street-to-building relationship. Two imported `road-straight` tiles meet end-to-end; two imported `tile-low` surfaces meet their eastern sidewalks at the same X edge and the same Y `0.11` surface top. The paving ends exactly at the calibrated bounds of `building-i`. The building is quarter-turned so its reviewed working face points west toward the street, while its three-cell exterior apron remains unobstructed. Two reviewed lamps occupy outer sidewalk cells outside the central access band. Their model-local `-Z` heads face the carriageway, and their mounting feet are raised to the imported pavement top rather than buried at ground Y `0.0`.

## Environment identities

| Identity | Intersection control | Edge fixtures | Tactical detail |
| --- | --- | --- | --- |
| Industrial district | reviewed stop signs | mostly electricity poles with periodic road lights | sparse construction barriers on the opposite outer sidewalk |
| Commercial street | reviewed traffic lights | regular curved or square road lights | sidewalks remain uncluttered |
| Mixed service | traffic lights at crossroads, stop signs at T-junctions | alternating lights and electricity poles | very sparse construction barriers |

The visual variants are selected deterministically through the existing module placement variant. All references use stable semantic asset IDs and the Asset Lab's saved calibration at presentation time. Five road/paving meshes gained explicit procedural approval only after receiving these module contracts; no calibration value changed.

Parcel templates continue to add context-specific kit assets: dumpsters near service alleys, containers and machinery in loading areas, construction fencing around yards, and complete reviewed structures facing the street. Expanded 60 × 50 previews reserve several large parcels. Industrial and mixed-service layouts select from calibrated per-building profiles whose working faces are normalized toward the sidewalk; commercial blocks select the smaller complete shells explicitly confirmed for that context. Commercial small parcels use paved, lit forecourts rather than industrial container staging. Landlocked parcels remain designated district buffers instead of becoming disconnected paving slabs with isolated clutter. These objects belong to functional parcels rather than a random map-wide clutter pass.

## Adding a street detail

1. Confirm the asset identity, facing, calibration, and procedural approval in the semantic catalog.
2. Wrap it in an `EnvironmentModuleDefinition` with the narrowest tactical role.
3. Choose a cross-section slot that leaves the carriageway, inner sidewalk lane, and entrance band usable.
4. Add an environment-specific deterministic rule in `CoherentEnvironmentAssembler`.
5. If it affects gameplay, author cell effects explicitly; visual bounds never become tactical occupancy.
6. Add a fixed-seed assertion and inspect overhead plus close-up rendered views.

## Inspection and verification

Launch the Map Editor directly:

```powershell
godot_console --path . res://tools/map_editor.tscn -- 2208 industrial_district
godot_console --path . res://tools/map_editor.tscn -- 7319 commercial_street
godot_console --path . res://tools/map_editor.tscn -- 11027 mixed_service
godot_console --path . res://tools/map_editor.tscn -- 2303 asset_first_frontage
```

The last command opens the Task 2.3 fixture and enables the editor's engineering-fixture view automatically. The shell is intentionally exterior-only; the white paving is a walkable frontage forecourt, not a playable building interior.

Use **Inspect road seam** for a straight connection or select an intersection in the map. Right-drag orbits, middle-drag pans, and the wheel zooms. The rendered capture fixture records overhead and close intersection evidence for all three representative environments:

```powershell
godot_console --path . --resolution 1440x900 --script res://tests/coherent_layout_capture.gd -- artifacts/streetscape-review
```

`coherent_geometry_contract_test.gd` extracts openings from actual imported triangle surfaces, compares their final rendered directions with connectors through all supported quarter turns, and verifies a connected straight/cross/curve fixture. `coherent_road_streetscape_test.gd` protects exact cross-section widths, one imported kit surface per road tile, absence of duplicate normal surfaces, explicit diagnostic reconstruction, the 2× horizontal adapter, inward-facing lights, intersection pavement and corner islands, clear inner sidewalk lanes, explicit barrier behavior, tactical authority, and presenter output across three identities and nine seeded maps.

`coherent_asset_first_frontage_test.gd` protects the bounded fixture's physical seams, imported asset ownership, building and lamp facing, lamp mounting height, frontage clearance, sealed tactical shell, and street-to-apron path. `coherent_asset_first_frontage_capture.gd` records five clean views, three engineering views, and a four-rotation certification matrix. Green marks the access route, cyan the road/paving seams, red the straight-road join, gold the frontage apron, and magenta the lamp envelopes.

The [Task 2.4 certification record](../architecture/reviews/2026-10-21-task-2.4-asset-first-street-certification.md) pins the fixture's asset and catalog revisions, exercises the complete composition at all four quarter turns, and records objective checks plus clean inspection evidence. Its current status is **certification candidate** because final visual approval belongs to the project owner.

## Current limits

- The procedural grammar emits straight approaches, crossroads, and T-junctions. The curve module has a verified visual/connector contract and is usable by authored layouts, but coherent procedural plans do not select it yet. Medians, crosswalks, parking lanes, and secondary road widths need explicit profiles before use.
- Every supported imported road surface resolves to the same world Y `0.11` pavement top. The straight uses a top-center anchor at offset `0.11`; T, cross, and curve use their inherited floor anchor at offset `0.01`, compensating for their 0.10-unit mesh height. A presented-bounds regression protects the final geometric result rather than requiring misleadingly identical metadata offsets. Kit curb boundaries still overlap or terminate abruptly at some curve-to-square joins and require a Phase 2 certified transition policy.
- The lane markings are a readable development baseline rather than a traffic simulation.
- Fixture cadence is environment-specific but does not yet respond to building use, pedestrian demand, or power-grid continuity.
- Imported traffic furniture still depends on its developer-reviewed calibration; the street system never rewrites those values.
- The certified frontage is one authored straight-street composition. It does not certify curve-to-parcel transitions, driveways, crosswalks, or a generalized parcel relationship solver.
