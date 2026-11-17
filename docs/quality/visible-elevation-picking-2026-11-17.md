# Visible elevation picking — 2026-11-17

Fix for [issue #27](https://github.com/Melo9002/fusefire-proving-grounds/issues/27).

## Problem and correction

On the Tactical Test Range, a soldier beside the ramp could not select its visible ramp, stairs or gallery while viewing Ground. The navigation graph already allowed the ascent. MouseRaycaster instead picked the surface closest to the inspected floor and rejected anything above it; automatic inspection uses the selected soldier's height too.

Ordinary picking now chooses the first visible legal surface along the camera ray. Hidden roof colliders remain available to explicit Alt+wheel inspection, but cannot intercept ordinary interior clicks. Changing floor inspection applies the existing cutaway update immediately, so a subsequent click sees the new visibility state. The cached choice accounts for visibility changes while preserving explicit cycling between unchanged stacked surfaces.

This changes input selection, not movement costs, traversal, combat, geometry or replay simulation rules. The existing hidden-layer unit-picking filter is retained where a cutaway actually hides a candidate. Global camera ownership remains a separate tracked concern (#2).

## Reproduction and verification

`tests/visible_elevation_picking_test.gd` loads the real selectable range, puts the active soldier at `(11,0,15)`, and checks ramp `(11,1,14)`, stairs `(6,1,14)` and landing `(11,3,12)` with both automatic and explicit Ground viewing. It checks a legal movement hover and commits a real Move onto the picked landing.

- Before correction: initial regression **14 checks, 7 failures**. Physical candidates and navigation were valid; picking and the resulting destination were wrong.
- Final focused headless regression: **15 checks, 0 failures**.
- Movement subsystem: **23 pass, 0 fail, 0 skip** (103.91s), including elevation cycling, hidden-roof movement, surface navigation and replay. The final test-only capture setup was subsequently checked by the focused headless and graphics runs.
- Final smoke: **11 pass, 0 fail, 0 skip** (47.09s).
- Separate `tactical_camera_aperture_test.gd`: **0 failures**; `compact_battlefield_test.gd`: **0 failures**.
- Graphics run: **17 checks, 0 failures**, including an angled camera pick and capture. Inspected `artifacts/elevation-review/visible-ascent-ground-view.png`: Ground remains selected while the blue route climbs the ramp onto the gallery and the movement preview shows the AP cost. This is a focused visual check, not an exhaustive manual playthrough.

Commands:

```powershell
.\tools\run_tests.ps1 subsystem -Subsystem movement
godot_console --headless --path . --script res://tests/visible_elevation_picking_test.gd
godot_console --headless --path . --script res://tests/tactical_camera_aperture_test.gd
godot_console --headless --path . --script res://tests/compact_battlefield_test.gd
godot_console --path . --script res://tests/visible_elevation_picking_test.gd -- capture artifacts/elevation-review
```

Godot emitted the environment's existing root-certificate-store warning; it did not prevent these checks. No full AI or replay subsystem rerun was needed for this input-only correction. Shader polish remains deferred.

## Quick hands-on check

Open Tactical Test Range in Match Setup. Keep Ground selected, move beside either ramp or stairs, then hover and click a reachable visible upper surface. The blue path should climb and the soldier should follow without manually switching floors. Use Alt+wheel when intentionally choosing a surface beneath another one. In the warehouse, Ground inspection should still allow interior clicks without accidentally selecting its hidden roof.
