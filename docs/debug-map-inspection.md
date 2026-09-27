# Debug map inspection

Task 24A extends the existing F3 tools with read-only inspection of the battlefield model.

## Using the inspector

1. Start an authored or generated match.
2. Press **F3**.
3. Enable **Inspect map cells and metadata**.
4. Close the F3 panel or leave it open while paused, then hover a walkable map surface.
5. On stacked terrain, hold **Alt** and use the mouse wheel to choose another surface.

The top-right inspection overlay reports:

- map source, dimensions, and generation seed;
- total, walkable, stoppable, elevated, occupied, and line-of-sight-blocking cells;
- low and full cover counts;
- zone, traversal-link, building, platform, and hill counts;
- hovered cell grid and world coordinates;
- elevation, movement cost, cover height, line-of-sight blocking, occupant, zones, and connected traversal links.

**Show all map zones** draws deployment zones in faction colors, objectives in purple, and extraction zones in green. **Show traversal links** draws yellow lines between linked surfaces. Both layers can be toggled independently.

This inspector reads the authoritative `MapData` and does not change movement, combat, objectives, or replay state.

## Automated verification

Run:

```powershell
godot_console --headless --path . --script res://tests/debug_map_inspector_smoke.gd
godot_console --headless --path . --script res://tests/debug_tools_smoke.gd
```

The focused test covers authored metadata, generated-map seed and size, elevation inspection, zones, traversal links, and visibility toggles.

