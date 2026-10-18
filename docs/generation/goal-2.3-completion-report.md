# Goal 2.3 Completion Report — Coherent Layout Assembly

Status: **demonstrated as an opt-in procedural assembly and visual-coherence foundation**

## Architecture and strategy

FuseFire now assembles modular environments through a seeded identity, connected macro road plot, road-facing parcels of more than one size, authored parcel compositions, and contextual street details. `EnvironmentLayoutPlan` records the hierarchy and its decisions. `CoherentEnvironmentAssembler` performs bounded transactional placement. The shared `EnvironmentModuleMapWriter` commits accepted definitions into authoritative `MapData` for both authored and procedural layouts.

The generator distinguishes tactical footprints, placement clearances, and calibrated visual envelopes. Footprints author gameplay. Clearances reserve functional space. Visual envelopes reject known mesh overhang conflicts during assembly without becoming movement or combat geometry.

The approach adapts useful Plot and Parcel concepts found in the local XCOM 2 SDK: large-scale plots, multiple parcel sizes, facing-aware entrance slots, eligibility and mission metadata, deterministic selection, backtracking records, and explicit plot-cover pieces. The practical lesson is that a parcel is an authored coherent place; unrelated props are later details. No XCOM code or content is copied.

## Problems found in visual review

- Storefront and window-wall modules were being used as whole buildings, producing freestanding Hollywood-set façades.
- Logical road connectivity was represented by narrow individual meshes, so a connected graph still looked broken.
- Parcel fillers placed valid objects without enough functional relationship to one another.
- Visual-envelope coverage was incomplete, allowing calibrated meshes to overhang into unrelated structures.
- A newly enclosed building exposed deployment cells that were legal in isolation but disconnected from the road-connected playable region.

## Implemented behavior

- Three environment identities: industrial district, commercial street, and mixed service.
- Seeded crossroad and rotated T-junction networks with connected approaches that reach map boundaries.
- Ten-cell parcels plus a larger 20 × 20 district parcel carrying road-edge metadata.
- A complete City Kit Industrial building shell for the large parcel.
- A roofed, four-sided Factory Kit service building with multiple usable entrances.
- Loading-bay, machinery-yard, service-alley, and courtyard compositions.
- Rotation of templates toward an adjacent road edge.
- Bounded candidate attempts, recorded rejection reasons, and explicit open-ground fallback.
- Rotation-aware tactical footprints, same-layer clearance reservations, and calibrated visual-envelope rejection.
- Continuous visible road surfaces generated from the connected road plan.
- Contextual traffic signals, stop signs, streetlights, utility poles, fences, and dumpsters chosen after road and parcel planning.
- Catalog visual references that resolve saved Asset Lab scale, yaw, anchor, and offset without changing tactical footprints.
- Deterministic repair of deployment cells onto the road-connected ground component.
- Coexistence with all four authored Goal 2.2 presets and every older generation mode.
- Shared modular presentation for authored and procedural source kinds.

Representative inspection seeds are:

- `industrial_district`, seed `2208` — T junction, complete structures, loading and machinery parcels.
- `commercial_street`, seed `7319` — crossroad, district building, service buildings, and traffic signals.
- `mixed_service`, seed `11027` — T junction with commercial and industrial compositions.
- `industrial_district`, seed `7` — demonstrates a rejected visual-envelope conflict followed by a valid alternative.

## Map Editor

The Map Editor selector includes authored layouts and all three procedural identities. Procedural maps use a 50 × 40 tactical canvas. Cyan outlines identify road plot cells; amber outlines identify parcels. Press `P` or use **Plan overlay** to hide those diagnostics and inspect the rendered environment. Status text reports topology, road and parcel counts, rejection count, fallback use, component count, and shared tactical validation.

The compact Map Composer mode can start from its fixture or copy the displayed authored/generated layout. It supports catalog selection, click-to-place grid snapping, selection outlines, one-cell movement, quarter-turn rotation, deletion, placement validation, and save/reload through readable project-local JSON. This creates the authored parcel workflow needed to improve procedural composition without hard-coding every arrangement.

Launch it with:

```powershell
godot_console --path . res://tools/map_editor.tscn -- 2208 industrial_district
```

Seed controls, orbit, pan, zoom, direct click selection, outline, framing, and the presentation-transform scratchpad continue to work. The capture fixture now records overview, overhead, and street-level views for each representative identity.

## Verification

- Focused coherent assembly regression: 0 failures.
- Existing modular component regression: 0 failures.
- Map Editor layout persistence regression: 0 failures, including disk save/reload, invalid data rejection, and the tracked starter layout.
- Ironclad smoke: 9 passed, 0 failed.
- Ironclad generation subsystem: 15 passed, 0 failed, 5 explicit-only checks skipped, 161.42 seconds.
- Ironclad UI subsystem: 15 passed, 0 failed, 57.72 seconds.
- D3D12 rendered capture completed at 900p for all three representative identities in overview, overhead, and street views and was manually inspected.
- The starter composition and compact composer UI were rendered and inspected at the project's new 1600 × 900 reference resolution.
- `git diff --check`: clean after documentation normalization.

The automated results establish deterministic planning, bounded termination, connected road graphs, spatial conflict rejection, tactical validity, deployment legality, presentation dispatch, and Map Editor behavior. Rendered inspection separately confirms that the planned road and parcel structure and calibrated meshes are visible; it is not inferred from headless success.

## Remaining limits

- Road grammar currently creates one intersection with straight approaches. Multiple intersections, curves, lane markings, curbs, and secondary streets remain extensions.
- The first template catalog is intentionally small and creates at most one large district parcel.
- City Kit shells are exterior-only tactical obstacles. Factory service buildings are enterable but lack furnished interiors and gameplay-driven roof cutaways.
- Many catalog assets still lack authored visual envelopes and functional parcel roles.
- Open-ground fallback is explicit but not yet scored for environmental quality.
- Mission needs are validated after assembly rather than reserving parcels before placement.
- Procedural vertical environments remain deferred; the authored vertical fixture still protects elevated translation and traversal.

Goal 2.3's core outcome is demonstrated: the same modular catalog can now produce distinct seeded environments with continuous streets, complete building forms, recognizable functional parcels, visible rejection diagnostics, and valid tactical connectivity. Future work can extend the grammar rather than replace the foundation.
