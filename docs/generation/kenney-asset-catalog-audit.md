# Kenney Asset Catalog Audit

This Goal 2.1 audit evaluates the current catalog for visual calibration and future modular battlefield authoring. It changes no calibration values, review states, vendor GLBs or tactical geometry.

The later catalog-wide semantic pass is documented in `semantic-asset-identification-report.md`. This file retains the calibration and dimensional audit; semantic status below reflects the newer classification where relevant.

## Confirmed inventory and calibration mechanism

The repository contains 315 tracked GLBs: 37 City Kit Industrial, 95 City Kit Roads, 143 Factory Kit and 40 Modular Space Kit. Godot successfully measured all 315 imported mesh hierarchies during this audit. The resulting analysis was temporary; the checked-in `native_bounds.json` intentionally remains the 14-asset curated baseline.

Persistent developer choices live in `tools/asset_lab/asset_calibrations.json`. Resolution is `asset override > category preset > general fallback`. The current file records 13 per-asset overrides and all 315 assets as calibration-reviewed. The laboratory can save/reset overrides, edit presets, filter review state, move to the next unreviewed asset and report the active source. Curated `PROFILES` provide detailed anchor/orientation notes for representative assets; semantic review remains independent of calibration review.

## Current semantic grouping

| Group | Count | Confidence | Evidence and limitation |
| --- | ---: | --- | --- |
| Buildings | 20 | High | Industrial `building-*`; closed exterior shells, not enterable modules. |
| Shipping containers | 3 | High | Industrial `shipping-container-*`. |
| Chimneys | 4 | High | Industrial `chimney-*`. |
| Tanks / water tower | 3 | High | `detail-tank*` and `water-tower`; the family contains materially different forms. |
| Solar panels | 5 | High | Individual and grouped `solar-panel-*` variants. |
| Windmills / industrial landmarks | 2 | High name, medium use | Currently grouped as `industrial_other`; likely landmarks rather than ordinary props. |
| Roads and paving | 61 | High family, mixed role | Includes roads, barriers, bridges and paving. Names distinguish pieces, but connector semantics are not authored. |
| Signs and signals | 15 | High | Road signs, highway signs and traffic lights. |
| Electricity infrastructure | 8 | High | Poles, side pieces and wire spans; several are connection components rather than standalone poles. |
| Road lights | 6 | High | Curved/square single, double and cross variants. |
| Construction furniture | 5 | High | One fence, one dumpster and three barrier/cone/light pieces. |
| Factory structural modules | subset of 143 | High by name and render | Walls, entrances, corners, railings, platforms and catwalks are distinct semantic families; exact tactical modules remain separately authored. |
| Factory machinery / interior props | subset of 143 | High identity, mixed connector confidence | Conveyors, cranes, robot arms, machines, pipes, boxes and controls are classified; machine-port questions remain flagged. |
| Space structural modules | subset of 40 | High by name and render | Floors, walls, open-top rooms, gates, corridors and stairs form a separate coherent 4-unit grammar. |

`factory_kit/oopi` is identified as Kenney's Oopi alien character reference and excluded from environment use. Directional controls, displays, gates and several roadside objects retain explicit working-face review flags. Classification does not imply tactical occupancy.

## Provisional developer observations

These are visual preferences observed beside the approximately 1.60–1.64 m MIRA reference. They are neither universal real-world scale nor approval of every asset in a category.

| Category | Observed preferred uniform scale |
| --- | ---: |
| Buildings | 9.0 |
| Shipping containers | 9.0 |
| Chimneys | 9.0 |
| Water tanks | 9.0 |
| Solar panels | 9.0 |
| Electricity poles | 9.0 |
| Road lights | 9.0 |
| Construction fences | 5.0 |
| Dumpsters | 5.0 |

The current catalog also assigns 9.0 to roads/paving, signs/signals and the two industrial windmills; 5.0 to three other construction props; and category scale 2.0 to Factory and Space assets. These existing choices were measured, not changed by the semantic pass.

## Measured scale flags

Dimensions below are hierarchy AABBs after the currently resolved calibration. They measure visual envelopes, not door clearance, collision, solid occupancy or usable floor space.

- **Industrial landmarks:** `windmill` is approximately 5.44 × 20.82 × 10.14 and `windmill-low` 5.44 × 16.14 × 10.14. Their height makes them the strongest candidates for individual review within `industrial_other`.
- **Tanks and chimneys vary greatly inside their categories:** `water-tower` reaches 19.27 high; `detail-tank-large` spans about 13.58 × 8.65 × 14.84. Chimneys range from 1.80 × 9.00 × 1.80 (`basic`) to 9.72 × 15.30 × 9.72 (`large`), while `medium` is taller but narrower at 4.05 × 17.32 × 4.05. The variation may be intentional, but a single category multiplier does not prove visual suitability.
- **Largest closed buildings:** `building-r` spans 22.35 × 12.54 × 11.45; `building-c` 16.88 × 11.25 × 18.97; `building-l` 18.75 × 17.32 × 16.83. Review these from the tactical camera before using them as modular anchors.
- **Grouped solar panels:** `solar-panel-landscape-group` reaches 13.62 × 2.36 × 8.06 and the portrait group 8.26 × 3.69 × 11.24. They should be treated as arrays with clearance, not interchangeable with single panels.
- **Road assemblies:** roundabout pieces are 27 × 27 and curve/intersection pieces can reach 18 × 18 at scale 9. These are likely coherent multi-tile assemblies rather than scaling errors. Their authored connector pitch should precede footprint authoring.
- **Electricity variants:** `electricity-pole-wide` spans 9.71 horizontally, compared with 0.71 for `electricity-pole-single`; wide wire/side pieces similarly approach one 9-unit road pitch. Do not classify the wide variants as single-object outliers.
- **Human-scale references:** the scale-5 construction fence is about 0.89 high and the dumpster 1.05 high. Scale-9 road lights are 5.40–6.07 high. Shipping containers resolve to roughly 3.35 × 3.13 × 7.40. These are useful rendered comparison targets because their relation to a MIRA is visually familiar.
- **Cross-pack mismatch:** Factory doors are about 1.60 high and Factory structure bays 3.00 high at native scale, while Space walls/corridors are 4.05–4.70 high. Both packs are internally coherent, but they should not share seams or floor heights automatically.

The later semantic pass rendered all 315 assets in 17 family contact sheets. Those normalized thumbnails establish identity and family relationships, while model-local facing and exact seam compatibility still require individual inspection where flagged.

## Prioritized manual inspection shortlist

1. Factory `structure-wall`, `structure-doorway`, `structure-doorway-wide`, `structure-window`, standalone `door*`, stairs and platforms: establish the first wall/entrance grammar and verify actual openings.
2. Roads `road-straight`, `road-side`, `tile-low`, intersections and curves: verify 9-unit connection pitch, sidewalk overhang and allowed rotations for plot access.
3. Industrial `shipping-container-a/b/c`, Roads `construction-fence` and `dumpster`: establish cargo lanes and familiar tactical-cover silhouettes.
4. Factory `machine`, `conveyor-long`, `crane` and representative robot arms: author working-face clearance and loading-area arrangements.
5. Industrial `building-r/c/l`, `water-tower`, both windmills, large tank and grouped solar panels: decide whether landmark-specific overrides are necessary before procedural placement.
6. Space `template-floor`, `template-wall`, corridor, gate and stairs: retain as a separate 4-unit construction grammar unless a deliberate adapter module is authored.

For Goal 2.2, add semantic subcategories only as real modules consume them. Store visual placement, authoritative footprint, connectors, clearance and allowed rotations separately. Expand checked-in bounds baselines around the module shortlist rather than freezing all decorative assets at once.
