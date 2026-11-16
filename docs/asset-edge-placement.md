# Asset edges, standing positions and hybrid animation

Prototype foundation, 2026-11-16. **The intended direction is grid identity plus geometry-based standing points, not perfectly grid-aligned assets.** This is an experiment with an explicit fallback: if it cannot give reliable movement, LOS and replay at reasonable cost, use grid-compliant assets inside the combat area. Surroundings can remain unrestricted.

## The requested behavior

In the container example, the usable space and cover contact should follow the container's actual side. A tile partly overlapped by an object may still contain a safe standing point. The actor should stand there, close to the surface, rather than stand at the tile center or be visually pushed while gameplay stays behind.

There is no rule that “half a tile is always usable.” A body of the chosen width must fit in real space, including neighboring space and other units, and have a traversable route to that point. Animation cannot make an undersized gap physically valid.

The grid can still identify the occupied tile and keep existing turn/AP structure. The physical standing point becomes the shared position for movement, targeting, cover, range and LOS. First aim for **one canonical point per cell**; multiple poses/positions per tile are a later decision, not a requirement for this first experiment.

## What exists now

| Foundation | Status |
| --- | --- |
| `systems/grid/surface_placement.gd` | Pure, bounded body-fit search against supplied world-space boxes; returns a proposed point and a clear failure reason. Separately returns surface contact, outward direction and desired body clearance. No map, actor or occupancy mutation. |
| Existing `tactical_pose_context.gd` | Authored-pose selection now reads actual nearby part bounds and exposes contact hints. An empty label alone no longer supplies a pose. |
| Existing `UnitVisualAdapter` | Exposes `last_cover_contact` and uses the existing low/high-cover clips and weapon-grip IK. It does **not** apply the proposed root offset. |
| Surface Fit Lab | Isolated slider demo with a MIRA placeholder, body-fit/contact markers and a diagnostic LOS ray from the resolved point. |
| Live battles | Conservative grid movement remains in place. Partly blocked cells are **not unlocked** by this foundation. No new peek, crouch, navigation or replay rules are active. |

The body proxy starts at radius 0.28, height 1.8 and horizontal clearance 0.04 world units for a one-unit tile. These are prototype parameters, not measurements guaranteed to fit every character or weapon. A search is limited to 32 local parts and 256 tested points; exceeding those limits reports failure. The candidate set is conservative: failure means no tested fit, not proof that no continuous solution exists.

Bounds still come from the existing automatic per-mesh boxes. This does not recover holes inside a single concave mesh or produce exact polygon collision. No per-asset hull fitting, tactical-role assignment or boundary export is added.

## Why LOS must be part of it

Combat already reads actual `MapData` surface positions, including XYZ offsets. The path graph also stores world positions. However, many movement/presentation consumers still convert cells back to their centers, and ordinary shots currently skip the source/target navigation cells' geometry. That assumption must change when those cells may themselves contain part of an object.

The lab therefore indexes the object independently of navigation, using the existing shot-only index. Its ray tests do not ignore a solid merely because it overlaps the starting tile. At the default setting, the old-center ray is blocked while the resolved-point ray clears the edge. **This is one diagnostic geometry ray, not a complete legal attack, path, Guard or replay validation.** The lab deliberately leaves its navigation cell blocked.

## Smallest next integration

| Order | Work before enabling partly occupied tiles |
| --- | --- |
| 1 | Derive a supported standing point from existing asset parts and a body profile; retain cell identity. Reject cells without a fit. Do not move the asset to suit the grid. |
| 2 | Validate swept body clearance between points, diagonal corners, floor support, entrances, ramps and other units. A safe destination alone does not prove a safe route. Bodies may extend across cell boundaries, so one-unit-per-cell occupancy is insufficient by itself to prevent neighboring bodies overlapping. |
| 3 | Make movement, previews, cover, range, five-sample LOS, Guard, spawning and mission interactions use the same point. Find nearby cover surfaces by actual distance/contact, including parts in the actor's own cell; do not keep a four-neighbor-only shortcut. Preserve independent obstacle geometry in source/target cells. |
| 4 | Version the compiler/simulation, reconstruct or record resolved points and include them in validation/fingerprints. Current cell-only state fingerprints are not enough to detect a changed within-cell position. Keep deterministic ordering and a defined precision. |
| 5 | Drive hybrid poses from the committed point and contact. Only then enable the workflow on a container, truck and building-edge example through real movement and saved replay. |

Keep this inside the current map/action/presentation path. There is no proposed second generator, free-movement engine or new manual asset workflow. This experiment does not require finishing the entire animation system before continuing the combat milestone.

## Authored plus procedural animation

Use authored clips for readable motion and timing: low-cover idle, rise-over-low-cover/fire/return, left-corner lean/fire/return, and right-corner lean/fire/return. Existing high-cover left/right shooting and cover clips are placeholders to reuse; a distinct rise-over-low-cover sequence is still future work.

Procedural fitting can then adjust contact height/direction, upper-body lean, feet on the supported surface and hand/weapon placement within bounded limits. Reuse the rig's existing IK instead of adding another rig. Wall-hand and foot contact solving are **not implemented** here. The gold marker is a target for future fitting, not a hand already attached to the wall.

Any actual peek firing origin must first be validated by the shared tactical query and used identically by UI, AI, execution, Guard and replay. A visual lean cannot invent a legal shot through a wall. Animation follows committed results; root motion must not silently change tactical position.

## What JA3's public code confirms

THQ Nordic publishes significant Lua source for modding. Its [cover code](https://github.com/THQNordic/JaggedAlliance3Modding/blob/main/Lua/Tactical/Cover.lua) contains explicit alignment checks, cardinal cover offsets and stance-dependent cover queries. Its [unit code](https://github.com/THQNordic/JaggedAlliance3Modding/blob/main/Lua/Tactical/Unit.lua) uses aim/look IK and passes positions and stance into cover queries. Its [combat paths](https://github.com/THQNordic/JaggedAlliance3Modding/blob/main/Lua/Tactical/CombatPath.lua) track positions, occupancy restrictions and destination stances. These support separating tactical placement from pose fitting; they **do not establish arbitrary mesh-edge standing or reveal the complete native collision/pathfinding implementation**. FuseFire's proposal is our design, not a claim to reproduce JA3 internally. Sources inspected read-only on 2026-11-16; no JA3 code/assets copied.

## How to test this foundation

Open `art/characters/mira_0/demo/surface_fit_demo.tscn` in Godot and press **F6** (run current scene), or run:

```powershell
godot_console --path . res://art/characters/mira_0/demo/surface_fit_demo.tscn
```

| Test | Expected result |
| --- | --- |
| Default slider **0.65** | Body fits. Standing X is **-0.17**, leaving a **0.04 body gap** before the face at X=0.15. Cyan marks the fit, red the old center and gold the contact. The authored cover placeholder faces the object. |
| Default LOS text/ray | **Old center blocked → resolved point clear**. The green ray starts at the resolved point's shot height. |
| Slider fully left, **0.00** | **NO FIT**; the character/contact markers hide instead of pretending animation can solve the collision. |
| Slider fully right, **1.20** | Body approaches the moved object: standing X **0.38**, still with a 0.04 body gap. Both rays may now be clear. |
| Intermediate positions | The finite search may choose a valid corner rather than fail. Some position jumps are expected in this geometric lab; smooth movement is not implemented here. |
| Normal Parcel Editor / battle | Existing movement restrictions remain. This delivery is not expected to make the screenshot's half-blocked tiles clickable yet. |

For the next slice to count as successful, play the same off-grid container at several offsets/rotations, approach both ends and a corner, compare destination previews with actual shots, put two soldiers in neighboring cells, and save/reopen its replay. Accept only if positions fit, travel does not clip, preview/execution agree and replay reconstructs the same points. Otherwise keep the conservative grid-compliant fallback.

Automated foundation: **64 geometric/contact checks** and **6 lab checks** passed. Tactical-pose, unit-visual-adapter, locomotion, action-presenter and directional-cover checks also passed. A rendered default view was inspected. No full movement/replay claim is made. The first lab rejection case incorrectly assumed a thin object left no corner fit; setting the obstacle across the entire cell correctly tests rejection without removing that assertion. A project scan parsed the scripts; Windows certificate-store and editor-settings-save diagnostics were environment issues, not tactical assertion failures.
