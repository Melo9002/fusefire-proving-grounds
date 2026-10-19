# Environment Asset Calibration Laboratory

Goal 2.1 establishes a visual calibration workflow for the four retained Kenney packs. It does not assign tactical behavior to meshes. `MapData` remains the sole authority for occupied cells, movement, cover, line of sight, elevation and traversal.

Calibration and semantic interpretation are deliberately separate. The same laboratory now edits confirmed meaning in `asset_semantics.json`; see [Semantic Asset Catalog](semantic-asset-catalog.md). A reviewed scale does not imply that an asset is a complete building, a compatible module or approved for procedural use.

## Launch and controls

Open `res://tools/asset_lab/asset_lab.tscn` in Godot and run the current scene (**F6**).

- The asset-family selector separates the catalog into City Industrial, City Roads, Factory and Modular Space groups. Search operates within the selected family. `✓` marks confirmed metadata, `?` an unknown identity, `!` a known identity with scoped review flags, and `·` a catalog classification with no flagged fields.
- The semantic-category selector groups all 315 assets by their likely role (buildings, roads, conveyors, doors, pipes, screens, and so on) using pack naming, geometry, and rendered family evidence. It makes no scale or gameplay claim. `factory_kit/oopi` is retained as a non-environment character reference, with only its local facing still flagged for review.
- The interpretation selector filters confirmed, catalog-classified, unresolved, and identity-unknown assets. **Next unresolved semantic asset** advances inside the active family, category, and search batch.
- The review selector shows all, reviewed, or unreviewed assets. **Next unreviewed asset** advances within the active family, semantic category, and search.
- Right-drag orbits, middle-drag pans, and the mouse wheel zooms. **F** frames the model; **1**, **3**, and **7** select front, side, and top views. **Q/E** rotate an individual asset by 90 degrees. The same actions are available as visible buttons.
- Uniform scale never stretches one axis independently. Yaw rotates around Godot's up axis.
- The information panel reports the semantic calibration category and active source: `default`, `category`, or `asset override`.
- Floor center aligns the lowest mesh point and centers X/Z. Source origin preserves an authored modular pivot. Top center puts a thin road or floor surface at the requested height.
- Anchor X/Z use half-cell increments. The neighbor control exposes pitch and seam alignment.
- Yellow lines show complete imported hierarchy bounds. Red, green and blue lines show +X, +Y and +Z at the placement anchor.
- The MIRA reference uses the actual runtime visual, uniformly normalized inside the Lab to the developer-selected **1.60 m** reference height. This comparison-only transform does not modify the character scene or gameplay scale.
- The measured panel reports native and calibrated dimensions. Suggested footprint X/Z is planning metadata for future modules; it never changes tactical cells.
- **Copy current calibration JSON** copies scale, orientation, anchors, measured dimensions, classification, planning footprint, notes, review state, and source. It deliberately records `tactical_occupancy: not authored`.

## Saving calibration work

Persistent developer choices live in the human-readable project file `res://tools/asset_lab/asset_calibrations.json`. The laboratory writes only this file through explicit controls; original GLBs, native bounds, gameplay geometry and `MapData` are untouched.

1. Select an asset and adjust scale, yaw, anchor and offsets while comparing it with the runtime MIRA and one-unit grid.
2. Choose a human-verified classification, enter a suggested planning footprint when useful, and record orientation, intended combinations, clearance, or scale evidence in the notes box.
3. The status line changes to **UNSAVED CHANGES** when the viewport or metadata differs from the resolved saved values.
4. **Save calibration** records the visual properties, metadata, and current measured dimensions for that asset. **Ctrl+S** performs the same action.
5. Toggle **Reviewed** only when the record is trustworthy. Enabling it also saves the current calibration so a reviewed flag can never point only at an inherited preset or unsaved viewport state. Then use **Next unreviewed asset**.
6. **Reset to inherited preset** removes the selected asset override and restores its category or general default. It does not erase review state.
7. Edit **Category preset scale** and explicitly save it to update every asset in the category that lacks an individual override.
8. **Reload saved calibrations** discards unsaved viewport edits and rereads the project file.

The general fallback is currently 1.0. Resolution is always:

`asset override > category preset > general fallback`

The current category values are developer-selected visual calibration baselines. They provide complete scale coverage for the catalog, while individual overrides preserve exceptions. The Reviewed flag records that the developer accepted the asset's currently resolved visual calibration, whether inherited or overridden; it does not invent orientation, footprint, or tactical approval.

The four assembly views exercise road and paving seams, a wall with a wide entrance, loading machinery, and Space Kit floor/wall alignment. They are calibration fixtures, not gameplay modules.

For repeatable measurements:

```powershell
godot_console --headless --path . --script res://tools/asset_lab/measure_catalog.gd -- res://tools/asset_lab/native_bounds.json
godot_console --headless --path . --script res://tests/asset_calibration_test.gd
```

`measure_catalog.gd` overwrites the explicitly supplied output path, so it is suitable for detecting an imported-model change. The checked-in JSON contains measured native bounds for all 315 catalog assets.

## Calibration conventions

One tactical cell equals one Godot world unit. Imported scenes are Y-up and rotate around Y. The inherited calibration tiers are provisional visual starting points; they are neither verified universal real-world scales nor finalized tactical footprints. Curated profiles record earlier principal-axis or facade observations, while the saved per-asset record is the place for current human verification. A visual model may span many cells, but its `AABB` is only a presentation and clearance envelope. Open cranes, door openings and structural projections prove that an AABB cannot be converted automatically into solid occupancy.

The catalog currently resolves these deterministic baselines across all 315 assets:

| Calibration category | Scale | Rationale |
| --- | ---: | ---: | --- |
| Buildings | 10.0 | Developer-selected category baseline. |
| Shipping containers | 8.0 | Category baseline; all three current container records override this to 5.0. |
| Chimneys, tanks and industrial remainder | 5.0 | Human-reviewed baseline; individual landmarks may retain overrides. |
| Solar panels | 10.0 | Category baseline; the five inspected solar assets currently override this to 5.0. |
| Electricity infrastructure | 10.0 | Developer-selected category baseline. |
| Road lights | 5.0 | Human-reviewed street-fixture baseline. |
| Roads/paving and signs/signals | 5.0 | Shared City Kit road baseline. |
| Construction fences and dumpsters | 5.0 | Read as human-scale street furniture. |
| Other construction equipment | 5.0 | Shared construction-prop baseline. |
| Factory Kit | 1.5 | Enlarged from native size so a 1.60 m MIRA has comfortable doorway headroom while compatible pieces retain one shared scale. |
| Modular Space Kit | 1.0 | Native-size baseline retained as a separate construction family. |
| Unknown assets | fallback 1.0 | Safe fallback for future or uncategorized catalog entries. |

Fit-to-envelope remains appropriate for a deliberately authored runtime prop reservation, such as the warehouse containers, but changing laboratory calibration does not rescale those existing warehouse assets.

Quarter-turns are the currently verified rotations. Arbitrary yaw remains inspectable, but its axis-aligned bounds grow conservatively and future module connectors should declare allowed rotations.

## Placement and tactical-authoring conventions

The Lab now resolves `AssetPlacementConventions` for every selected asset. The information panel shows the calibrated visual envelope, visual-origin snap, family assembly pitch, tactical-authoring policy, and any authored footprint already represented by a runtime module.

- City Roads modules snap their visual origins to integer units and use a 5-unit tile pitch.
- Factory pieces use integer visual anchors and a 1.5-unit native-bay multiplier. The assembly fixture aligns measured edges rather than assuming an old fixed pitch.
- Space Kit remains a separate integer-aligned, 4-unit-pitch family.
- General props use half-unit visual anchors until a module supplies a stronger convention.

The **visual envelope** is the calibrated AABB rounded outward for planning. It helps find clearance problems but is never occupancy. An **authored tactical footprint** exists only for assets already represented by a deliberate module, such as containers, roads, factory wall pieces, and the construction barrier. The Lab reports `author_before_gameplay` for tactical-looking assets that still require this decision.

Tactical meaning is also authored, never inferred from category or height. For example, the calibrated shipping container is a solid full-cover obstacle, while the construction barrier is a traversable low-cover cell that costs two movement points and triggers the existing vault pose. A painted floor marking can remain ordinary ground even if its mesh has nonzero height.

## Previously measured representative subset

| Family / asset | Native mesh bounds (X × Y × Z) | Provisional calibration | Observed use |
| --- | ---: | --- | --- |
| Industrial `building-a` | 2.084 × 1.470 × 1.242 | 10×, floor center | Exterior massing reference; closed shell, not an enterable building |
| Industrial `shipping-container-a` | 0.373 × 0.348 × 0.823 | 5× override, floor center | Cargo prop; long axis Z before rotation |
| Industrial chimneys | varies | 5× category, individual overrides where reviewed | Pack-scale industrial structures |
| Roads `road-straight` | 1.000 × 0.020 × 1.000 | 5×, top center | 5 × 5 visual road tile |
| Roads `road-side` | 1.000 × 0.020 × 1.310 | 5×, source origin | Road tile with asymmetric sidewalk overhang |
| Roads `tile-low` | 1.000 × 0.020 × 1.000 | 5×, top center | Matching 5 × 5 paving tile |
| Roads construction fence / dumpster | varies | 5×, floor center | Human-scale street furniture |
| Factory structural wall/window | 1.000 × 3.000 × 2.000 | 1.5×, source origin | 1.5-unit visual bay, 4.5-unit height |
| Factory wide doorway | 2.000 × 3.000 × 2.000 | 1.5×, source origin | 3-unit visual entrance bay at the same height |
| Factory `machine` | 1.200 × 1.300 × 1.500 | 1.5×, floor center | Standalone machinery |
| Factory `conveyor-long` | 2.000 × 0.400 × 1.000 | 1.5×, floor center | 3-unit visual pitch; preview uses a proportional stand |
| Factory `crane` | 1.926 × 3.553 × 3.680 | 1.5×, floor center | Loading-area prop with a strongly offset source pivot |
| Space `template-floor` | 4.000 × ~0 × 4.000 | 1×, source origin | 4-unit visual pitch |
| Space `template-wall` | 4.000 × 4.250 × 1.001 | 1×, source origin | Matching 4-unit wall bay |
| Space `corridor` | 4.000 × 4.250 × 4.000 | 1×, source origin | Enclosed room-scale section |

These dimensions come from Godot's imported mesh hierarchy, including descendant transforms. The catalog stores source path, pack-derived identifier, category, uniform scale, anchor convention and a compatibility note. The generated bounds baseline stores the exact measured values separately.

## Findings from assembly inspection

- Road assets remain internally coherent at 5×: connected tiles use a 5-unit pitch, and the side-road's 1.31 native depth intentionally includes a sidewalk strip. Adjacent paving must account for the 6.55-unit scaled edge, not assume a square footprint.
- Factory structural pieces share dimensions and origins. At 1.5× their seams remain proportional and the wide entrance provides comfortable headroom over the 1.60 m MIRA. Assembly fixtures now derive adjacency from measured bounds, so future scale edits do not create false gaps.
- Factory machinery shares the 1.5× pack baseline, but practical modules still need authored spacing around cranes, conveyors and working faces.
- Space Kit remains internally coherent at a 4-unit pitch and 4.25-unit height under its native-size baseline. It is still a separate construction grammar rather than an automatic match for Factory pieces.
- City Kit Industrial buildings are closed exterior shells. Enlarging one produces convincing exterior massing but does not create an enterable building or tactical collision.
- The existing Industrial Warehouse remains unchanged: its fit-to-envelope placement is runtime presentation data and does not consume this laboratory default.

## Boundaries and Goal 2.2 requirements

New assets begin unreviewed regardless of whether they inherit a category preset. Forward direction is visual and family-specific; filenames and AABBs do not prove entrances or connectors. Decorative details, openings and sparse machinery require authored tactical meaning.

Goal 2.2 should define its first real module records from the verified road/paving and Factory entrance assemblies. A module needs an authoritative cell footprint separate from its visual envelope, allowed quarter-turn rotations, explicit connection points, clearance, presentation placements and suitability tags. Door and road connectors should be authored; bounds should validate clearance and seams rather than generate gameplay state.
