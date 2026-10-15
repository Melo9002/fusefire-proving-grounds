# Industrial Warehouse Vertical Slice

## Architecture and configuration

Select **Special — Industrial Warehouse (40 × 30)** in match setup. This is a fixed authored site; the seed controls deployments and mission placement. Commander policies and tactical rules remain shared with other maps.

`FlatMapGenerator` creates base cells and deployments; `IndustrialWarehouseLayoutBuilder` marks authoritative obstructions and the raised platform; `GeneratedTraversalBuilder` connects the platform; `MissionZonePlanner` populates objectives after graph construction. `MapValidator` checks the resulting graph. `GeneratedTerrainPresenter` and `IndustrialWarehousePresenter` render it. Imported meshes never supply movement or shooting legality.

## Implemented visual pass

- Continuous warehouse shell with a four-cell loading entrance, north entrance, two side entrances, and dispatch signage.
- Flat walkable service roof at elevation 5, with an exterior ladder on the east side; 5-unit walls clear the 2-unit-high maintenance platform and standing MIRAs.
- Separate asphalt roads, concrete production floor, loading apron, road markings, and cargo/crane exclusion outlines. TAB retains its existing grid toggle.
- Three long containers, each reserving a 5×2 footprint and 1.87-unit cover height. Nearby low-cover cells do not overwrite container footprints.
- Machinery on solid service plinths, conveyor workstations, loading crane, and an elevated maintenance platform using existing deck, railing and ladder presentation. No decorative catwalk meshes obstruct the deck.
- The miniature decorative building is absent. Walls, cargo and machinery use blocked grid cells; low barriers retain existing traversable-but-not-stoppable low-cover semantics.

The imported subset uses City Kit Industrial containers and Factory Kit machinery, conveyors and crane. Vendor GLBs are untouched. Shared `EnvironmentAssetPlacement` code accumulates **all ancestor transforms**, measures rotated bounds, applies **one uniform scale**, centers the model in its reserved envelope and aligns its lowest point to the floor. It does not stretch axes independently. The shell and roof are simple FuseFire-owned procedural geometry.

The screenshot helper stages one MIRA visual at the loading entrance for scale comparison; it is not an added combatant or a gameplay change.

## Camera cutaway contract

`WarehouseRoofCutaway` controls presentation of a real walkable roof. The layout owns 234 roof surface cells and a separate thin non-walkable ceiling slab at world height 4.75–5.0, which blocks shots through the ceiling while preserving the interior. The roof collider supports existing mouse picking; hiding the roof never removes its collision or tactical cells. `TacticalCamera` supplies its existing selected-unit or cinematic actor/target focuses:

- Hide the roof when a focus or the camera is inside its interior volume, or the roof bounds intersect the camera-to-focus segment.
- A rooftop focus keeps the roof visible, taking precedence over an interior cutaway. Restore it when cutaway conditions clear. Elevated maintenance-platform occupants remain inside the interior volume.
- Fade opted-in warehouse walls and imported props to 82% transparency if they intervene between camera and focus. Restore each mesh's original transparency afterward.
- Keep the existing physics-based occlusion for ordinary terrain. The new opt-in `TacticalVisualOccluder` fills the gap for scenery without physics colliders.
- Restore presentation on camera removal. No camera ownership, turn state, RNG, cover, AP or replay fingerprints are changed by visibility.

This is focus-based visibility, not a rule that globally hides a building whenever **any** unit enters. Cinematics can use both actor and target. Bounds are conservative, so a sparse crane may fade even when its open gaps would permit a view. Fades currently switch immediately; temporal smoothing and broader scenery coverage remain future work. This does not claim to solve every camera obstruction on other maps.

### Floor inspection — implemented narrow integration

A persistent **VIEW** panel shows the inspected level and provides **Ground / Walkway / Roof** buttons. The existing **Alt + wheel** picker also cycles roof, maintenance deck and ground where their collider surfaces overlap under the cursor. On this map, the camera follows that inspection choice and destinations prefer the inspected floor, so hidden roof collision cannot silently steal an interior click. Inspection is a height ceiling: if no eligible lower tile exists, return no destination instead of falling back upward. Higher-level unit clicks are filtered too. Explicit Roof inspection permits rooftop picking, but AP, path reachability and action legality remain owned by the action service. Selecting a different actor or moving the actor clears the manual override; a selected rooftop actor selects rooftop height automatically. Other map presets retain their previous picker behavior.

The panel derives its buttons from authoritative walkable elevations and uses optional `MapData` labels (`Ground`, `Walkway`, `Roof` here). General multi-building membership and visual layer filtering for all units remain future work. No full floor-management framework was added.

### Local XCOM 2 SDK evidence

Inspected the installed War of the Chosen SDK under `C:/Program Files (x86)/Steam/steamapps/common/XCOM 2 War of the Chosen SDK/Development/SrcOrig/XComGame/Classes/`:

- `XComFloorVolume.uc`: floor volumes carry reveal/cursor roles, actor inclusion/exclusion lists, floor numbers and camera-to-cursor occlusion settings. `ContainsValidUnit()` filters eligible, visible, living occupants.
- `XComBuildingVolume.uc`: building floors cache participating geometry and external mesh groups separately from gameplay floor data.
- `XComBuildingVisManager.uc`: prioritized focus points, floor reveals and separate cutout/periphery systems. Core floor-hiding routines are native declarations; their C++ bodies were not inspected.
- `X2Camera_FrameAbility.uc:144`: moving-actor framing explicitly restricts cutdown subjects to avoid cutting away the floor under that actor.
- `XComCutoutBox.uc:44`: cutout updates remove ignored actors from the prior camera's touched list and restore their dither state.

The useful lesson is explicit floor membership and focus priority, plus reliable restoration. FuseFire uses small opt-in presentation nodes and its existing grid/ladder/picker; it does not reproduce XCOM's volume manager or shader system.
## Replay boundary correction discovered during validation

A new full industrial Reach playback exposed an existing mismatch also reproduced with the warehouse disabled: the final Move recorded completed objective progress while the battle result remained ongoing; deferred outcome evaluation ran during presentation, so replay compared against Victory.

Move now calls the existing `ObjectiveManager.evaluate_outcome_after_action_commit()` after movement lifecycle callbacks and before emitting its record, matching Attack's existing synchronous outcome boundary. Mission success criteria are unchanged. New industrial Reach recordings verify all 30 actions.

The preset is serialized as `industrial_warehouse`; absent fields default to false. No replay envelope/action schema changed. Ordinary replay fixtures remain regression checks. Recordings from the earlier uncommitted industrial layout are not layout-compatible with the changed cargo/wall geometry. Old Reach recordings containing the demonstrated transient final-state mismatch are not migrated by this fix; they already failed full playback.

## Reproducible checks and visual inspection

Run from the project root with the project's Godot executable:

```powershell
godot_console --headless --path . --script res://tests/industrial_warehouse_vertical_slice_smoke.gd
godot_console --headless --path . --script res://tests/industrial_warehouse_ai_smoke.gd
godot_console --headless --path . --script res://tests/camera_obstruction_test.gd
godot_console --headless --path . --script res://tests/industrial_roof_movement_test.gd
godot_console --path . --resolution 1440x900 --script res://tests/industrial_warehouse_capture.gd -- C:/path/to/captures
```

The capture helper launches the real renderer and saves overview, loading, interior, MIRA-scale and level-interface PNGs. It disables the gameplay camera, hides UI/grid for inspection, and explicitly selects exterior/cutaway views; it is a visual inspection tool, not a simulation test. The automated camera test separately exercises camera-driven fading/restoration, including existing physics occlusion and cinematic focuses.

Layout tests check deterministic construction, connected deployments, objective zones, solid prop footprints, rotated imported bounds, uniform scaling, floor alignment and roof/wall restoration. The AI test requires actual Reach completion and complete replay verification, rather than merely accepting a non-stalled round limit.

## Known limitations / next useful work

- Fixed layout, not procedural district assembly. Playtest this site before extracting modular bays and adjacency rules.
- Roads and outer deployment areas remain very open. Map-quality score 43 and 84% open area are limitations, not a quality gate passed by appearance alone.
- Crane footprint is a conservative solid 3×4 obstruction, including space between its legs. Its painted exclusion area makes the reserved region visible; precise crane traversal/LOS is not implemented.
- Shell/header detail remains simplified. The flat roof deliberately matches the walkable plane; pitched walkable geometry would need separately authored surface heights. The roof is exposed, without new rooftop cover props.
- Generalized multi-building floor UI, smooth occlusion transitions, automatic hiding for every indoor occupant, authored asset modules and richer cargo composition are deferred.


## Validation results (2026-10-14)

- `industrial_warehouse_vertical_slice_smoke.gd`: 0 failures, seeds 1 and 940059876; 1,692 cells and two ladder links validate.
- `industrial_roof_movement_test.gd`: 0 failures; authoritative climb/descent, one-AP climb, roof retention, lower-floor cutaway, real collider picking, UI labels, and rejection of implicit upward tile selection.
- `industrial_warehouse_ai_smoke.gd`: Normal Reach 3v3, seed 940059876, Victory in 2 rounds / 26 decisions; full playback verifies 30/30 actions.
- `camera_obstruction_test.gd`, `tactical_camera_selection_test.gd`, `action_camera_director_test.gd`, `elevation_selection_smoke.gd`, `elevation_combat_smoke.gd`: 0 failures.
- `tactical_action_service_test.gd`, `replay_schema_test.gd`: 0 failures.
- `battle_replay_smoke.gd`: 41/41 actions verified; `rescue_battle_replay_smoke.gd`: 286/286 verified.
- `generated_mission_placement_smoke.gd`: 80 maps, 0 failures (existing generated-map coverage, not 80 warehouse missions).
- `prototype_1_milestone.gd`: 15/15 matches completed, 0 issues. The final floor-picker/UI additions were additionally checked with the roof, elevation-selection, camera and industrial replay tests.
- Godot 4.7.2 editor import: exit 0, no script parse errors. Sandboxed runs report Windows root-certificate-store access and editor-settings write errors; these are environment limitations. Actual D3D12 rendering and screenshot capture succeeded.
- `git diff --check`: passed. No commit or push performed.

The original Reach replay regression was reproduced on both warehouse and ordinary generated maps before the synchronous Move outcome correction. Its assertion was retained and now passes; no replay comparison was weakened.
