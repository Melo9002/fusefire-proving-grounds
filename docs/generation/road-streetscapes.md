# Road Geometry and Streetscapes

FuseFire's coherent layouts use a shared street cross-section that joins the ten-cell road grammar to road-facing parcels. The system combines exact derived surfaces with reviewed Kenney kit assets: generated boxes provide seamless roadbed, sidewalk, curb, and marking geometry; the semantic asset catalog supplies calibrated signals, signs, lights, poles, barriers, dumpsters, containers, fences, and parcel equipment.

## Street cross-section

Each straight street occupies a 10 × 10 tactical module:

| Region | Width | Presentation | Tactical meaning |
| --- | ---: | --- | --- |
| Carriageway | 6 cells | dark asphalt with center markings | ordinary open ground |
| Left sidewalk | 2 cells | raised concrete | ordinary open ground |
| Right sidewalk | 2 cells | raised concrete | ordinary open ground |
| Curbs | 0.12 units | raised seam at both road edges | presentation only |

Crossroads and T-junctions use the same widths. Their asphalt arms meet at exact centers and their sidewalk corner islands leave every active road approach open. Presentation surfaces sit slightly above the preview base plane to prevent z-fighting. Their height and material never create movement, collision, cover, or line of sight.

The original City Kit Roads meshes remain in the asset library as inspected source material. The coherent generator uses derived geometry because stretching a complete one-meter road tile across a ten-cell macro tile could not preserve a useful carriageway, sidewalk width, or exact intersection seam. The legacy 20 × 20 authored road corner still uses its imported mesh and is not part of the procedural grammar.

## Frontage and placement rules

Road furniture uses explicit rotation-aware sidewalk slots:

- The outer sidewalk lane carries poles, lights, signals, signs, and occasional barriers.
- The inner sidewalk lane remains clear for pedestrians and tactical traversal.
- Straight-segment fixtures avoid the central frontage band used by entrances.
- Each intersection receives one control asset per active approach. T-junctions therefore receive three rather than four.
- A tactical obstacle appears only when deliberately requested by an environment rule. Construction barriers retain their explicit vaultable low-cover contract; ordinary furniture remains visual-only.

Road modules occupy the ground placement layer. Furniture and tactical obstacles use the occupant layer, so a prop can stand on road or sidewalk presentation without deleting the ground underneath it. Parcel composition remains independent and cannot infer gameplay rules from mesh overlap.

## Environment identities

| Identity | Intersection control | Edge fixtures | Tactical detail |
| --- | --- | --- | --- |
| Industrial district | reviewed stop signs | mostly electricity poles with periodic road lights | sparse construction barriers on the opposite outer sidewalk |
| Commercial street | reviewed traffic lights | regular curved or square road lights | sidewalks remain uncluttered |
| Mixed service | traffic lights at crossroads, stop signs at T-junctions | alternating lights and electricity poles | very sparse construction barriers |

The visual variants are selected deterministically through the existing module placement variant. All references use stable semantic asset IDs and the Asset Lab's saved calibration at presentation time. No new procedural approvals or calibration changes are made by street generation.

Parcel templates continue to add context-specific kit assets: dumpsters near service alleys, containers and machinery in loading areas, construction fencing around yards, and complete reviewed structures facing the street. Expanded 60 × 50 previews reserve several large parcels. Industrial and mixed-service layouts select from calibrated per-building profiles whose working faces are normalized toward the sidewalk; commercial blocks use complete authored shop buildings. Landlocked parcels remain undeveloped ground instead of becoming disconnected paving slabs with isolated clutter. These objects belong to functional parcels rather than a random map-wide clutter pass.

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
```

Use **Inspect road seam** for a straight connection or select an intersection in the map. Right-drag orbits, middle-drag pans, and the wheel zooms. The rendered capture fixture records overhead and close intersection evidence for all three representative environments:

```powershell
godot_console --path . --resolution 1440x900 --script res://tests/coherent_layout_capture.gd -- artifacts/streetscape-review
```

`coherent_road_streetscape_test.gd` protects exact cross-section widths, intersection pavement and corner islands, rotation-aware kit placement, clear inner sidewalk lanes, explicit barrier behavior, tactical authority, and presenter output across three identities and nine seeded maps.

## Current limits

- The procedural grammar has straight approaches, crossroads, and T-junctions. Curves, medians, crosswalks, parking lanes, and secondary road widths need explicit profiles before use.
- The lane markings are a readable development baseline rather than a traffic simulation.
- Fixture cadence is environment-specific but does not yet respond to building use, pedestrian demand, or power-grid continuity.
- Imported traffic furniture still depends on its developer-reviewed calibration; the street system never rewrites those values.
