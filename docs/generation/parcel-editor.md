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

The footprint grid is visual guidance. `MapData` compiled from explicit authored metadata remains authoritative for traversal, cover, line of sight and occupancy.

## Current boundary

This first slice is an inspection foundation. It does not yet move assets, undo edits, save drafts, publish content, certify visuals, or change runtime parcels. Those capabilities will be added one small slice at a time, starting with placement/history/draft persistence, only after this inspection workflow is comfortable.

The quarantined chunk drafts and tools remain untouched. No retired runtime generator, revision library, publication stack or certification database is a dependency of this editor.
