# Environment Asset Calibration Laboratory

Goal 2.1 establishes a visual calibration workflow for the four retained Kenney packs. It does not assign tactical behavior to meshes. `MapData` remains the sole authority for occupied cells, movement, cover, line of sight, elevation and traversal.

## Launch and controls

Open `res://tools/asset_lab/asset_lab.tscn` in Godot and run the current scene (**F6**).

- The asset-family selector separates the catalog into City Industrial, City Roads, Factory and Modular Space groups. Search operates within the selected family. A leading `*` marks one of the 14 curated profiles.
- Right-drag orbits; the mouse wheel zooms; **F** frames the current model or assembly.
- Uniform scale never stretches one axis independently. Yaw rotates around Godot's up axis.
- Every Kenney asset initializes and resets to a developer-selected family scale: **9.0** for City Kit architecture and infrastructure, **5.0** for selected human-scale street furniture, and **1.0** for Factory Kit and Modular Space Kit assets authored at useful native dimensions.
- Floor center aligns the lowest mesh point and centers X/Z. Source origin preserves an authored modular pivot. Top center puts a thin road or floor surface at the requested height.
- Anchor X/Z use half-cell increments. The neighbor control exposes pitch and seam alignment.
- Yellow lines show complete imported hierarchy bounds. Red, green and blue lines show +X, +Y and +Z at the placement anchor.
- The MIRA reference is the actual runtime visual and measures approximately 1.60 world units tall after it initializes.
- **Copy current calibration JSON** copies the inspected visual values. It deliberately records `tactical_occupancy: not authored`.

The four assembly views exercise road and paving seams, a wall with a wide entrance, loading machinery, and Space Kit floor/wall alignment. They are calibration fixtures, not gameplay modules.

For repeatable measurements:

```powershell
godot_console --headless --path . --script res://tools/asset_lab/measure_catalog.gd -- res://tools/asset_lab/native_bounds.json
godot_console --headless --path . --script res://tests/asset_calibration_test.gd
```

`measure_catalog.gd` overwrites the explicitly supplied output path, so it is suitable for detecting an imported-model change. The checked-in JSON is the measured baseline for the curated subset.

## Calibration conventions

One tactical cell equals one Godot world unit. Imported scenes are Y-up and rotate around Y. The calibration tiers are visual starting points derived from rendered comparisons against the runtime MIRA; they are neither verified universal real-world scales nor finalized tactical footprints. Curated profiles record the visually inspected principal axis or facade direction; unreviewed models explicitly report that their orientation is unknown. A visual model may span many cells, but its `AABB` is only a presentation and clearance envelope. Open cranes, door openings and structural projections prove that an AABB cannot be converted automatically into solid occupancy.

The catalog applies these deterministic tiers to all 315 assets:

| Asset family | Count | Scale | Rationale |
| --- | ---: | ---: | --- |
| City Kit Industrial | 37 | 9.0 | Buildings, containers, chimneys, tanks, solar panels, water tower and windmills share the pack's miniature convention. |
| City Kit Roads infrastructure | 90 | 9.0 | Roads, paving, poles, road lights, signs, bridge pieces and traffic lights align with the City Kit convention. |
| City Kit Roads street furniture | 5 | 5.0 | Construction barrier, cone, fence, light and dumpster read at human scale beside a MIRA. |
| Factory Kit | 143 | 1.0 | Structural bays, doors and machinery are already authored in useful world-sized units; 9× or 10× makes them monumental. |
| Modular Space Kit | 40 | 1.0 | Four-unit rooms and walls already form a coherent native-scale construction grammar. |

Fit-to-envelope remains appropriate for a deliberately authored runtime prop reservation, such as the warehouse containers, but changing laboratory calibration does not rescale those existing warehouse assets.

Quarter-turns are the currently verified rotations. Arbitrary yaw remains inspectable, but its axis-aligned bounds grow conservatively and future module connectors should declare allowed rotations.

## Verified representative subset

| Family / asset | Native mesh bounds (X × Y × Z) | Calibration | Verified use |
| --- | ---: | --- | --- |
| Industrial `building-a` | 2.084 × 1.470 × 1.242 | 9×, floor center | Exterior massing reference; closed shell, not an enterable building |
| Industrial `shipping-container-a` | 0.373 × 0.348 × 0.823 | 9×, floor center | Cargo prop; long axis Z before rotation |
| Industrial chimneys | varies | 9×, floor center | Pack-scale industrial structures; intentionally remain in the City tier |
| Roads `road-straight` | 1.000 × 0.020 × 1.000 | 9×, top center | 9 × 9 visual road tile |
| Roads `road-side` | 1.000 × 0.020 × 1.310 | 9×, source origin | Road tile with asymmetric sidewalk overhang |
| Roads `tile-low` | 1.000 × 0.020 × 1.000 | 9×, top center | Matching 9 × 9 paving tile |
| Roads construction fence / dumpster | varies | 5×, floor center | Human-scale street furniture |
| Factory structural wall/window | 1.000 × 3.000 × 2.000 | 1×, source origin | 1-unit visual bay, 3-unit height |
| Factory wide doorway | 2.000 × 3.000 × 2.000 | 1×, source origin | 2-unit visual entrance bay at the same height |
| Factory `machine` | 1.200 × 1.300 × 1.500 | 1×, floor center | Standalone machinery |
| Factory `conveyor-long` | 2.000 × 0.400 × 1.000 | 1×, floor center | 2-unit visual pitch; preview uses a proportional stand |
| Factory `crane` | 1.926 × 3.553 × 3.680 | 1×, floor center | Loading-area prop with a strongly offset source pivot |
| Space `template-floor` | 4.000 × ~0 × 4.000 | 1×, source origin | 4-unit visual pitch |
| Space `template-wall` | 4.000 × 4.250 × 1.001 | 1×, source origin | Matching 4-unit wall bay |
| Space `corridor` | 4.000 × 4.250 × 4.000 | 1×, source origin | Enclosed room-scale section |

These dimensions come from Godot's imported mesh hierarchy, including descendant transforms. The catalog stores source path, pack-derived identifier, category, uniform scale, anchor convention and a compatibility note. The generated bounds baseline stores the exact measured values separately.

## Findings from assembly inspection

- Road assets remain internally coherent at 9×: three tiles meet on a 9-unit pitch, and the side-road's 1.31 native depth intentionally includes a sidewalk strip. Adjacent paving must account for the 11.79-unit scaled edge, not assume a square footprint.
- Factory structural pieces share dimensions and origins. Their wall/door seams remain exact at native scale and produce a three-unit wall height comparable to a MIRA.
- Factory machinery preserves its useful human/room proportions at native scale, but practical future modules still need authored spacing around cranes, conveyors and working faces.
- Space Kit remains internally coherent at a 4-unit pitch and 4.25-unit height. It is still a separate construction grammar rather than an automatic match for Factory pieces.
- City Kit Industrial buildings are closed exterior shells. Enlarging one produces convincing exterior massing but does not create an enterable building or tactical collision.
- The existing Industrial Warehouse remains unchanged: its fit-to-envelope placement is runtime presentation data and does not consume this laboratory default.

## Boundaries and Goal 2.2 requirements

The 301 unstarred assets remain browsable but unverified. Forward direction is visual and family-specific; filenames and AABBs do not prove entrances or connectors. Decorative details, openings and sparse machinery require authored tactical meaning.

Goal 2.2 should define its first real module records from the verified road/paving and Factory entrance assemblies. A module needs an authoritative cell footprint separate from its visual envelope, allowed quarter-turn rotations, explicit connection points, clearance, presentation placements and suitability tags. Door and road connectors should be authored; bounds should validate clearance and seams rather than generate gameplay state.
