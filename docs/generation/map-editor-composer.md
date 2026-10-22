# Map Editor Composer

The Map Editor is a project-local development tool for inspecting generated layouts and authoring reusable module compositions. It uses the same registered components, placement constraints, Asset Lab calibrations, tactical writer, and presenter as runtime generation.

Launch composition mode with:

```powershell
godot_console --path . res://tools/map_editor.tscn -- 2202 custom_layout
```

The editor normally opens on **Environment — Industrial District**. Choose **Editable — Custom Layout** to author. Legacy component demonstrations are deliberately hidden from this creative workflow; enable **Engineering fixtures** when a traversal, structural, or compatibility fixture is needed.

To use a generated or authored map as a starting point, display it first and click **Edit copy**. The editor copies its module placements into the custom working composition and leaves the source preset unchanged.

## Authoring workflow

1. Choose a component from the **Map Composer** panel. Entries show their family and logical grid size. The normal list favors reviewed assets and reusable authored assemblies; **Engineering fixtures** also reveals loose legacy structure fragments.
2. Choose a 90-degree rotation and visual variant.
3. Click an empty grid cell to place the component. The component origin snaps to that cell.
4. Click a component to select it. Its thin amber outline and status line show its component ID, origin, rotation, and variant.
5. Use the arrow keys to move it one cell, `Q` / `E` to rotate it, or `Delete` to remove it. The panel buttons provide the same rotate and delete actions.
6. Press `Ctrl+S` or **Save** to write the composition. **Reload** discards unsaved edits and restores the saved file. **Clear** clears only the working composition until it is saved.

Camera controls remain available while composing: right-drag orbits, middle-drag pans, the wheel zooms, `F` frames the map, and `1`, `3`, and `7` select standard views.

## Saved format and validation

When no custom file exists, the tool opens a small tracked starter composition. The first save writes your editable layout to:

```text
tools/map_editor/layouts/custom_layout.json
```

The starter remains unchanged at `tools/map_editor/layouts/starter_layout.json`, so **Reload** always has a useful fallback after the custom file is removed or renamed.

The JSON is a versioned persistence envelope containing the unified battlefield layout document. It preserves environment identity; authored, generated, or edited provenance; the original generator seed and configuration; map size; stable placement IDs and transforms; assembly and parcel relationships; pinned asset/calibration/assembly dependencies; mission zones; and presentation mode. It does not copy generated meshes, the full asset catalog, or compiled `MapData` internals.

Loading is transactional. The complete document is parsed, its schema and references are checked, dependencies are resolved, placements are reconstructed, and mission data is validated before the editor replaces its working document. A missing required asset, stale calibration or assembly certification, unsupported version, broken relationship, or malformed file leaves the current composition untouched and reports the affected field or identity.

The tracked starter still uses the old schema-1 placement format so compatibility remains continuously exercised. That format did not store environment identity, provenance, relationships, dependencies, or mission zones. It therefore loads only under the visibly labeled `legacy_compatibility` identity and remains dirty until the user explicitly saves it as the current format. The original file is never rewritten during load.

Every edit rebuilds the candidate through `EnvironmentModuleLayout`. Out-of-bounds placement, same-layer overlap, clearance intrusion, unsupported rotation, and visual-envelope conflicts are rejected before they reach the saved composition. Ground modules and compatible occupants may share cells by design.

Asset Lab calibration continues to control presentation scale, yaw, anchor, and visual offset. Component definitions continue to control authoritative movement, cover, line of sight, traversal, and suitability. Editing one does not silently rewrite the other.

The current composer saves one working layout. Named composition libraries, copy/paste, undo/redo, drag placement, socket visualization, and direct promotion of a selection into a procedural parcel template are natural follow-up tools.
