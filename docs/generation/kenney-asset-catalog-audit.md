# Kenney Asset Catalog Audit

This Goal 2.1 audit evaluates the current catalog for visual calibration and future modular battlefield authoring. It changes no calibration values, review states, vendor GLBs or tactical geometry.

The later catalog-wide semantic pass is documented in `semantic-asset-identification-report.md`. This file retains the calibration and dimensional audit; semantic status below reflects the newer classification where relevant.

## Confirmed inventory and calibration mechanism

The repository contains 315 tracked GLBs: 37 City Kit Industrial, 95 City Kit Roads, 143 Factory Kit and 40 Modular Space Kit. Godot successfully measured all 315 imported mesh hierarchies, and `native_bounds.json` retains that catalog-wide measurement baseline.

Persistent developer choices live in `tools/asset_lab/asset_calibrations.json`. Resolution is `asset override > category preset > general fallback`. The current file records 15 per-asset overrides and all 315 assets as calibration-reviewed. The laboratory can save/reset overrides, edit presets, filter review state, move to the next unreviewed asset and report the active source. Curated `PROFILES` provide detailed anchor/orientation notes for representative assets; semantic review remains independent of calibration review.

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
| Factory machinery / interior props | subset of 143 | High identity, reviewed connector scope | Conveyors, cranes, robot arms, machines, pipes, boxes and controls are classified. Two opaque-pipe machine sockets are verified; the other reviewed machine bodies remain intentionally socket-free. |
| Space structural modules | subset of 40 | High by name and render | Floors, walls, open-top rooms, gates, corridors and stairs form a separate coherent 4-unit grammar. |

`factory_kit/oopi` is identified as Kenney's Oopi alien character reference and excluded from environment use. The later six-axis review resolved the directional controls, displays, gates, roadside objects and machine-connection questions without granting procedural eligibility. Classification does not imply tactical occupancy.

## Provisional developer observations

These are historical visual preferences observed during early review. The current laboratory uses a 1.60 m MIRA reference. The observations are neither universal real-world scale nor approval of every asset in a category.

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

Later hands-on review replaced those initial estimates. The current baselines are 5.0 for roads/paving, signs/signals, road lights, chimneys, tanks and the industrial remainder; 1.5 for Factory Kit; and 1.0 for Modular Space Kit. Buildings remain 10.0, electricity infrastructure 10.0, solar panels 10.0, and construction furniture 5.0. Individual overrides preserve exceptions.

## Measured scale flags

Dimensions below are hierarchy AABBs after the currently resolved calibration. They measure visual envelopes, not door clearance, collision, solid occupancy or usable floor space.

- **Industrial landmarks:** `windmill` is approximately 3.02 × 11.57 × 5.63 and `windmill-low` 3.02 × 8.97 × 5.63 at the current scale-5 baseline. Their height still warrants parcel-level clearance.
- **Tanks and chimneys vary greatly inside their categories:** `water-tower` is about 4.26 × 10.71 × 4.16 and `detail-tank-large` 7.54 × 4.81 × 8.24. Chimney Basic retains an individual scale-10 override and measures 2 × 10 × 2; Large is about 5.4 × 8.5 × 5.4 and Medium 2.25 × 9.62 × 2.25 at the category baseline. A shared category does not make their placement interchangeable.
- **Largest closed buildings:** `building-r` spans about 24.84 × 13.93 × 12.72; `building-c` 18.76 × 12.50 × 21.08; `building-l` 20.84 × 19.25 × 18.70. Review these from the tactical camera before using them as modular anchors.
- **Grouped solar panels:** `solar-panel-landscape-group` reaches 13.62 × 2.36 × 8.06 and the portrait group 8.26 × 3.69 × 11.24. They should be treated as arrays with clearance, not interchangeable with single panels.
- **Road assemblies:** the roundabout piece is 15 × 15 and curve/intersection pieces can reach 10 × 10 at scale 5. These are coherent multi-tile surfaces rather than scaling errors. Their authored connector pitch should precede footprint authoring.
- **Electricity variants:** electricity infrastructure retains scale 10 independently from the scale-5 road surfaces. Wide wire and side pieces represent spans, not single poles, and should not be classified as ordinary prop outliers.
- **Human-scale references:** the construction fence is about 0.89 high, the dumpster 1.05 high, and `light-curved` 3.37 high at scale 5. The reviewed container override produces approximately 1.86 × 1.74 × 4.11. These are useful rendered comparison targets because their relation to a MIRA is visually familiar.
- **Cross-pack mismatch:** Factory structure bays are 4.5 high at the current 1.5 baseline, while Space walls and corridors remain about 4.05–4.70 high at native scale. Similar height does not establish compatible pivots, thicknesses or sockets; the packs remain separate construction grammars.

The later semantic pass rendered all 315 assets in 17 family contact sheets. Those normalized thumbnails establish identity and family relationships, while model-local facing and exact seam compatibility still require individual inspection where flagged.

## Prioritized manual inspection shortlist

1. Factory `structure-wall`, `structure-doorway`, `structure-doorway-wide`, `structure-window`, standalone `door*`, stairs and platforms: establish the first wall/entrance grammar and verify actual openings.
2. Roads `road-straight`, `road-side`, `tile-low`, intersections and curves: verify the current 5-unit connection pitch, sidewalk overhang and allowed rotations for plot access.
3. Industrial `shipping-container-a/b/c`, Roads `construction-fence` and `dumpster`: establish cargo lanes and familiar tactical-cover silhouettes.
4. Factory `machine`, `conveyor-long`, `crane` and representative robot arms: author working-face clearance and loading-area arrangements.
5. Industrial `building-r/c/l`, `water-tower`, both windmills, large tank and grouped solar panels: decide whether landmark-specific overrides are necessary before procedural placement.
6. Space `template-floor`, `template-wall`, corridor, gate and stairs: retain as a separate 4-unit construction grammar unless a deliberate adapter module is authored.

For Goal 2.2, add semantic subcategories only as real modules consume them. Store visual placement, authoritative footprint, connectors, clearance and allowed rotations separately. Expand checked-in bounds baselines around the module shortlist rather than freezing all decorative assets at once.
