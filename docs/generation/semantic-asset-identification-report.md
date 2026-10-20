# Comprehensive Semantic Asset Identification

This report records the catalog-wide semantic pass over FuseFire's 315 imported Kenney environment models. It is based on stable asset IDs, source-pack naming, native geometry measurements, rendered family contact sheets, existing calibration profiles and established module contracts.

Semantic interpretation remains separate from visual calibration and tactical authority. The original identification pass changed no GLB, calibration value, reviewed-calibration state, `MapData` cell, collision, cover, traversal or procedural approval. After the developer completed the rendered batch inspection, all current interpretations were promoted to confirmed records. Later environment work separately approved only assets that gained placement contracts.

## Coverage

| Source pack | Assets | Result |
| --- | ---: | --- |
| City Kit Industrial | 37 | Buildings, cargo, exhaust, storage and power equipment identified. |
| City Kit Roads | 95 | Road surfaces, barrier overlays, supports, paving, utilities, signs and signals distinguished. |
| Factory Kit | 143 | Structural bays, railings, platforms, conveyors, pipes, machines, controls and props identified. |
| Modular Space Kit | 40 | Corridors, open-top rooms, gates, stairs, walls, floors and utility details identified as a separate grammar. |
| **Total** | **315** | **315 catalog identities; all scoped orientation and machine-connection reviews resolved.** |

The effective catalog now contains 315 human-confirmed records. Every stable ID has a supported identity and no record retains a review flag. Procedural eligibility remains narrower: 32 assets currently have explicit visual placement contracts.

The catalog uses five independent review flags:

- `identity`: the object itself is not understood.
- `working_faces`: identity is known, but the model-local operating or street-facing side needs confirmation.
- `connections`: identity is known, but exact compatible mounts or ports need authoring.
- `clearance`: additional functional clearance remains uncertain.
- `assembly`: intended structural combination remains uncertain.

A catalog classification can therefore be useful without pretending every orientation or connector is verified. Human-confirmed annotations still override the catalog classification and clear its unresolved flags unless the confirmed record explicitly retains one.

## Important corrections from rendered inspection

- The 22 City Roads names containing `barrier` are edge/barrier overlay meshes, not complete road surfaces. They now use `road_barrier_modules` and cannot be mistaken for traversable road geometry.
- Factory `structure-high`, `structure-medium`, `structure-short`, `structure-tall` and their yellow variants are post-and-rail modules. They are railings rather than building walls.
- Factory scanners are intentionally open pass-through arches. Their visual bounds must not become solid occupancy.
- Space rooms are complete open-top room modules for tactical cutaway presentation while remaining fragments of the larger corridor grammar.
- Factory inner and outer corners expose two equal working faces. Rendered compass inspection establishes inner `+Z + +X` and outer `-Z + -X`.
- Crane lift and magnet models are attachments; the freestanding crane is the complete machine.
- Traffic-light object variants and road-sign object variants are mountable components, while their pole/gantry variants are complete roadside objects.
- Opaque and glass Factory pipes form separate connection families even though their dimensional grammar is related.

## Family summary

Major classified families include 20 industrial building shells, 54 road surfaces/barrier overlays, 11 signs, five traffic signals, 38 conveyors, 18 pipe modules, 15 Factory structural/railing pieces, 11 Space corridors and seven open-top Space rooms. Smaller families cover containers, chimneys, tanks, power generation, bridge supports, electrical spans, streetlights, controls, catwalks, cranes, doors, hoppers, machines, robotics, scanners, screens, gates, stairs and floor/platform systems.

Each family now provides, where supported:

- Object kind, structural role and completeness.
- Attachment convention and environment contexts.
- Connection-family tags.
- One or two working faces when evidence is strong.
- Orientation, clearance and assembly guidance.
- Explicit unresolved-field flags where evidence is insufficient.

These tags describe visual meaning. Exact tactical footprints, interaction cells, cover, line of sight and traversal still belong to environment module definitions and `MapData`.

## Resolved review batches

### Working faces

All 45 flagged records were rendered from local `+Z`, `-Z`, `+X`, `-X`, top and bottom views. Calibration yaw was deliberately excluded from the decision so the stored values remain model-local:

- Industrial shells `building-a` through `building-t` use the door, loading-bay and window composition as evidence. Most face `-Z`; `building-g` and `building-m` face `+Z`.
- Highway panels face `-Z`. The warning sign and all four signal variants face `-X`, where their colored panels or lenses are visible.
- Empty sign mounts and the orthogonal street-name sign are axis-neutral because their geometry has no unique horizontal operating side.
- Factory screens face `-Z`; lever controls face `+Z`; the four top-actuated floor buttons are axis-neutral.
- Space gates expose equal `+Z` and `-Z` working faces because the passage is bidirectional.
- Oopi's visible face points toward local `-X`. It remains a non-environment character reference and is not procedurally approved.

These rendered findings were subsequently confirmed by the developer after batch inspection. A future correction can still replace an individual annotation without changing calibration or tactical authority.

### Machine connections

All 16 Factory machinery flags were reviewed with six-axis renders, native bounds and pivots, animation inspection, and explicit native-scale seam assemblies:

- `machine-connection-hole` exposes a `factory_pipe` receiver at native local `(0, 1.293, 0.36)`, normal `+Y`.
- `machine-connection-pipe` exposes a `factory_pipe` outlet at native local `(0, 1.75, 0.36)`, normal `+Y`.
- The verified example mate uses the `pipe-large` local `-X` endpoint `(-0.5, 0.5, 0)`, rotated `+90°` around Z. Its pivot-aware origin is offset `(0.5, 0.5, 0)` from either machine socket. This transform was rendered directly; an unrotated bounds overlap is not accepted as evidence.
- The five cogs are complete standalone machine props. Their central bores are not treated as verified sockets.
- The four animated pistons are complete standalone machinery. Their animation and vertical operating clearance are preserved; matching envelopes do not establish compatibility.
- The generic, bed, fortified, window and window-bar machine bodies have no verified external socket. Their top details are not general-purpose mounts.

Opaque and glass pipes remain distinct connection families. The review itself granted no procedural approval; later building and streetscape work approved selected assets only after authoring placement contracts.

## Inspection workflow

Run the Asset Lab with `res://tools/asset_lab/asset_lab.tscn` and **F6**. The interpretation filter now separates:

- Needs semantic review.
- Unknown identity.
- Confirmed semantics.
- Catalog-classified semantics.

An exclamation marker means the identity is useful but one or more fields remain unresolved. A question mark means the identity itself is unknown. **Next unresolved semantic asset** advances through the active family/category/search filters. The information panel shows evidence plus orientation, clearance and assembly guidance.

For family comparison, run:

```powershell
godot_console --path . --script res://tests/semantic_asset_contact_sheet.gd -- C:\path\to\output
```

The command produces 17 labeled pages covering all 315 assets. Thumbnail cameras normalize framing only; the label preserves each model's native dimensions and no calibration data is changed.

For a six-axis review of specific stable IDs, run:

```powershell
godot_console --path . --script res://tests/semantic_asset_review_capture.gd -- C:\path\to\output factory_kit/screen-wide modular_space_kit/gate-lasers
```

For the reviewed Factory seam study, run:

```powershell
godot_console --path . --script res://tests/semantic_machine_connection_capture.gd -- C:\path\to\machine-connections.png
```

Both are explicit graphical diagnostics. They never write calibration or semantic data.

## Trust and procedural use

Resolution remains:

1. Human-confirmed annotation.
2. Catalog classification supported by pack, name and rendered family evidence.
3. Conservative unknown fallback.

Procedural selection still requires a confirmed record with explicit `generation_ready`. Structural fragments remain available for authored assemblies without qualifying as complete buildings. User-confirmed records survive schema loading and future catalog inference changes because they remain stored separately in `asset_semantics.json`.
