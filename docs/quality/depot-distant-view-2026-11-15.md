# 03, step 5 — Depot distant view

The isolated background placeholders are now six modest building districts around Depot. Both layouts share the same ordinary editable `art/environments/authored/plots/depot_distant_blocks.tscn` under Distant.

## Content and purpose

- Six district anchors spaced around the site, roughly 100 units from its center. Each contains six existing low-detail building silhouettes and one simple ground pad.
- Mostly low rooflines, with a few taller silhouettes. Ground pads give the groups a place in higher-angle views instead of leaving single buildings standing alone.
- The existing Commercial-kit `low-detail-building-wide-a`, `wide-b`, `d` and `f` geometry, using the established uniform scale 10. Source paths remain on the editable building nodes. Imported visual meshes were saved into this authored backdrop scene; source GLBs and their materials were not edited. Replacing/changing an original model does not automatically rebuild these saved visual meshes.
- One scene-owned muted, desaturated building material and a subdued ground material. Nearby structures, tactical assets, shared lighting and fog are unchanged. Background models cast no shadows and introduce no lights.
- **42 meshes, 6,060 triangles** in total: 36 building silhouettes and six pads. The focused content check caps this scene at 60 meshes and 6,500 triangles. This bounds content complexity; it is not a frame-time performance result.

The six existing top-level anchors remain, preserving the earlier ownership/placement checks. The added district content stays outside the 70-unit separation used for this backdrop. No tactical grid, generation choices, population rules, missions, boundary markings or replay schema changed. No physics/navigation bodies, streaming, LOD framework or runtime authoring dependency was added. Temporary inspection/assembly scripts were removed after the editable scene was saved.

## Review views

The existing `tools/environment_authoring/current_surroundings_capture.gd` tool now adds three more cardinal low views and two higher views for Depot. It captures **40 views** across the three sites and seeds 16/17; the additional views apply only to Depot. Exact poses/FOV are written to `views.json` beside the images.

```powershell
godot_console --path . --script res://tools/environment_authoring/current_surroundings_capture.gd -- artifacts/depot-distant-review
```

Reviewed Depot's four horizon directions, normal oblique/entry views, a near-vertical high view, and diagnostic wide framing. The skyline is visible at low angles, while the high battle view keeps attention on the playable area. The high-wide pose deliberately exceeds normal gameplay framing to inspect all districts; it is not a supported-camera-range promise. Ordinary street spaces remain between districts; this is a prototype setting rather than a continuous city wall or final environment art.

## Validation

- New `depot_distant_view_test.gd`: **14 expected content failures** on the previous scene (two uncovered heading gaps, six shadow-casting meshes and six missing muted material overrides); **zero failures** on the final scene. It checks distribution, separation, grounding, material restraint, no extra lights/shadows/physics/navigation, and the geometry cap.
- During iteration the test also needed support for PrimitiveMesh surface arrays and oriented pad bounds. A rotated pad's conservative world AABB includes empty space, so distance is now measured against its oriented rectangle. The 70-unit separation and geometry caps were preserved; no existing assertion was removed or weakened to pass.
- Final focused checks: **5 passed, 0 failed** — distant view, Depot surroundings, boundary readability, world-area ownership and current generation. Existing exact perimeter, source-family and six-anchor checks remain intact.
- Final rendered run: **40 captures, zero capture/initialization failures**. No script/shader/parse errors appeared in its log. The final project import/parse scan is also checked. Sandbox certificate/log-store/editor-settings diagnostics remain environmental. No broad mission/replay or full suite rerun was needed for this static scene and capture-tool change.

## Step-6 camera follow-up

The first westward diagnostic used eye `(32, 4, 0)`, looking at `(-8, 2, 0)`, FOV 46. That eye lies inside the nearby EastWorkshop and obscures the battlefield. Those images were retained locally as `service_depot-16-low_west-obstructed.png` and `service_depot-17-low_west-obstructed.png`. The horizon-review pose now uses eye `(25, 4, 0)` in the clear space between the workshop and the tactical edge.

This is a concrete obstruction case to exercise in step 6. The capture script directly sets the camera while its normal rig processing is disabled; the image alone does **not** establish a failure of live/replay camera avoidance. Reproduce under actual camera control, inspect orbit/zoom/cinematic paths and existing aperture/fade behavior, and keep the saved blocked pose as a diagnostic. The step-5 change does not fix or claim to validate those behaviors.

Next: step 6, cameras and obstruction. Renderer/frame-time budgets remain step 8, and applying the finished pattern to Freight Yard/Fleet Station remains the later rollout.
