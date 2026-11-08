# Parcel Editor

The Parcel Editor is FuseFire's small authoring companion for the registered 16×16, 16×32 and 32×32 parcel scenes. It is intentionally not the retired Map Editor, a second game engine, or a procedural generator.

## Open it

Start FuseFire normally, open the **Settings** tab in Match Setup, and choose **Open Parcel Editor**. Use **Back to Match Setup** to return.

For direct development launch:

```powershell
godot_console --path . res://tools/parcel_editor/parcel_editor.tscn
```

## Inspect a parcel

Choose a registered parcel from the list. The editor opens on **Inspect** with the parcel size and validation visible. Expand **Technical details** for the stable ID, role, revision, service interface and population regions. The parcel picker, camera controls and draft status stay above the task tabs.

- Right mouse drag: orbit.
- Middle mouse drag: pan.
- Mouse wheel: zoom.
- `F` or **Frame**: frame the complete parcel.
- **Top** and **Oblique**: repeatable review views.
- **Show authored movable population**: isolate the fixed assembly from deterministic container/vehicle sockets when the parcel supports them.
- **Show tactical contracts**: inspect gameplay authority separately from imported meshes. Cyan marks elevated/access contracts; orange marks explicit tactical solid volumes.

## Make a visual draft

Open **Move objects** and click a visible imported object in the viewport, or choose it from the list. Drag with LMB to preview its position on its current floor in half-cell steps. Release in the viewport to commit a single undo step. Press `R` for a quarter-turn, `Shift+R` for the reverse, and `Esc` to cancel an active drag. The outline and labeled axes also match the X/Y/Z nudge buttons, which provide half-cell horizontal and quarter-cell vertical steps.

Blue means the visual candidate fits the parcel and clears other authored solid boxes. Red identifies an out-of-bounds footprint or a solid overlap. An invalid drop restores the starting pose. Rotation and nudges use the same checks. **Compare authored tactical bounds** shows the original gameplay volumes beside the visual draft. This check covers visual bounds and authored solid overlaps in 3D. Floor support, deliberate stacking, doors and tactical routes need their own authoring contracts.

**Save visuals** and **Load visuals** use the displayed parcel-specific file under `user://parcel_drafts/`. Replacing an existing quick-save file asks for confirmation. **Save visuals as…** chooses a separate file, and **Open visual draft…** opens one. A draft records the source parcel ID and exact revision, stable scene-node paths, asset IDs and visual transforms. It is rejected when the registered parcel revision, node identity or asset identity has changed.

Saving does not edit the `.tscn`, publish content, change tactical metadata or affect a battle. The preview deliberately leaves cyan/orange tactical contracts in their authored locations so a visual/tactical disagreement is visible instead of silently changing gameplay.

The footprint grid is visual guidance. `MapData` compiled from explicit authored metadata remains authoritative for traversal, cover, line of sight and occupancy.

## Population field drafts

Open **Population fields** and choose a surface or floor. **Inspect** leaves the scene in camera mode. **Paint** exposes the Parking, Containers, Equipment and Protected presets. Drag with LMB and watch the outline and cell dimensions update before releasing. **Erase** removes the topmost matching field on click. The legend distinguishes periwinkle permission fields, coral protected fields, gold bays and green aisles. The selected floor receives the stroke even when another floor is visible above it.

Set Seed and percentage of eligible bays, then **Preview**. This shows compatible occupants whose footprints fit within the painted permission areas and avoid protected areas. The result counts authored sockets filtered out by the paint separately from overlap conflicts. Parking can use authored sockets and new parking rows. Containers and equipment use authored sockets. **Show source** restores the authored population. **Undo field** and **Redo field** affect only the field draft. `Ctrl+Z` and `Ctrl+Y` follow the active editing tab. Preview requires source visual transforms.

### Paint parking and preview

Parking paint now defines where vehicles are allowed. The editor derives one contiguous row per painted floor from 3 × 5 bays and a four-cell aisle. It checks existing sockets, authored solids, protected paint and headroom. **Next seed** previews another outcome using the same paint. Density controls occupancy of eligible bays.

On the original office parcel, paint X 2–29 and Z 4–11 and preview at 100%. The editor finds four bays alongside the three authored sockets. **Export parking scene** validates the full layout and writes a separate scene containing the possible bays. It retains the original authored sockets and fixes a calibrated vehicle type for each new bay at export. A battle seed chooses which bays are occupied and which direction cars face. Replay records the resolved choices in its existing manifest.

To play the registered proof, select **Urban family** in Match Setup, enable **Tactical Population**, and use an even seed to choose the service-street plot. Seeds **0** and **2** were checked in the battle scene and occupy different new bays. Fresh street battles use the painted parking variant. Exact older manifests can still resolve the original office parcel. The battle seed is chosen through Match Setup and stays fixed for that encounter.

### Override a parking row

1. Paint Parking permission over the intended bays and Protected over access space you want to keep empty.
2. Choose **Parking row** once the selected floor has Parking permission, then use the green ground arrow to check the aisle direction before drawing. **Top** view makes the grid easier to read.
3. Drag along the edge of the row that faces the aisle. The tool fits whole 3 × 5 cell bays behind that edge and checks a four-cell-deep aisle on the chosen side. Gold outlines mark fitting bays, red marks rejected bays, and green marks the aisle.
4. Press **Preview** to see seeded vehicle models, occupancy, and forward/reverse headings. **Save fields** stores the row and heading with the painted fields. Erase a row by clicking within its bay outline in **Erase** mode.

The office lot demonstrates four extra bays. Paint X 2–29 and Z 4–11, then drag along Z 10 from X 13 to 24 with **Aisle toward +Z**. The result fits seven cars at 100% occupancy, including the original three. The 3 × 5 bay and 2.5-cell headroom are initial editor dimensions checked against the calibrated sedan, SUV and taxi. Existing sockets reserve their space, and new bays avoid fixed solids, named deck slabs and other rows' aisle space. Aisle checks establish geometric clearance. Access to the wider road network and vehicle turning remain outside this proof.

Editor camera: RMB drag down raises the view toward overhead, up lowers it, matching the battle camera's vertical orbit preference. Horizontal orbit and MMB pan retain their controls.

**Save fields** and **Load fields** use the displayed parcel-specific file under `user://parcel_fields/`. Replacing an existing quick-save file asks for confirmation. Use **Save fields as…** and **Open field draft…** for separate drafts. Files record parcel revision, surface geometry, fields and preview settings. Invalid or stale loads preserve the current draft. The header names the draft with unsaved changes. Switching parcels or returning to Match Setup asks before discarding those changes.

### Export a parking scene

Use **Export parking scene** after checking the inferred or manually drawn row. The tool checks every bay and compiles the fully occupied parcel. The whole entrance span and each aisle must remain walkable, with a tactical route from the entrance to the aisle on its declared floor. These checks run for all supported parcel rotations. The export preserves original authored sockets and rejects protected paint that would conflict with them. Visual transform drafts must be restored to source transforms first.

The result is a separate `.tscn` in `user://parcel_exports/`. The status shows its full path. It contains the original parcel and explicit, optional row sockets with the calibrated vehicle and authored tactical volume at each bay. The seed chooses the models baked into the new sockets. The preview occupancy slider affects the preview only. Authored sockets retain their normal runtime occupancy and forward/reverse options. The filename identifies the resulting content, and an existing export is preserved. Review the scene in the source project before registering it in the parcel catalog.

## Current boundary

The active editor inspects registered parcels, supports visual transform and population-field drafts with bounded history, and exports validated parking scenes for manual review. Runtime registration and mission certification are separate steps.

The quarantined chunk drafts and tools remain untouched. No retired runtime generator, revision library, publication stack or certification database is a dependency of this editor.
