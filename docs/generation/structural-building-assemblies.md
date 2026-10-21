# Structural Building Assemblies

FuseFire distinguishes three levels of environment authoring:

1. **Assets** are imported meshes with calibrated visual transforms. They do not define gameplay.
2. **Modules** are reusable tactical and visual components with footprints, effects, sockets, clearance and presentation references.
3. **Building assemblies** are parcel-sized architectural contracts composed into one reusable module. They state whether a structure is closed, intentionally open, or a sealed prebuilt shell and validate entrances, usable floor and roof coverage.

`EnvironmentBuildingDefinition` owns the structural contract. `IndustrialBuildingCatalog` owns the first authored assemblies and exports their modules into `IndustrialModuleCatalog`. The procedural parcel grammar therefore places a validated building or shelter as a unit; it no longer infers a building from nominally compatible façades.

## Why the old Factory assembly failed

The source bounds in `tools/asset_lab/native_bounds.json` show that `structure-wall`, `structure-window-wide`, and `structure-doorway-wide` are 3 m tall and 2 m deep at native scale. At the reviewed presentation scale of 2 they are approximately 6 m tall and **4 m deep**. The former 10×10 service building treated eight of these as thin perimeter panels. Their deep volumes overlapped at the corners, while four 4×4 roof tiles covered only an 8×8 region. Logical compatibility could not make that geometry into a sound building.

The individual Factory pieces and their calibration remain unchanged for authored experiments. The procedural service shop now uses exact derived Godot box meshes for its shell. This gives its walls, roof and entrance one shared dimensional contract while preserving the original imported library as reference. Derived boxes are presentation-only; the associated module still authors every blocked, traversable, cover and line-of-sight cell explicitly.

## Initial assemblies

### Service building

- 10×10 parcel and tactical footprint.
- Closed enclosure with a fully assigned perimeter.
- One four-cell street entrance with exterior and interior access sockets.
- 8×8 usable interior floor.
- Roof coverage over every usable interior cell.
- Exact wall, floor, roof, window-panel and entrance-lintel geometry.
- Spawn and objective suitability inside the building.

The generator rotates the entire assembly toward its parcel's road edge. The entrance, tactical effects, sockets and geometry rotate together.

### Loading canopy

- 8×6 parcel.
- Explicit `open_shelter` enclosure intent.
- Four blocking supports and open usable floor between them.
- Roof coverage over the loading space.
- Loading sockets and an objective-suitable covered area.

Because openness is part of its contract, the missing walls are valid architecture rather than an incomplete building.

### City Industrial shells

- Twenty per-asset sealed tactical footprints derived from calibrated bounds rather than one shared 14×14 estimate.
- Complete vendor-authored exterior models with reviewed working faces.
- A normalized local `+Z` frontage and three-cell placement-clearance apron.
- Explicit `prebuilt_shell` status.
- No claimed interior, doorway or walkable floor.

This keeps the useful exterior massing without pretending that a closed GLB contains playable rooms. Thirteen profiles fit the current 20×20 procedural frontage parcel; the remaining large profiles stay registered for future campus parcels.

### Certified building-i shell

`city_industrial_shell_i` is the first shell promoted from reviewed building metadata to a reusable certified assembly. Its `EnvironmentAssemblyContract` binds the existing building definition to:

- the stable `city_kit_industrial/building-i` asset ID and one required shell component;
- the source-to-module transform that turns the reviewed model-local `-Z` face into module-local `+Z`;
- the current GLB SHA-256 and a fingerprint of scale, anchor, corrective yaw and native bounds;
- the resolved 10.281378 × 7.335410 × 13.000001 visual envelope;
- an explicitly authored 11×13 solid tactical footprint;
- a six-by-three exterior frontage apron;
- all four canonical quarter-turn orientations; and
- `complete_exterior`/`sealed_building_shell` classification.

The tiny excess above 13 in the imported floating-point Z extent is treated as measurement noise for the 13-cell tactical reservation; the exact visual extent remains preserved. The entrance and garage door establish an exterior frontage relationship only. They do not create a walkable interior.

Certification is intentionally pinned. Changing the GLB, resolved calibration, component transform, footprint, envelope, frontage, clearance or supported rotations makes validation fail. Other reviewed City Industrial shells continue to use their existing placement profiles but are not implicitly certified by this first record.

## Validation rules

A closed building is reusable only when:

- every perimeter cell is assigned to a wall or entrance;
- at least one entrance exists on the boundary and leads inward to usable floor;
- wall cells are blocked by the associated tactical module;
- usable floor does not overlap walls;
- every usable floor cell has authored roof coverage; and
- the structural parcel and exported module have the same size.

Open shelters validate usable floor and roof coverage but do not require enclosure. Prebuilt shells require identified source assets and remain sealed unless a separate interior contract is authored.

These checks establish structural completeness. They do not prove artistic quality, door animation, roof cutaway behavior, furnishing, or play balance. Those still require rendered inspection and tactical testing.

## Inspecting and authoring

Launch the Map Editor from the project root:

```powershell
godot --path . res://tools/map_editor.tscn -- 2202 building_gallery
```

Choose **Authored — Building Gallery** to compare the closed service shop, open loading canopy and sealed City Industrial shell. Left-click any assembly to select it. Right-drag orbits, middle-drag pans, the wheel zooms, and `1`, `3`, and `7` switch to front, side and overhead views. The selection readout reports the assembly ID, enclosure kind and architectural purpose.

The assembly-view buttons provide three diagnostics:

- **Complete** restores the ordinary environment.
- **Shell** isolates the selected assembly and shows only walls, supports, floors, roofs, and other structural visuals.
- **Decor** keeps the assembly isolated but shows only separable trim, window panels, signs, and similar decorative visuals.

Visual roles belong to individual presentation entries in the building definition. A future derived scene can therefore expose its shell and decoration without changing tactical cells. Monolithic vendor buildings currently appear wholly in **Shell** because their source GLB does not separate decorations into reusable nodes; the editor does not pretend it can isolate geometry that the asset does not expose.

The transparent UI surface deliberately passes mouse events to the 3D view; buttons and fields remain interactive. If camera input is tested after UI changes, verify both selection and orbit in open viewport space.

For a repeatable front, side, back and overhead capture of every gallery assembly, run this explicit rendered check with a writable output directory:

```powershell
godot --path . --script res://tests/structural_building_capture.gd -- artifacts/structural-buildings
```

To author another reusable building:

1. Add an `EnvironmentBuildingDefinition` to `IndustrialBuildingCatalog`.
2. Choose its purpose, parcel size and enclosure intent.
3. Record wall, entrance, usable-floor and roof cells.
4. Add entrance directions and semantic module connections.
5. Author tactical effects independently of visual geometry.
6. Add calibrated asset references or exact derived visuals.
7. Run `validate()` and add the assembly to the building gallery before allowing procedural parcels to select it.

For a certification-ready imported shell, also attach an `EnvironmentAssemblyContract`, pin its resolved dependencies, name its frontage/access relationship, and add both positive and negative validation cases. `IndustrialBuildingCatalog.certified_assemblies()` exposes only records whose current dependencies and spatial contract still validate.

The focused automated check and clean rendered inspection are:

```powershell
godot_console --headless --path . --script res://tests/certified_building_assembly_contract_test.gd
godot_console --path . --script res://tests/certified_building_shell_capture.gd -- artifacts/certified-building-shell
```

## Current limits

- The service shop has one rectangular floor and no furnished interior.
- Roofs do not yet participate in gameplay-driven cutaway groups.
- The City Industrial shells remain exterior-only.
- Individual Factory structure blocks remain useful authoring pieces, but their four-metre visual depth at scale 2 requires a native-pitch assembly larger than a single 10×10 parcel.
- Structural validation checks authored topology and tactical correspondence. Rendered multi-angle review remains required for visual quality.
