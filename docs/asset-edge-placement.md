# Asset edges, standing positions and hybrid animation

Prototype pilot, 2026-11-16. **Keep most assets grid-aligned for readability; use geometry-based standing points for tile-edge walls and occasional irregular objects.** The grid identifies the tactical choice. Real geometry decides where the body can fit. If an asset cannot give reliable movement and shots, keep a conservative blocked cell or use a grid-compliant combat asset. Surroundings remain unrestricted.

## The requested behavior

In the container example, the usable space and cover contact should follow the container's actual side. A tile partly overlapped by an object may still contain a safe standing point. The actor should stand there, close to the surface, rather than stand at the tile center or be visually pushed while gameplay stays behind.

There is no rule that “half a tile is always usable.” A body of the chosen width must fit in real space, including neighboring space and other units, and have a traversable route to that point. Animation cannot make an undersized gap physically valid.

The grid can still identify the occupied tile and keep existing turn/AP structure. The physical standing point becomes the shared position for movement, targeting, cover, range and LOS. First aim for **one canonical point per cell**; multiple poses/positions per tile are a later decision, not a requirement for this first experiment.

## What exists now

| Foundation | Status |
| --- | --- |
| `systems/grid/surface_placement.gd` | Pure, bounded body-fit search against supplied world-space boxes; returns a proposed point and a clear failure reason. Separately returns surface contact, outward direction and desired body clearance. No map, actor or occupancy mutation. |
| Existing `tactical_pose_context.gd` | Authored-pose selection now reads actual nearby part bounds and exposes contact hints. An empty label alone no longer supplies a pose. |
| `systems/grid/surface_navigation.gd` | Resolves supported cell points, checks swept body clearance, neighboring bodies and actual nearby cover contacts. One shared prototype body profile; deterministic box geometry. |
| Existing `UnitVisualAdapter` | Reads the committed standing point/contact, chooses the existing low/high-cover clips and retains weapon-grip IK. It does not invent a separate cosmetic root offset. |
| Surface Fit Lab | Isolated slider demo with a MIRA placeholder, body-fit/contact markers and a diagnostic LOS ray from the resolved point. |
| Surface Fit Range | Ordinary editable parcel with a container, truck and building. Partial cells are enabled here through the normal Generation 2 → action → presentation → saved replay path. |
| Other maps | Retain existing movement. The pilot is deliberately opt-in at the parcel/map level, not a per-asset authoring job. |

The body proxy starts at radius 0.28, height 1.8 and horizontal clearance 0.04 world units for a one-unit tile. These are prototype parameters, not measurements guaranteed to fit every character or weapon. A search is limited to 32 local parts and 256 tested points; exceeding those limits reports failure. The candidate set is conservative: failure means no tested fit, not proof that no continuous solution exists.

Bounds still come from the existing automatic per-mesh boxes. This does not recover holes inside a single concave mesh or produce exact polygon collision. No per-asset hull fitting, tactical-role assignment or boundary export is added.

## Why LOS must be part of it

The pilot's `MapCellData.world_position` is the canonical support/standing point. `support_center` retains logical cell identity. Movement paths, previews, grid-to-world conversion, range, five-sample LOS, Guard and spawning share that point. Cover and pose contacts search real nearby parts, including the actor's own cell and diagonal parts. Mission adjacency additionally checks physical distance and obstruction.

Parts are independently indexed for shots, so occupying their cell does not make them disappear from source/target LOS. Cover indicators sit beside the actual surface, rather than at a guessed tile edge. Grid tiles and AP costs still identify discrete tactical steps.

The lab therefore indexes the object independently of navigation, using the existing shot-only index. Its ray tests do not ignore a solid merely because it overlaps the starting tile. At the default setting, the old-center ray is blocked while the resolved-point ray clears the edge. **This is one diagnostic geometry ray, not a complete legal attack, path, Guard or replay validation.** The lab deliberately leaves its navigation cell blocked.

## Integration and deliberate limits

| Order | Pilot behavior |
| --- | --- |
| 1 | Existing part boxes automatically produce a supported point. Invalid/no-fit cells remain blocked; assets are never moved to suit the grid. |
| 2 | Graph edges require swept body clearance and floor support. Destination and route queries also check neighboring bodies. Entrances and diagonal routes use the same check. |
| 3 | Shared canonical positions feed movement, previews, combat, Guard, spawning, mission adjacency, contacts and surface-aligned cover markers. |
| 4 | Compiler **5**, simulation **surface-placement-6**, Move payload **10**. Points are rounded to **1/10000 tile**. The accepted manifest stores a reconstruction signature; moves record XYZ at each checkpoint; state fingerprints include map geometry/profile and within-cell positions. Older simulation recordings reject clearly. Compilers 1–4 remain available for their historical whole-cell geometry. |
| 5 | All three examples complete real moves and saved replay. Existing authored cover clips, contact direction and weapon IK follow the committed point. Wall-hand/foot IK and new peek firing origins remain future animation work. |

The pilot proves **flat supported floors**, including tile-edge walls. Sweeps use a conservative enclosing box around the standing body: a tight rounded corner can be rejected even if a more sophisticated solver could pass it. Unsupported rises and unvalidated ladder/step transitions reject; this pilot does not claim arbitrary ramp, stair or ladder traversal. Existing maps retain their current traversal. Do not enable this flag on a vertical map before validating its links and support representation.

The common body profile does not yet cover differently sized creatures, carried-body silhouettes or every authored animation extremity. Contact hints and authored clips are placeholders, not completed procedural cover animation. No second generator or manual hull-fitting workflow is introduced.

## Authored plus procedural animation

Use authored clips for readable motion and timing: low-cover idle, rise-over-low-cover/fire/return, left-corner lean/fire/return, and right-corner lean/fire/return. Existing high-cover left/right shooting and cover clips are placeholders to reuse; a distinct rise-over-low-cover sequence is still future work.

Procedural fitting can then adjust contact height/direction, upper-body lean, feet on the supported surface and hand/weapon placement within bounded limits. Reuse the rig's existing IK instead of adding another rig. Wall-hand and foot contact solving are **not implemented** here. The gold marker is a target for future fitting, not a hand already attached to the wall.

Any actual peek firing origin must first be validated by the shared tactical query and used identically by UI, AI, execution, Guard and replay. A visual lean cannot invent a legal shot through a wall. Animation follows committed results; root motion must not silently change tactical position.

## What JA3's public code confirms

THQ Nordic publishes significant Lua source for modding. Its [cover code](https://github.com/THQNordic/JaggedAlliance3Modding/blob/main/Lua/Tactical/Cover.lua) contains explicit alignment checks, cardinal cover offsets and stance-dependent cover queries. Its [unit code](https://github.com/THQNordic/JaggedAlliance3Modding/blob/main/Lua/Tactical/Unit.lua) uses aim/look IK and passes positions and stance into cover queries. Its [combat paths](https://github.com/THQNordic/JaggedAlliance3Modding/blob/main/Lua/Tactical/CombatPath.lua) track positions, occupancy restrictions and destination stances. These support separating tactical placement from pose fitting; they **do not establish arbitrary mesh-edge standing or reveal the complete native collision/pathfinding implementation**. FuseFire's proposal is our design, not a claim to reproduce JA3 internally. Sources inspected read-only on 2026-11-16; no JA3 code/assets copied.

## How to test the live pilot

1. Open **Parcel Editor** and select **Surface Fit Range — container, truck, building edges**. It is an ordinary editable scene at `art/environments/authored/parcels/surface_fit_range.tscn`.
2. Press **Preview**, then **Test battle**. With the editor's default two soldiers, test the container and truck; the automated three-soldier test covers the building too. Walk near the building in additional moves if desired.
3. Move toward the left side of each object. Useful destinations in parcel coordinates are **(5, 0, 12)**, **(13, 0, 12)** and **(21, 0, 12)**. Expect the soldier to stand slightly away from the tile center, beside the real surface. The object stays put. Use Move to see cover markers at its actual face.
4. Try crossing the object or placing a second soldier too close in a neighboring tile. Unsafe destinations/routes must reject or use a safe detour. A clear destination never authorizes travel through an object.
5. Move around an end before attempting a shot. A nearby obstacle still blocks its own cell's firing ray; fitting beside it does not grant the ability to shoot through it. Corner lean clips do not grant a new tactical peek origin yet.

Automated saved replay, with optional review captures:

```powershell
godot_console --headless --path . --script res://tests/surface_battle_replay_test.gd
godot_console --path . --script res://tests/surface_battle_replay_test.gd -- capture artifacts/surface-battle-review
```

The test archives the exact parcel, moves three soldiers, saves/reopens JSON and verifies replay reconstructs all three positions. It also rejects changed standing-point evidence. This is a three-Move replay, **not a completed combat match**. Review captures show the placeholder poses, not proof that every frame/weapon clears every mesh.

To try a new ordinary asset, place it in this parcel with the existing Objects tool. Its existing automatic mesh boxes participate without another asset flag or boundary draft. Current per-mesh boxes still fill holes inside one concave mesh; tanks do not yet gain an exact curved footprint. Other parcels have not been globally enabled. Developers can opt a reviewed parcel in through root metadata `surface_placement_enabled = true`; the whole assembled map then uses consistent geometry rules.

## Original slider lab

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
| Other existing maps | Existing movement restrictions remain. The new range is the enabled pilot. |

Verification and limitations: [surface-placement integration record](quality/surface-placement-2026-11-16.md).
