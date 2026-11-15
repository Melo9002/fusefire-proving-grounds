# 03, step 4 — Readable Depot boundary

Both Depot layouts now combine a precise prototype indicator with physical context:

- **Yellow dashed perimeter:** the exact 40 × 40 playable limit, retained unchanged.
- **Short low fence runs:** existing construction-fence assets along two non-road edges. The crossing layout uses north/east; the spine layout uses east/south.
- **Four corner cones:** existing construction cones just outside the playable rectangle.
- **Open-road ground labels:** “BATTLE LIMIT” at both road crossings, on the out-of-bounds side. They explain the limit using words as well as color. Roads themselves remain open and continue into the surroundings.

The result is a prototype pattern for future map authoring. Physical cues suggest a site edge; yellow dashes remain the exact limit wherever scenery is open or continues farther. This is the Depot proof; applying the approach to the other two sites remains the later rollout step.

## Editing and ownership

`art/environments/authored/plots/depot_edge_cues_crossing.tscn` and `depot_edge_cues_spine.tscn` are ordinary editable scenes. Each is instanced as `Peripheral/BoundaryCues` in its corresponding Depot plot. There is no new runtime script, authoring tool, asset role or generation path. Temporary assembly/inspection scripts were removed after saving the scenes.

Construction-fence geometry was measured before placement: at the established scale 5 it is 0.375 wide × 0.89375 high × 1.875 long, with its long axis along local Z. Panels use explicit rotations and a 1.9 pitch. Fence centers sit 0.65 beyond the tactical edge; their visible geometry stays outside playable cells. Cones use the same existing asset-family scale. Labels sit at ground height 0.18, clear of the current road surface, and face the approaching player side of each crossing.

No tactical cell, walkability, cover, LOS, population, mission, connector or replay contract changed. The cues add no physics or navigation bodies. They are scenery; they do not define the grid or close a tactical entrance. The original perimeter remains a flat-Depot prototype indicator rather than an arbitrary-terrain solution.

## Validation

- New `depot_boundary_readability_test.gd`: **two expected missing-content failures before implementation; zero failures afterward**. It checks both layouts, physical geometry outside playable cells and the continuing-road corridor, all four corners, both text labels, absence of physics/navigation bodies, preserved visible perimeter and a bounded grid.
- Final focused checks: **4 passed, 0 failed** — boundary readability, Depot surroundings, world-area ownership and current generation. Existing assertions were retained. No full suite or broad mission/replay rerun was needed for this scenery-only change.
- Rendered capture: **30 views, zero capture/initialization failures**, under `artifacts/depot-boundary-review/`. Inspected Depot entry/overview views plus a six-view overview/reverse/low sheet for seeds 16/17. The labels, short fences and yellow limit remain visible; the road crossings are unobstructed. Actual action/replay-camera inspection and rendering budgets remain later steps.
- Project import/parse scan and capture logs are checked for script/shader/parse failures. Sandbox certificate/log-store/editor-settings diagnostics are environmental; they are not gameplay failures.

Reproduce the pictures with the existing `tools/environment_authoring/current_surroundings_capture.gd` tool. A real player usability pass can still judge contrast and comprehension; geometric checks alone do not establish that every player will understand the boundary from every angle.
