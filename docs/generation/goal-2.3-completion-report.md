# Goal 2.3 Completion Report — Coherent Layout Assembly

Status: **demonstrated as an opt-in procedural assembly foundation**

## Architecture and strategy

FuseFire now assembles modular environments in three layers: a seeded environment identity, a connected macro road plot, and road-aware parcels filled by authored templates. `EnvironmentLayoutPlan` records the hierarchy and its decisions. `CoherentEnvironmentAssembler` performs bounded transactional placement. The shared `EnvironmentModuleMapWriter` commits accepted definitions into authoritative `MapData` for both authored and procedural layouts.

The generator distinguishes tactical footprints, placement clearances, and calibrated visual envelopes. Footprints author gameplay. Clearances reserve functional space. Visual envelopes reject known mesh overhang conflicts during assembly without becoming movement or combat geometry.

The approach adapts useful Plot and Parcel concepts found in the local XCOM 2 SDK: large-scale plots, facing-aware parcels, entrances and eligibility metadata, randomized deterministic ordering, and search for a valid arrangement. No XCOM code or content is copied.

## Implemented behavior

- Three environment identities: industrial district, commercial street, and mixed service.
- Seeded crossroad and rotated T-junction networks with connected approaches that reach map boundaries.
- Ten-cell parcels carrying road-edge metadata.
- Storefront, loading-bay, yard, workshop, service-alley, and courtyard templates.
- Rotation of templates toward an adjacent road edge.
- Bounded candidate attempts, recorded rejection reasons, and explicit open-ground fallback.
- Rotation-aware tactical footprints, same-layer clearance reservations, and calibrated visual-envelope rejection.
- Deterministic repair of deployment cells invalidated by an accepted tactical obstacle.
- Coexistence with all four authored Goal 2.2 presets and every older generation mode.
- Shared modular presentation for authored and procedural source kinds.

Representative inspection seeds are:

- `industrial_district`, seed `2208` — T junction, loading and machinery parcels.
- `commercial_street`, seed `7319` — crossroad with repeated storefront parcels.
- `mixed_service`, seed `11027` — T junction with commercial and industrial parcels.
- `industrial_district`, seed `7` — demonstrates a rejected visual-envelope conflict followed by a valid alternative.

## Map Editor

The Map Editor selector includes authored layouts and all three procedural identities. Procedural maps use a 50 × 40 tactical canvas. Cyan outlines identify road plot cells; amber outlines identify parcels. Status text reports topology, road and parcel counts, rejection count, fallback use, component count, and shared tactical validation.

Launch it with:

```powershell
godot_console --path . res://tools/map_editor.tscn -- 2208 industrial_district
```

Seed controls, orbit, pan, zoom, direct click selection, outline, framing, and the presentation-transform scratchpad continue to work.

## Verification

- Focused coherent assembly regression: 0 failures.
- Existing modular component regression: 0 failures.
- Ironclad smoke: 9 passed, 0 failed.
- Generation subsystem before the new test registration: 14 passed, 0 failed, 4 explicit-only checks skipped. The runner now includes `coherent_` tests in future generation runs.
- Ironclad full: 88 passed, 0 failed, 8 explicit-only visual/stress checks skipped, 673.41 seconds.
- D3D12 rendered capture completed for all three representative identities and was manually inspected.
- `git diff --check`: clean after documentation normalization.

The automated results establish deterministic planning, bounded termination, connected road graphs, spatial conflict rejection, tactical validity, deployment legality, presentation dispatch, and Map Editor behavior. Rendered inspection separately confirms that the planned road and parcel structure and calibrated meshes are visible; it is not inferred from headless success.

## Remaining limits

- Road grammar currently creates one intersection with straight approaches. Multiple intersections, curves, secondary streets, and larger blocks remain extensions.
- Parcel size is fixed and the first template catalog is intentionally small.
- Most catalog assets do not yet have calibrated visual envelopes.
- Open-ground fallback is explicit but not yet scored for environmental quality.
- Mission needs are validated after assembly rather than reserving parcels before placement.
- Procedural vertical environments remain deferred; the authored vertical fixture still protects elevated translation and traversal.

Goal 2.3's core outcome is demonstrated: the same modular catalog can now produce distinct seeded environments with recognizable road and parcel organization, visible rejection diagnostics, and valid tactical connectivity. Future work can extend the grammar rather than replace the foundation.
