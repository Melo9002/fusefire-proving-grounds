# Parcel Editor

The Parcel Editor is FuseFire's small authoring companion for the registered 16×16, 16×32 and 32×32 parcel scenes. It is intentionally not the retired Map Editor, a second game engine, or a procedural generator.

## Open it

Start FuseFire normally, open the **Settings** tab in Match Setup, and choose **Open Parcel Editor**. Use **Back to Match Setup** to return.

For direct development launch:

```powershell
godot_console --path . res://tools/parcel_editor/parcel_editor.tscn
```

## Inspect a parcel

Choose a registered parcel from the list. The left panel reports its stable ID, functional role, standard footprint, revision, service interface and catalog validation.

- Right mouse drag: orbit.
- Middle mouse drag: pan.
- Mouse wheel: zoom.
- `F` or **Frame**: frame the complete parcel.
- **Top** and **Oblique**: repeatable review views.
- **Show authored movable population**: isolate the fixed assembly from deterministic container/vehicle sockets when the parcel supports them.
- **Show tactical contracts**: inspect gameplay authority separately from imported meshes. Cyan marks elevated/access contracts; orange marks explicit tactical solid volumes.

## Make a visual draft

The **Visual placement draft** list contains imported visual nodes already authored in the selected parcel. Choose one, then use the X/Z/Y and yaw controls to adjust its preview transform. Half-cell horizontal steps, quarter-height vertical steps and quarter-turn yaw keep routine edits legible. **Undo**, **Redo** and `Ctrl+Z`/`Ctrl+Y` operate only on this draft.

**Save draft** writes `user://parcel_drafts/<parcel-id>.draft.json`; **Load draft** validates and restores it. A draft records the source parcel ID and exact revision, stable scene-node paths, asset IDs and visual transforms. It is rejected when the registered parcel revision, node identity or asset identity has changed.

Saving does not edit the `.tscn`, publish content, change tactical metadata or affect a battle. The preview deliberately leaves cyan/orange tactical contracts in their authored locations so a visual/tactical disagreement is visible instead of silently changing gameplay.

The footprint grid is visual guidance. `MapData` compiled from explicit authored metadata remains authoritative for traversal, cover, line of sight and occupancy.

## Population field drafts

Scroll to **Population Fields / Draft**. Select a surface/floor and a Parking, Containers, Equipment or Protected preset. Select **Draw field**, then drag LMB across cells; select **Erase field** and click to remove the topmost matching field. Cyan marks permitted regions; red marks protected regions. RMB/MMB/wheel still control the camera. The selected floor's plane receives the stroke even if another floor is visible above it.

Set Seed and occupied percentage, then **Preview**. This version filters compatible population sockets already authored in the parcel; it cannot add assets to an empty field. A permitted field must contain the occupant's authored tactical footprint, while any protected overlap excludes it. Manual fixed content remains visible. **Reset** restores source population. Field Undo/Redo is separate from visual placement Undo/Redo. Preview requires unchanged source visual transforms.

**Save fields / Load fields** use `user://parcel_fields/<parcel-id>.fields.json`, recording parcel revision, surface geometry, fields and preview settings. Invalid/stale loads preserve the current draft. Switching parcels resets unsaved fields, so save first. Field drafts are editor previews: they do not publish source scenes, change battles, or certify mission/access/count requirements. Runtime publication and new-socket authoring remain future work.

## Current boundary

The active editor inspects registered parcels and supports visual transform and population-field drafts with bounded history. It does not yet add or remove source assets, edit tactical contracts, write source scenes, publish content, certify visuals, or change runtime parcels. Those capabilities should be added only when a real authoring task demonstrates the need and can preserve this boundary.

The quarantined chunk drafts and tools remain untouched. No retired runtime generator, revision library, publication stack or certification database is a dependency of this editor.
