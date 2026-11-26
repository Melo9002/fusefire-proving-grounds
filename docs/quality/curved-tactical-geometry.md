# Curved tactical geometry and partial-tile traversal

This implementation builds on integrated main `0c1184c`, which includes the
planning responsiveness changes from PR #94. Compiler revision 7 connects exact
upright cylinders and yawed rounded rectangles to the existing tactical grid.
Issue #7 is the review and acceptance record. [GitHub issue #7](https://github.com/Melo9002/fusefire-proving-grounds/issues/7)

## Geometry and ownership

| Step | Owner and contract |
| --- | --- |
| Authored solid | `AuthoredSceneMapCompiler` reads asset-local dimensions and shape metadata, composes transforms and registers an analytic solid. Untagged assets retain their existing compiler behavior. Invalid curve metadata, tilt, shear or unequal horizontal scaling use the enclosing box. |
| Deterministic stand | `SurfacePlacement` tests the existing box candidates, projections to curved margins and a fixed within-tile lattice. `SurfaceNavigation` checks the resulting point against floor support and rounds it to 1/10000 tile. The logical grid still has one canonical point per stop. |
| Route and occupancy | `SurfaceNavigation` and `MapGraphBuilder` check full body sweeps before keeping edges. Direct edges and the existing style of supported elbows are considered. Dynamic bodies still use the existing occupied-path clearance checks across the actual route. The AI continues using PR #94's cooperative planning and clearance reuse. |
| Shot and cover | `CombatRules` queries the same shape through the column index for LOS, directional protection, previews, execution and reactions. A curve's open grazing edge doesn't participate in the legacy paired-box seam rule. Ordinary box seams retain their behavior. |
| Visual surface | `TacticalPoseContext` takes the canonical stand and exact surface contact and normal. `CoverVisualizer` draws an arc for cylinder contacts and a tangent marker for rounded boxes. The route builder uses the validated route. |
| Persistence | Authored manifests keep the compiler revision. The standing-point signature includes normalized curved shape records sorted independently of registration order. Revisions 1–6 retain their existing solid and presentation data; the outside pipe's separate obstacle starts at revision 7. |

The rounded prism is the exact union of two rectangular strips and four corner
disks, with a fixed vertical extent. The same footprint answers contact, body
and ray queries. For upright assets the actor uses the existing 0.28 m body
radius, 1.8 m height and 0.04 m extra clearance at the standard 1 m grid.
Rectangular obstacles retain their existing conservative body-box test. The
geometry is compiled once and column-indexed. Tactical queries never scan
render triangles.

Asset definitions carry the shape once, and placed copies inherit it through
the scene transform. The Depot's measured upright shell has a 3.77104 m
radius and a 0.35 m local axis offset. An overlapping authored box covers the
external pipe, including the portion outside the shell. The lying drum keeps
its historical approximation. The rounded cabinet is a reusable authoring
fixture in the real Surface Fit Range battle, with a 3.6 × 2.6 m footprint,
0.65 m corner radius and 0.41 rad yaw. [Asset authoring and replay details](../asset-edge-placement.md)

## Gameplay evidence

| Fixture | Result |
| --- | --- |
| Service Depot, seed 16, upright tank | Revision 7 restored `(26, 0, 6)` beside the shell. A Move from `(25, 0, 6)` committed at world `(6.5, 0, -13.5)`, 0.391 m from the wall. The central tank stayed blocked. The position became unavailable when another unit occupied it. The player move query and AI candidate inventory both offered it once clear. |
| Service Depot, shots and Guard | From `(26, 0, 6)`, the tank blocked the line to `(26, 0, 11)`. Guard agreed. The ray and attack to `(24, 0, 7)` cleared the shell. The player query, AI inventory and committed receipt agreed on 100% chance and cover. An independent ray outside the shell still hit the pipe. |
| Surface Fit Range, seed 17, rounded cabinet | Revision 7 recovered five stops near the cabinet compared with the revision-6 conservative box. One recovered point, `(4, 0, 8)`, was unreachable from the selected deployment with the available action. The same action could reach `(4, 0, 11)` diagonally from `(3, 0, 12)`; preview and execution agreed on the canonical world endpoint `(-11.6248, 0, -4.001)`. |
| Save and reload | The real Range session archived its exact authored parcel. The saved replay reloaded and recompiled that content, then replayed one Move with the recorded result and state fingerprint. |
| Fitting controls | A path with clear endpoints could still intersect a rounded prism. A rounded corner beside a box rejected a gap smaller than the body. Tangency, rotated geometry, positive vertical scale and conservative fallback for unequal horizontal scaling were exercised. |

The 1280×720 rendered run used mainline battle scenes, the normal presentation
clock and OpenGL compatibility. It passed 43 checks, including three captures.
I inspected the rendered stops. This is automated gameplay with inspected
frames rather than a human playthrough. The first two views use the same camera
setup either side of the committed Depot move.

| Depot, before the move | Depot, at the recovered stop |
| --- | --- |
| ![MIRA at the starting cell](images/curved-tactical-geometry/depot-before-move.jpg) | ![MIRA stops beside the circular tank](images/curved-tactical-geometry/depot-curved-stop.jpg) |

![MIRA stops beside the rounded cabinet in Surface Fit Range](images/curved-tactical-geometry/range-rounded-corner.jpg)

```powershell
.\tools\run_tests.ps1 select -Test surface_curved_battle_test,cover_round_presentation_test -Import
New-Item -ItemType Directory -Force artifacts/curved-tactics/rendered | Out-Null
$env:FUSEFIRE_TEST_OUTPUT_DIR = (Resolve-Path artifacts/curved-tactics/rendered).Path
godot_console --path . --resolution 1280x720 --rendering-method gl_compatibility --script res://tests/surface_curved_battle_test.gd -- capture $env:FUSEFIRE_TEST_OUTPUT_DIR
```

## Limits

- Standing-point search is bounded to 32 local parts and 256 tested
  candidates. Mixed geometry can miss a very narrow viable sliver. Accepted
  points still require exact analytic clearance and an independently validated
  route. Surface support and strict diagonal eligibility stay as before.
- The supported shapes are upright extrusions with yaw and equal scale in
  both horizontal axes. Authoring can combine these solids with boxes.
  Arbitrary concavities, hollows, ellipses and walkable curved tops remain
  outside the shape contract. A separate authored floor is required for a
  walkable deck.
- Collision uses the authored body profile, not a per-frame skeleton or
  weapon mesh. Existing idle and cover poses can still lean or extend a
  weapon near an object. Cover and shots always use the authoritative point
  and ray contract. Debug obstacle envelopes are conservative visual aids.
