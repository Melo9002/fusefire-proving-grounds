# 03 — Current surroundings inspection

Step 1 complete: identify problems and reusable content. No map, lighting, camera or gameplay behavior was changed.

## Evidence

Reviewed real rendered battles on **Service Depot, Freight Yard and Fleet Station**, seeds **16 and 17**: six accepted layouts, five views each, **30 captures**, zero capture/initialization failures. Inspected every view using contact sheets. Source inspection covered all six plot definitions, their scenery scenes, shared atmosphere and camera limits.

Reproduce from the project root with a graphics-enabled Godot run:

```powershell
godot_console --path . --script res://tools/environment_authoring/current_surroundings_capture.gd -- artifacts/surroundings-review
```

Images and exact camera transforms/FOV are written to `artifacts/surroundings-review/` and `views.json`. Generated images are local artifacts, not tracked source. This launches a separate diagnostic process; it does not open, save or discard a live parcel session.

- **entry:** initial battle camera and grid, frozen before selection-focus animation; not a test of the completed focus transition.
- **overview/reverse:** opposing clean oblique views, FOV 46°, grid/cursor hidden.
- **low:** eye at `(0, 4, 32)`, looking at `(0, 2, -8)`, FOV 46°. Inspects the skyline; this is a manually positioned view, not an actual replay/action-camera sequence.
- **wide:** eye at `(38, 48, 58)`, FOV 65°. Deliberate diagnostic exposure of the scenery extent, beyond the default gameplay framing; visibility here alone is not a normal-camera defect.

## Short fix list

| Priority | Observed problem | Where / evidence | Smallest direction for later steps |
| --- | --- | --- | --- |
| 1 | The yard paving ends in straight, exposed strips against mostly empty dark ground. The battlefield looks placed on a board. | All six layouts, overview/reverse. | Continue a few nearby surfaces and structures across the edge; give each edge an intentional yard, fence, wall or terrain treatment. Preserve tactical limits. |
| 2 | Roads are isolated straight strips with visible square ends and little connecting development. | All sites in oblique views; especially obvious in wide views. Depot 17 rotates the same strip. | Keep the road assets/calibration. Connect their visible ends to believable surrounding streets or carry them beyond relevant camera views. No road generator is required. |
| 3 | Scenery beyond the yard lacks a continuous setting. Freight/Fleet repeat isolated container stacks and offices on both sides; Depot has one isolated landmark. | Freight/Fleet overview/reverse; Depot 17 reverse. | Group existing props into a small number of surrounding compounds, with connecting ground and varied placement. Keep the useful silhouettes. |
| 4 | There is almost no distant skyline. Low views expose a broad blank gray-green background; fog does not supply a recognizable place. | Low views of every site. | Add a simple distant industrial silhouette and tune the horizon blend only after near-edge continuity is established. |
| 5 | The extended ground is itself a finite square, whose outline remains visible in the wide diagnostic views. | All six wide captures. Source: 144 × 144 ground, versus a 40 × 40 tactical map. | Establish the supported camera envelope first, then hide/blend or extend the outer edge as needed. Do not infer a need for streaming from these captures. |
| 6 | Open terrain beside the yard looks as usable as terrain inside it. Surface color/grid make a rectangle legible, but do not explain why a soldier cannot cross it. | All sites, entry and clean overview views. | Use readable physical/contextual boundaries where appropriate, retaining a tactical boundary aid for deliberately open edges. |

## Keep

- **Service Depot:** warehouse, process equipment and tank-storage identity; water-tower/building landmark choices; the two different road/frontage arrangements. It is the strongest first proof because the industrial setting is already recognizable.
- **Freight Yard:** the contrasting container and fleet aprons, central service lane, parked-vehicle variety and container stacks. They supply the ingredients for a surrounding logistics yard.
- **Fleet Station:** two offices, vehicle court, parking markings and front sidewalk. North/south frontage variants remain useful camera checks.
- **Across all sites:** existing imported models, consistent style, road scale and common light/shadow direction. The shared atmosphere gives reasonably coherent lighting; the conspicuous discontinuity is mainly surface/layout continuity, not a demonstrated lighting failure.
- **Existing ownership:** plot scenes already own surrounding scenery; compilation stamps parcels into tactical MapData separately. Keep that boundary. This inspection did not independently verify every off-map targeting/navigation case.

## Camera and lighting notes

The current camera supports near-horizontal pitch (2° minimum), so a backdrop hidden in overhead views can still become visible during play. Low views therefore matter. Fleet Station seed 16 presents the backs of its offices in the chosen low view and obscures parts of the vehicle court. That is an angle to inspect in step 6, not proof that camera avoidance is broken.

Shared atmosphere is in `systems/generation2/authored_battlefield_layout.gd`: flat-color background, ambient energy 0.58 and fog density 0.006. The owning battle supplies its environment. The existing warm directional light casts coherent shadows across the content. No obvious light seam or floating ground was established in this pass; fine seam inspection remains necessary after adjoining surfaces are authored.

## Next bounded action

Proceed to **step 2**: identify the Tactical / Peripheral / Distant areas in the existing scene ownership, then author one Service Depot continuity proof in step 3. Use the list above as its acceptance checklist. Do not change the generator, add more playable sites, introduce a scenery framework or start LOD/streaming work for this step.

## Limits

This is a visual/source inspection, not a new full regression run, gameplay balance assessment or performance benchmark. All six battles initialized successfully; no actions were played. Actual replay camera sequences, all possible camera positions, edge targeting/pathing and rendering budgets remain for later steps. Godot emitted sandbox certificate/log-store diagnostics; no script/parse failures appeared in the capture log.
