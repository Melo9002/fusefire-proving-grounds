# Environment Asset Calibration Laboratory

Goal 2.1 establishes a visual calibration workflow for the four retained Kenney packs. It does not assign tactical behavior to meshes. `MapData` remains the sole authority for occupied cells, movement, cover, line of sight, elevation and traversal.

## Launch and controls

Open `res://tools/asset_lab/asset_lab.tscn` in Godot and run the current scene (**F6**).

- Search browses all 315 GLBs. A leading `*` marks one of the 14 curated profiles.
- Right-drag orbits; the mouse wheel zooms; **F** frames the current model or assembly.
- Uniform scale never stretches one axis independently. Yaw rotates around Godot's up axis.
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

One tactical cell equals one Godot world unit. Imported scenes are Y-up and rotate around Y. Curated profiles record the visually inspected principal axis or facade direction; unreviewed models explicitly report that their orientation is unknown. A visual model may span many cells, but its `AABB` is only a presentation and clearance envelope. Open cranes, door openings and structural projections prove that an AABB cannot be converted automatically into solid occupancy.

Connected families use one fixed uniform scale and normally retain their source origin. Standalone props can use floor-center placement. Fit-to-envelope remains appropriate for a deliberately authored prop reservation, such as the warehouse containers, but it must not be used independently on pieces that need matching seams.

Quarter-turns are the currently verified rotations. Arbitrary yaw remains inspectable, but its axis-aligned bounds grow conservatively and future module connectors should declare allowed rotations.

## Verified representative subset

| Family / asset | Native mesh bounds (X × Y × Z) | Calibration | Verified use |
| --- | ---: | --- | --- |
| Industrial `building-a` | 2.084 × 1.470 × 1.242 | 5.5×, floor center | Exterior massing reference; closed shell, not an enterable building |
| Industrial `shipping-container-a` | 0.373 × 0.348 × 0.823 | 5.5×, floor center | Cargo prop; long axis Z before rotation |
| Roads `road-straight` | 1.000 × 0.020 × 1.000 | 6×, top center | 6 × 6 road tile |
| Roads `road-side` | 1.000 × 0.020 × 1.310 | 6×, source origin | Road tile with asymmetric sidewalk overhang |
| Roads `tile-low` | 1.000 × 0.020 × 1.000 | 6×, top center | Matching 6 × 6 paving tile |
| Factory structural wall/window | 1.000 × 3.000 × 2.000 | 1.5×, source origin | 1.5-unit bay, 4.5-unit height |
| Factory wide doorway | 2.000 × 3.000 × 2.000 | 1.5×, source origin | 3-unit entrance bay at the same height |
| Factory `machine` | 1.200 × 1.300 × 1.500 | 1×, floor center | Standalone machinery |
| Factory `conveyor-long` | 2.000 × 0.400 × 1.000 | 1×, floor center | 2-unit machinery pitch; demo uses a 0.4-unit stand |
| Factory `crane` | 1.926 × 3.553 × 3.680 | 1×, floor center | Loading-area prop with a strongly offset source pivot |
| Space `template-floor` | 4.000 × ~0 × 4.000 | 1×, source origin | 4-unit modular pitch |
| Space `template-wall` | 4.000 × 4.250 × 1.001 | 1×, source origin | Matching 4-unit wall bay |
| Space `corridor` | 4.000 × 4.250 × 4.000 | 1×, source origin | Enclosed room-scale section |

These dimensions come from Godot's imported mesh hierarchy, including descendant transforms. The catalog stores source path, pack-derived identifier, category, uniform scale, anchor convention and a compatibility note. The generated bounds baseline stores the exact measured values separately.

## Findings from assembly inspection

- Road assets are internally coherent at 6×: three tiles meet on a 6-unit pitch, and the side-road's 1.31 native depth intentionally includes a sidewalk strip. Adjacent paving must account for the 7.86-unit scaled edge, not assume a square footprint.
- Factory structural pieces share dimensions and origins. At native scale the doorway is cramped relative to the 1.6-unit MIRA; a shared 1.5× scale gives a 4.5-unit storey and preserves wall/door seams.
- Factory machinery reads well at native scale, so it should not inherit the structural family's 1.5× scale. Pack identity alone is insufficient as a scale rule.
- Space Kit uses a coherent 4-unit pitch and 4.25-unit height. It is materially taller and wider than the calibrated Factory family and should remain a separate construction grammar.
- City Kit Industrial buildings are closed exterior shells. Enlarging one produces convincing exterior massing but does not create an enterable building or tactical collision.
- The warehouse's 5.5× container calibration remains visually credible and is intentionally independent from native-scale Factory machinery.

## Boundaries and Goal 2.2 requirements

The 301 unstarred assets remain browsable but unverified. Forward direction is visual and family-specific; filenames and AABBs do not prove entrances or connectors. Decorative details, openings and sparse machinery require authored tactical meaning.

Goal 2.2 should define its first real module records from the verified road/paving and Factory entrance assemblies. A module needs an authoritative cell footprint separate from its visual envelope, allowed quarter-turn rotations, explicit connection points, clearance, presentation placements and suitability tags. Door and road connectors should be authored; bounds should validate clearance and seams rather than generate gameplay state.
