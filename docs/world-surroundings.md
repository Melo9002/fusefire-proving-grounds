# World beyond the tactical area

Step 2 establishes ownership, using ordinary editable Godot Node3D groups. It does not add scenery or another generator.

## The three areas

```text
BattleLevel / GeneratedTerrain
    Selected plot
        Tactical
            Internal approach/lane/sidewalk visuals
            Accepted parcel instances, added when the battle is built
        Peripheral
            Extended ground, continuing road and nearby container stacks
        Distant
            Background workshops or the site's landmark
```

| Area | Purpose | Gameplay authority |
| --- | --- | --- |
| Tactical | The playable battlefield and its presented parcels. | MapData owns cells, movement, sight, shots and cover; GridManager owns unit occupancy. Existing parcel compilation and plot/mission contracts still supply gameplay data. |
| Peripheral | Nearby visual continuation across the battlefield edge. | No new grid cells, tactical obstacles, targets, deployment or objectives. Hazard markers inside this group are ignored by battle discovery. |
| Distant | Background structures and landmarks that establish the setting/horizon. | The same scenery-only restriction. Current placeholder models are not yet simplified into an optimized skyline. |

These groups describe **ownership**, not three sharply separated volumes. Extended ground and continuing roads can cross the tactical footprint. Moving a visual into Tactical does not compile it into gameplay; gameplay objects still belong to the existing editable parcels. No new role assignment, boundary export or registration step is introduced.

## Where to edit

The five scenes below cover the six normal site layouts:

- `art/environments/authored/plots/depot_loading_crossing.tscn`
- `art/environments/authored/plots/depot_service_spine.tscn`
- `art/environments/authored/plots/freight_yard_site.tscn` (shared by both apron arrangements)
- `art/environments/authored/plots/fleet_station_north.tscn`
- `art/environments/authored/plots/fleet_station_south.tscn`

Each contains Tactical, Peripheral and Distant as ordinary scene children. The plot owns their saved scenery; parcels remain separately editable scenes. Generation 2 places the accepted parcels under Tactical at runtime. The plot applies tile scale once; children use parcel coordinates. Local parcel tests and historical fixture plot scenes without these nodes receive empty groups through the same presenter, without migrating their saved content.

The groups also carry persistent Godot group names `tactical_area`, `peripheral_scenery` and `distant_scenery`. Discovery must not treat scenery as gameplay merely because a reused component contains tactical metadata or a hazard marker. Current scenery contains no PhysicsBody3D nodes. New collision-bearing scenery or actors would require review; these node labels do not automatically strip arbitrary physics bodies or scripts.

Global lighting/fog remains owned by the battle's explicit WorldEnvironment. No additional light, sky, streaming, LOD or backdrop framework is added. Plot/content revisions and replay schemas are unchanged because this step changes presentation ownership, not accepted tactical choices or scene positions.

## Validation and remaining work

`tests/world_area_ownership_test.gd` checks all three sites and seeds 16/17: editable groups, parcel world transforms at presentation scales 1 and 2, bounded grid, unchanged manifest reconstruction, scenery without physics bodies, and ignored scenery hazards alongside working Tactical hazards. Generation/compilation uses the existing unit-tile contract; the scale-2 case tests presentation separately, not new arbitrary-scale tactical compilation support.

The [step-1 inspection](quality/surroundings-inspection-2026-11-15.md) remains the visual backlog. Next is one Service Depot continuity proof: connect its edges to the setting using these groups. Physical boundary readability, horizon composition, actual action/replay camera angles and performance budgets remain later tasks. Grouping alone does not solve those visual problems.

### Step-2 evidence — 2026-11-15

- Ownership regression: zero failures across six current layouts at two presentation scales, plus the live hazard isolation check.
- Ironclad smoke: **11 passed, 0 failed, 0 skipped** (`artifacts/test-results/20261115-192133-smoke`). No full-suite run was needed for this bounded change.
- Complete saved replays: Freight 69/69, Fleet 47/47 and local ambulance parcel 53/53 actions verified to matching results. Camera handoff, tactical conditions, the garage fixture and garage camera-aperture checks also passed.
- Fresh rendered capture: **30 views, zero failures**, under `artifacts/surroundings-areas/`. Comparison against the step-1 images showed mean absolute RGB differences below 0.001 out of 255 for every view. A representative reverse view was inspected directly; this supports preserved appearance, not a claim that the step-1 visual problems are fixed.
- The initial regression setup attempted tactical compilation at tile scale 2, which is outside the current unit-tile authoring contract, then dereferenced a failed presentation. That was a test setup defect; the final test explicitly exercises presentation scale separately and safely handles failed presentation. No compiler assertions or existing gameplay rules were relaxed.
- Sandbox certificate/log-store diagnostics remain environmental. Captures and final focused runs had no script/parse errors.
