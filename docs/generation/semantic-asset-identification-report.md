# Comprehensive Semantic Asset Identification

This report records the catalog-wide semantic pass over FuseFire's 315 imported Kenney environment models. It is based on stable asset IDs, source-pack naming, native geometry measurements, rendered family contact sheets, existing calibration profiles and established module contracts.

Semantic interpretation remains separate from visual calibration and tactical authority. This pass changes no GLB, calibration value, reviewed-calibration state, `MapData` cell, collision, cover, traversal or procedural approval.

## Coverage

| Source pack | Assets | Result |
| --- | ---: | --- |
| City Kit Industrial | 37 | Buildings, cargo, exhaust, storage and power equipment identified. |
| City Kit Roads | 95 | Road surfaces, barrier overlays, supports, paving, utilities, signs and signals distinguished. |
| Factory Kit | 143 | Structural bays, railings, platforms, conveyors, pipes, machines, controls and props identified. |
| Modular Space Kit | 40 | Corridors, open-top rooms, gates, stairs, walls, floors and utility details identified as a separate grammar. |
| **Total** | **315** | **315 catalog identities; unresolved fields remain explicit.** |

The effective catalog contains 12 existing human-confirmed records and 303 catalog classifications. Sixty-one assets retain one or more narrowly scoped review flags. Every stable ID now has a supported identity. The existing 12 procedural approvals remain the only procedural approvals.

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

## Remaining review batches

### Oopi character reference

`factory_kit/oopi` is a small white ovoid alien on teal feet. The exact model name and rendered form align with Kenney's Oopi character; Kenney's own *Oopi's Quest* identifies Oopi as an alien. The catalog therefore treats this model as a non-environment `character_reference` and easter egg, with medium confidence because the Factory Kit page does not explicitly document the cameo. It remains procedurally unapproved and only its local facing is flagged for review. Sources: [Kenney Factory Kit](https://kenney.nl/assets/factory-kit) and [Oopi's Quest](https://kenney.itch.io/oopis-quest).

### Working faces

Forty-five records still need a model-local facing decision: 15 unconfirmed industrial shells, seven complete sign/gantry models, four unconfirmed traffic signals, six Factory controls, eight screens/panels, four Space gates and Oopi. Their identity and placement category are already usable.

### Machine connections

Nine cog/piston components and seven complete machine variants have a reliable machine-family identity. Their exact port compatibility remains unresolved. This should be authored from actual seam tests rather than inferred from AABBs.

No asset in these review batches receives procedural approval merely by resolving its semantic question.

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

## Trust and procedural use

Resolution remains:

1. Human-confirmed annotation.
2. Catalog classification supported by pack, name and rendered family evidence.
3. Conservative unknown fallback.

Procedural selection still requires a confirmed record with explicit `generation_ready`. Structural fragments remain available for authored assemblies without qualifying as complete buildings. User-confirmed records survive schema loading and future catalog inference changes because they remain stored separately in `asset_semantics.json`.
