# 03, step 3 — Depot continuity proof

Both Service Depot layouts now sit within neighboring industrial yards. This is an editable prototype example for future map work, not a finished environment.

## What changed

- Extended the existing road in both directions, preserving its calibrated scale and height. The three sections join without gaps and cover 255 units along the road axis.
- Continued paving beyond all four tactical edges into loading, storage, process and delivery aprons. Their materials reuse the existing parcel palette, and their top height matches the parcel floors. Connecting lanes sit slightly higher to avoid coplanar flicker.
- Added four nearby workshops/warehouses, container storage and two tanks using existing imported assets. Their visible meshes remain outside the playable footprint. The old landmarks and all playable parcels remain in place.
- Enlarged the simple underlying ground to 640 × 640, moving its former visible square cutoff outside the reviewed views. It is still one simple surface, not an infinite terrain or streaming system.
- Added a first distant placeholder using the Commercial kit's existing `low-detail-building-*` family, identified in Asset Lab semantics as background building masses. Nearby industrial buildings remain detailed; distant blocks sit roughly 78–88 units away. This is not a completed skyline composition.
- Following the owner's request, added a **yellow dashed 40 × 40 playable perimeter**, including across open roads. It has no collision and does not close entrances. It is a prototype overlay cue, rather than a claim that the open edge is physically fenced.

The owner confirmed the yellow marking is appropriate for the prototype. Preserve this clear distinction while improving map tools/content later; no additional decorative polish is required to close this step.

## Ordinary editable scenes

Both `depot_loading_crossing.tscn` and `depot_service_spine.tscn` now instance:

- `depot_neighboring_yards.tscn` under **Peripheral**: paving, connecting lanes, neighboring structures and storage.
- `depot_distant_blocks.tscn` under **Distant**: simplified imported background buildings.
- `depot_playable_boundary.tscn` under **Tactical**: four narrow meshes using `presentation/overlays/playable_boundary.gdshader` to draw dashes.

All scenes are under `art/environments/authored/plots/`. Open them directly in Godot to move or replace the placeholder content. The temporary assembly scripts were removed after producing the scene assets. No new generation framework, authoring workflow, boundary editor, runtime tool dependency or downloaded asset was introduced.

The perimeter is authored for flat, 40 × 40 Depot, at height 0.16 so it remains visible over the current paving/road. It is not yet a universal terrain-following boundary for arbitrary maps. Its four ordinary scene meshes keep the cue lightweight. An initial MultiMesh version failed to retain its transforms when saved by the headless authoring process; the saved-scene regression caught this. The replacement stores simple plane sizes/positions and a dashed material directly; no assertion was removed to hide that failure.

## Tactical and replay scope

The playable grid remains 40 × 40. No parcel, population choice, connector, deployment rule, movement/shot/cover rule, mission definition, plot revision or replay schema changed. Scenery remains presentation-only under the ownership introduced in step 2; the presenter does not compile its decorative tactical metadata. The yellow cue follows the existing grid boundary rather than defining a new one.

## Verification

- New `depot_surroundings_test.gd`: both layouts present; neighboring meshes stay outside playable cells; scenery has no physics/navigation bodies; actual road mesh extents meet at matching heights; extended ground supports the road; saved boundary matches map size; distant models come from the low-detail family; presentation leaves tactical state/manifest unchanged; exact reconstruction retains tactical geometry. **Zero failures on final content.**
- Final project import/parse scan completed with exit 0 and no script/parse errors. Sandbox permissions prevented writing user editor settings; no project resource load failure was found.
- Final focused ownership and current-generation checks: **zero failures**. These retain generator independence, bounded tactical data, scenery hazard exclusion and presentation scale coverage.
- Ironclad smoke before the last perimeter/backdrop additions: **11 passed, 0 failed, 0 skipped** (`artifacts/test-results/20261115-195047-smoke`). The **48-case current mission/replay matrix also passed** on that preceding yard/road content. Those were not rerun merely for the final visual-only cue/background additions; the final focused checks and rendered capture cover the resulting scene resources. No full-suite run was performed.
- Final rendered run: **30 views, zero capture/initialization failures**, in `artifacts/depot-continuity-final/`. Reviewed all ten Depot views at seeds 16/17, including normal entry, oblique/reverse, low and diagnostic wide views. Exact camera poses are in `views.json`; the existing capture tool reproduces them. Yellow perimeter, road continuation and surrounding yards are visible. No script, shader or parse errors were found in the capture log; sandbox certificate/log-store diagnostics remain environmental.

## Remaining scope

This closes the continuous-looking Depot proof. Freight Yard and Fleet Station are unchanged. Physical edge treatments, a more cohesive distant horizon, full replay/action-camera obstruction inspection and measured rendering budgets remain subsequent steps. Wide diagnostic framing can still reveal the edges of authored neighboring pads and the sparse placement of background blocks. We are not claiming an endless world, final art, universally clear boundaries at every angle or measured performance compliance.
