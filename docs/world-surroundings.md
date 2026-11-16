# World beyond the tactical area

Roadmap 03 uses three ordinary editable scene groups. The proven Depot approach now also covers Freight Yard and Fleet Station. There is still one Generation 2 pipeline; surroundings are fixed plot scenery, not another procedural system.

| Layer | What belongs here | Gameplay |
| --- | --- | --- |
| Tactical | The playable 40 × 40 area, internal lanes/sidewalks, yellow boundary and runtime parcel instances. | MapData owns terrain, movement, shots and cover; GridManager owns actor occupancy. Parcels supply compiled tactical content. |
| Peripheral | Continuous ground, extended roads, neighboring yards, parked vehicles and boundary cues. | Visual only: no extra cells, actors, objectives, navigation or physics bodies. |
| Distant | Six muted, low-detail building districts establishing the horizon. | Visual only; no lights or shadows. |

These are ownership groups, not three non-overlapping boxes. A continuing road or ground surface can cross the playable footprint. Moving an object into Tactical alone does not compile gameplay: gameplay content still belongs to the existing parcel workflow. No new roles, hull-fitting, boundary export or scenery registration is required.

## Where to edit

Open the plot scene in Godot. Its Tactical, Peripheral and Distant children are saved and editable. Generation adds accepted parcels under Tactical at runtime and applies tile scale once.

| Site / layout | Plot scene | Near scenery |
| --- | --- | --- |
| Depot, seed 16 | `art/environments/authored/plots/depot_loading_crossing.tscn` | `depot_neighboring_yards.tscn` |
| Depot, seed 17 | `art/environments/authored/plots/depot_service_spine.tscn` | `depot_neighboring_yards.tscn` |
| Freight, both apron arrangements | `art/environments/authored/plots/freight_yard_site.tscn` | `freight_neighboring_yards.tscn` |
| Fleet, north frontage / seed 16 | `art/environments/authored/plots/fleet_station_north.tscn` | `fleet_neighboring_court.tscn` |
| Fleet, south frontage / seed 17 | `art/environments/authored/plots/fleet_station_south.tscn` | `fleet_neighboring_court.tscn` |

Near-scene filenames in the last column are in the same plots directory. Freight keeps container stacks and delivery vehicles; Fleet has service buildings and overflow parking. They use existing reusable asset scenes. The yards connect to 640-unit ground and three adjoining 85-unit road strips. Their different parcel arrangements/frontages remain intact.

Shared editable pieces, also in that directory:

- `depot_playable_boundary.tscn`: the exact yellow dashed 40 × 40 limit, reused by all three sites.
- `depot_edge_cues_crossing.tscn`: corner cones, short fence runs and BATTLE LIMIT road labels. Freight reuses it directly; Fleet overrides the two label positions to match its north/south road. Depot spine uses `depot_edge_cues_spine.tscn`.
- `depot_distant_blocks.tscn`: the same inexpensive six-district industrial backdrop, reused by all three sites. Its filename records its origin; it is an ordinary shared scene, not a Depot generator dependency.

Editing a shared piece affects every instance. To change one site's arrangement, edit its plot instance/overrides or its own near scene. Lighting/fog stays with the owning battle's WorldEnvironment, configured in `systems/generation2/authored_battlefield_layout.gd`.

## Keep edits simple and safe

1. Keep tall nearby scenery outside playable cells and continuing roads. Match ground height and existing calibrated asset scale.
2. Retain the yellow limit even where fences or curbs suggest a boundary. Roads can continue visually without becoming walkable off-map.
3. Reused visual scenery can contain inert tactical metadata, but it must stay under Peripheral/Distant and outside compilation. Current scenes contain no physics bodies or navigation regions. Those group names do not strip arbitrary collision bodies, scripts or actors added later.
4. Nearby visual wrappers use the existing camera occlusion helper; their camera-only bounds rebuild from their meshes. No tactical boundary fitting is needed for scenery.
5. Meaningful saved content changes require the existing plot revision policy so replay reconstruction does not silently change. Freight and Fleet plots are revision 2 after this rollout; Depot remains revision 1. Old Freight/Fleet revision-1 recordings reject explicitly. Recordings do not bundle historical plot art.

## Review and cost

Use seeds **16 and 17** in Match Setup to inspect both layouts of each site. Review normal entry, opposing overview, low cardinal, high and wide views. The rendered capture tool saves exact transforms/FOVs in `views.json`:

```powershell
godot_console --path . --script res://tools/environment_authoring/current_surroundings_capture.gd -- artifacts/surroundings-review
godot_console --path . --script res://tools/environment_authoring/surroundings_cost.gd -- artifacts/surroundings-cost
```

Both tools now cover all three sites. Keep the benchmark window visible and avoid other GPU work while measuring. It compares the same static battle/camera with Peripheral and Distant visible/hidden; it does not benchmark AI turns or unload hidden resources.

Content budget per plot: **160 scenery meshes, 25,000 authored triangles, no additional lights**. The shared distant backdrop keeps its separate **60 meshes / 6,500 triangles / no shadows** cap. Current totals: Depot 132 meshes / 19,004–19,964 triangles; Freight 142 / 20,592; Fleet 150 / 21,496.

The development-machine review thresholds remain added median GPU ≤1 ms, render CPU ≤0.5 ms, p95 frame interval ≤2 ms and draw calls ≤80 for the fixed benchmark views. These are review thresholds, not universal hardware guarantees or whole-game frame budgets. Simplify expensive scenery before considering streaming or LOD.

Loading always covers matches, editor tests and replay transitions through the first rendered frame, with initialization errors exposed and return controls preserved. It does not make construction threaded or guarantee recovery from out-of-memory crashes.

## Checks and milestone record

Current checks protect all six layouts: continuous roads/ground, scenery budgets, readable boundary cues, camera behavior, tactical edge isolation, mission placement and matching scenery/atmosphere after replay reconstruction. Headless checks do not establish visual correctness; the closing review also includes rendered captures and real graphics measurements.

See the [closing review](quality/world-surroundings-close-2026-11-15.md) for final results, reproduction and remaining limits. This closes the prototype world-surroundings milestone for the current curated sites; more varied art and arbitrary future maps remain normal content work.

Earlier evidence, retained as dated history rather than today's instructions:

- [Initial inspection](quality/surroundings-inspection-2026-11-15.md)
- [Depot continuity](quality/depot-continuity-2026-11-15.md), [boundary](quality/depot-boundary-readability-2026-11-15.md), [distant view](quality/depot-distant-view-2026-11-15.md), [camera review](quality/depot-camera-review-2026-11-15.md)
- [Tactical isolation and replay](quality/world-tactical-isolation-2026-11-15.md)
- [Initial cost measurement and loading](quality/surroundings-cost-2026-11-15.md)
