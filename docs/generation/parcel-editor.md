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
- **Show painted population guides** shows permission areas and empty placement outlines. Cars and containers that vary with the seed are hidden until Preview. Fixed structures stay visible.
- **Show tactical contracts**: inspect gameplay authority separately from imported meshes. Cyan marks elevated/access contracts; orange marks explicit tactical solid volumes.

## Make a visual draft

Open **Objects** to place new assets or select a visible object in the viewport or object list. Drag with LMB to preview its position on its current floor in half-cell steps. Release in the viewport to commit one undo step. Press `R` for a quarter-turn, `Shift+R` for the reverse, and `Esc` to cancel. The outline and labeled axes match the nudge buttons.

Use the fixed asset browser to search ground decoration or select a tactical template. **Place** shows a blue or red ghost as you move over the parcel. Click to place, use `R` to rotate, or press `Esc` to cancel. **Duplicate** starts another placement of a supported library asset. **Remove** works on standalone fixed objects. Add, duplicate, and remove share the visual undo and redo history. New tactical objects use existing authored volumes attached to their models. New placements are ground-level and check parcel bounds, solid overlap and the entrance.

The browser renders the selected calibrated asset above Place. **Bounds · selected object only** limits the tactical overlay to the selected fixed object and follows that object into combined Preview. Orange marks solids, and cyan marks floor and access contracts. Select **Bounds · all objects** for the full parcel.

Blue means the candidate fits the parcel and clears authored solids. Red identifies a footprint outside the parcel or a solid overlap. An invalid drop restores the starting pose. Rotation and nudges use the same checks. **Show current tactical bounds** displays attached gameplay volumes at the current transforms, including additions and removals. Floor support, deliberate stacking and physical door access still require authored contracts.

**Save visuals** and **Load visuals** use the displayed parcel-specific file under `user://parcel_drafts/`. Replacing an existing quick-save file asks for confirmation. **Save visuals as…** chooses a separate file, and **Open visual draft…** opens one. A draft records the source parcel ID and exact revision, stable scene-node paths, asset IDs and visual transforms. It is rejected when the registered parcel revision, node identity or asset identity has changed.

The fixed-object draft stores additions, removals and transforms. **Preview** includes these edits and compiles their attached tactical metadata into a temporary MapData. **Preview registered parcel** compares against the original layout. Both preserve your object and field drafts. **Export population scene** writes the current fixed objects and population rules to a separate scene for review and registration.

The footprint grid is visual guidance. `MapData` compiled from explicit authored metadata remains authoritative for traversal, cover, line of sight and occupancy.

## Population field drafts

Open **Population fields** and choose a surface or floor. **Inspect** leaves the scene in camera mode. **Paint** exposes the Parking, Containers, Equipment and Protected presets. Drag with LMB and watch the outline and cell dimensions update before releasing. **Erase** removes the topmost matching field on click. The legend distinguishes periwinkle permission fields, coral protected fields, gold bays and green aisles. The selected floor receives the stroke even when another floor is visible above it.

Permission strokes turn red over fixed tactical solids, protected cells, entrances, reserved aisles or beyond the selected floor. Releasing an invalid stroke leaves the draft unchanged. Paint Protected over areas that must stay clear. Empty placement guides can be painted over.

Set **Seed** and press **Preview** to see population together with your current fixed objects. A field draft controls permission and density. With no field draft, the registered population rules supply candidates, and conflicts with moved fixed objects produce an explicit error. Registered rules own their occupancy independently of draft density. **Preview registered parcel** compares the original scene. **Show guides** returns to editing. `Ctrl+Z` and `Ctrl+Y` follow the active editing tab.

### Paint parking and preview

Parking paint now defines where vehicles are allowed. The editor derives one contiguous row per painted floor from 3 × 5 bays and a four-cell aisle. It checks existing sockets, authored solids, protected paint and headroom. **Next seed** previews another outcome using the same paint. Density controls occupancy of eligible bays.

On the original office parcel, paint X 2–29 and Z 4–11 and preview at 100%. The editor finds four bays alongside the three authored sockets. **Export population scene** validates the full layout and writes the possible bay positions. The battle seed chooses occupancy, forward or reverse facing, and the calibrated model for each occupied new bay. Replay records those resolved choices.

To inspect the registered proof, open **Industrial office — seeded parking rules**. Preview here uses the same placement scope as the service-street office. To play it, select **Urban family** in Match Setup, enable **Tactical Population**, and use seed **0** or **2**. Both choose the service-street plot and occupy different new bays. Exact older manifests can still resolve the original office variants.

### Paint container storage

On **Warehouse loading apron**, paint ground cells X 7–9 and Z 20–29 with **Containers**. Preview at 100% fits two new positions. The tool fits up to four clear 3 × 5 positions in contiguous paint, using one calibrated container model and its authored tactical volume. It checks fixed obstacles, existing placements, protected areas and the entrance. Export checks ground connectivity at full occupancy in every supported rotation.

Gold outlines show fitting positions before Preview. Red outlines show rejected candidates, with a reason beside the preview controls. For example, paint X 2–4 and Z 21–25 and the existing `container_west` guide reserves that space. Empty guides retain their reservation so newly inferred positions cannot overlap a possible authored occupant. Smaller or disconnected paint reports that a contiguous 3 × 5 area is required.

Hover the fitting message to highlight the first rejected candidate in pink and its blocker in gold. Click the message to frame that pair. The temporary highlight clears when you leave the message. Container preview leads with the occupied count, and **Preview technical details** expands the underlying socket and exclusion counts.

**Warehouse loading apron — painted containers** is the registered proof. Its preview uses the Split-yard refinery loading slot's seed scope. In Match Setup, select **Refinery Family** and enable **Tactical Population**. The upper painted container position is occupied at seed **0** and empty at seed **12**. Other sites may resolve their loading slot differently.

### Override a parking row

1. Paint Parking permission over the intended bays and Protected over access space you want to keep empty.
2. Choose **Parking row** once the selected floor has Parking permission, then use the green ground arrow to check the aisle direction before drawing. **Top** view makes the grid easier to read.
3. Drag along the edge of the row that faces the aisle. The tool fits whole 3 × 5 cell bays behind that edge and checks a four-cell-deep aisle on the chosen side. Gold outlines mark fitting bays, red marks rejected bays, and green marks the aisle.
4. Press **Preview** to see seeded vehicle models, occupancy, and forward/reverse headings. **Save fields** stores the row and heading with the painted fields. Erase a row by clicking within its bay outline in **Erase** mode.

The office lot demonstrates four extra bays. Paint X 2–29 and Z 4–11, then drag along Z 10 from X 13 to 24 with **Aisle toward +Z**. The result fits seven cars at 100% occupancy, including the original three. The 3 × 5 bay and 2.5-cell headroom are initial editor dimensions checked against the calibrated sedan, SUV and taxi. Existing sockets reserve their space, and new bays avoid fixed solids, named deck slabs and other rows' aisle space. Aisle checks establish geometric clearance. Access to the wider road network and vehicle turning remain outside this proof.

Editor camera: RMB drag down raises the view toward overhead, up lowers it, matching the battle camera's vertical orbit preference. Horizontal orbit and MMB pan retain their controls.

**Save fields** and **Load fields** use the displayed parcel-specific file under `user://parcel_fields/`. Replacing an existing quick-save file asks for confirmation. Use **Save fields as…** and **Open field draft…** for separate drafts. Files record parcel revision, surface geometry, fields and preview settings. Invalid or stale loads preserve the current draft. The header names the draft with unsaved changes. Switching parcels or returning to Match Setup asks before discarding those changes.

### Export a population scene

Use **Export population scene** after inspecting the combined preview. It includes fixed edits and one population type per export. The tool checks the fully occupied parcel across supported rotations and keeps the entrance walkable. Parking adds aisle and approach checks. Container exports and fixed edits require ground stopping cells to remain reachable from the entrance. Existing authored sockets are preserved.

The result is a separate `.tscn` in `user://parcel_exports/`. The status shows its full path. It contains the original parcel, paint and the authored placement rules. At battle startup each accepted position gets its model and authored tactical volume. The filename identifies the exported rules, and an existing export is preserved. Review the scene in the source project before registering it in the parcel catalog. New equipment paint remains a preview tool for existing equipment positions.

The finishing sequence is visible beside Export. Save both drafts for later editing, export, and use **Open exported scene folder** to locate the scene. Open it in Godot for visual review, then copy the approved scene into the project's authored parcels and add its ID, role, size and revision to `AuthoredParcelCatalog`. Add it to a compatible plot slot or role candidate set and verify a battle before treating it as published content. Exported scenes have a new identity. Registration remains an explicit source-project step.

The checklist tracks saved drafts and whether the current composition matches its last export. Its next-step button opens the applicable save action, exports the current scene, or opens the exported scene folder. Edits mark an earlier export as stale. Godot review and registration stay marked as manual steps.

## Current boundary

The active editor inspects registered parcels, supports fixed-object and population-field drafts, and exports validated parking and container scenes for review. Runtime registration and mission certification are separate steps.

The quarantined chunk drafts and tools remain untouched. No retired runtime generator, revision library, publication stack or certification database is a dependency of this editor.
