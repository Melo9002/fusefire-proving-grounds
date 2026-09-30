# Character Animation Editing Guide

This guide covers the Prototype 1 VRoid character and AUG presentation. The blocking clips were generated in Godot and are now saved as an editable library. The demo and live units load the same library. Start with one small idle edit, inspect it in the demo, then test it in a match.

## Start here: edit an existing clip in Godot

All paths below are relative to the project root (the FileSystem dock's `res://`).

1. Open `art/characters/vroid_proof/animations/animation_workbench.tscn` in Godot's editor. This is an editing scene, not a playable demo: use the editor's 3D view, not F6.
2. Select its `AnimationPlayer`. In the Animation panel, choose `rifle_idle`, then scrub the timeline. The character should move.
3. Select an existing rotation key on a chest/head track. Adjust its value or timing in the key Inspector; start small. Keep the first/last keys compatible for a seamless loop. These saved rotations are quaternions, unlike the degree-based generator helpers.
4. Save the external `prototype_clips.tres` library using the Animation panel's library management/save controls, and save the scene. Confirm the `.tres` changes in Git. Do not use Make Unique unless intentionally creating a separate library.
5. Open `art/characters/vroid_proof/demo/vroid_weapon_ik_demo.tscn`, press F6, then **1**. Restart the running demo after saved edits; clips are loaded at startup.
6. Test in a battle and replay. Revert the `.tres` edit in Git if it does not look right.

The workbench previews **skeletal keys only**. It deliberately has no weapon IK, passenger, muzzle flash, or procedural defeat fall. Use the demo to inspect the combined result. Do not edit the Remote scene tree to make permanent changes: those disappear when the game stops.

### Where each kind of edit belongs

| Edit | File or Inspector location |
| --- | --- |
| Skeletal poses, key timing, clip lengths and loops | `art/characters/vroid_proof/animations/prototype_clips.tres`, through the workbench |
| Demo weapon/contact/rescue offsets | Root of `art/characters/vroid_proof/demo/vroid_weapon_ik_demo.tscn` |
| Live weapon/contact/rescue offsets, stride, turn speed, camera anchors | Root of `art/characters/vroid_proof/runtime/unit_visual_adapter.tscn` |
| Shared default offsets for both scenes | Exported defaults in `art/characters/vroid_proof/runtime/character_rig.gd` |
| Blend states, crossfade times, generated fallback clips, procedural defeat fall | `art/characters/vroid_proof/runtime/character_animation_controller.gd` |
| Gameplay-to-animation requests and return timers | `art/characters/vroid_proof/runtime/unit_visual_adapter.gd` |
| Rescue dummy mesh | `art/characters/vroid_proof/runtime/rescue_passenger.gd` |

Changing a demo Inspector value does **not** change live units. Copy accepted values into the runtime adapter scene, or change the shared script default if neither scene overrides it. The library is shared automatically; offsets are scene properties.

### Clip names and demo controls

| Clips | Preview | Loop |
| --- | --- | --- |
| `rifle_idle` | 1 | Yes |
| `move`, `move_back`, `move_left`, `move_right` | 2 or arrow keys; T previews turns; brackets change speed | Yes; keep matching cycle lengths/phases |
| `aim`, `shoot`, `hit`, `defeat` | 3, 4, 5, 6 | Aim holds; others play once |
| `cover_low`, `cover_high` | 7, 8 | Yes |
| `shoot_left`, `shoot_right` | 9, 0 | No |
| `vault`, `climb`, `descend`, `land` | V, B, N, L | Traversal loops; landing plays once |
| `pickup`, `carry_idle`, `carry_move`, `boarding` | R, P, M, E | Carry idle/move loop; others play once |

Right mouse drag orbits; C changes view; I toggles arm IK for inspection; Space runs the basic sequence. `RESET` is a technical rest pose, not a gameplay clip. Runtime rebuilds RESET from the used tracks; leave the workbench RESET intact.

### Inspector units and coordinates

**Weapon Contact** exposes grip, sight, buttstock and shoulder offsets. Grip/sight/stock offsets use weapon-local metres. The shoulder offset is added in Character-local axes to the animated right upper-arm origin. **Low Ready** exposes rifle Euler angles in degrees and grip position in Character-local metres. **Rescue Carry** exposes passenger/stowed rifle positions and stowed rifle angles in degrees. **Locomotion** exposes turn speed in degrees/second and stride in metres per cycle. **Camera Anchors** are adapter-local metres.

The runtime model faces **+Z**, with **+Y up**. Avoid flipping the character or root to correct one bad stride. Bone track paths are `.:J_Bip_...` relative to the Skeleton3D, and keys contain local bone poses including the imported rest transform. Only bone rotation/position tracks are accepted; gameplay still owns map translation.

### What remains procedural

`AnimationPlayer` stores the clips. `AnimationTree` chooses/blends them and controls locomotion pace. Arm IK runs afterward and can override keyed arm positions, so inspect hand contacts in the demo. Weapon carry/aim blending and recoil are driven by the presentation script. Defeat also tilts/translates the Character root in `_apply_visual_root_state()`.

Changing clip length alone does not change action timing: the adapter currently returns from shooting at 0.34 s, hit at 0.58 s, and pickup at 0.6 s; ObjectiveManager boards for 0.6 s. Inspect these callers before lengthening those clips. For now, keep replacements within the existing action windows. A full-body fall authored in Blender must replace the procedural fall too, or both will apply.

Saved library clips take precedence over `_make_*()` builders. Editing a builder will not change an existing saved clip. Missing names fall back to generated clips; invalid bone tracks produce a warning and fall back. `tools/export_animation_workbench.gd` was used once to bootstrap the files and refuses to overwrite them. Do not regenerate over hand edits.

## 26H rescue and extraction previews

Demo keys: **R** pickup, **P** carrying idle, **M** carrying movement, **E** boarding/release pose. The orange passenger is a lightweight cosmetic mannequin; the actual rescued actor remains hidden and tracked by the mission rules. There is no new drop-passenger command. Runtime boarding lasts 0.6 seconds, releases the cosmetic passenger, then performs the existing extraction and records it. Repeated extraction requests are rejected during boarding.

Edit `_make_rescue_pose()` in the animation controller, `rescue_passenger.gd` for the dummy, and `presentation/overlays/extraction_transport.gd` for the parked truck. Carrying disables shooting in both CombatRules and AttackAction, turns off weapon IK, and stows the AUG while the arm clips support the passenger. Supporting-hand contact still needs visual refinement.

`systems/objectives/extraction_transport_planner.gd` reserves a deterministic 2-by-4 footprint near boarding, before map validation. Those cells are indestructible full cover and block movement/LOS. Placement excludes mission/deployment zones and traversal endpoints, and preserves terrain connectivity. If no safe rectangle is available, the existing off-grid cosmetic fallback is retained. Boarding tiles remain authoritative; units do not physically walk into the vehicle.

Carriers prioritize evacuation and never chase targets. Escorts prioritize threats to the carrier, stay nearby, and keep its planned route clear; after the carrier leaves, escorts prioritize evacuation even while hostiles remain. Reach and extraction movement favors cover and safe progress over acquiring firing lanes. Units take supporting shots when no useful advance is available, without chasing enemies away from their objective. Rescue missions remain open after VIP boarding for remaining escorts. The truck's Leave button and the HUD departure action ask for confirmation showing the number left behind. Required VIP extraction must be satisfied first. Departure is journaled and replayed, including zero-AP boarding.

## 26G cover and traversal previews

In `vroid_weapon_ik_demo.tscn`, use **7/8** for low/high cover, **9/0** for left/right exposure shots, **V** for vault, **B/N** for climb/descent, and **L** for landing. Right-mouse drag orbits the camera. These previews stay in place; play a battle to inspect movement over actual terrain.

`tactical_pose_context.gd` derives presentation cues from adjacent cover and the original grid path. The visual adapter chooses nearby cover most aligned with facing, faces its normal on settling, and returns to that stance after a shot. High-cover exposure is a small body offset, not a guarantee that a hand or muzzle clears scenery. Vault/climb/descent loops follow existing path translation and finish with a landing pose. These are blocking clips: ladder-hand contacts, obstacle-sized vault arcs, foot-lock IK, and polished timing remain manual refinement work. The rifle remains held during traversal.

Edit `_make_tactical_pose()` and the exposure clips in `character_animation_controller.gd`. An explicit RESET animation restores bones unused by subsequent clips, preventing a crouch from persisting into idle. Presentation does not change cover bonuses, AP, collision, or shot evaluation.

## 26F locomotion tuning

Select the unit's visual adapter and expand **Locomotion** in the Inspector:

- **Turn Speed Degrees** controls how quickly the body follows path direction (default 360 degrees/second).
- **Stride Length** is metres per complete left/right step cycle (default 1.6). Larger values slow the feet at the same movement speed.

The `move` animation state contains a synchronized four-direction blend space and a pace multiplier. While the body turns toward travel, it blends backward or sideways steps into the forward loop. These are transitional directions, not a player-controlled strafe/lock-facing mode. Existing idle/move crossfades remain active. TacticalUnit supplies velocity before moving; animation does not displace the unit or change AP/path legality.

Clips are generated by `_make_move()` and `_make_directional_move()` in `art/characters/vroid_proof/runtime/character_animation_controller.gd`. This remains a blocking foundation without foot-lock IK; inspect foot sliding visually before accepting the stride setting. Test short moves, a reversal, diagonal travel, corners, and replay. Automated regression: `tests/locomotion_foundation_test.gd`.

## Current structure

Run `art/characters/vroid_proof/demo/vroid_weapon_ik_demo.tscn`. `character_animation_controller.gd` loads saved clips over its generated fallbacks and creates the `AnimationTree`; `runtime/character_rig.gd` places the AUG, drives arm IK, approximates sight/shoulder alignment, and presents recoil and muzzle flash.

The right hand owns the rifle attachment, the left hand follows `SupportHandTarget`, and `MuzzleSocket` drives effects. Movement remains in place because gameplay owns exact tactical positions. Press `C` to switch between three-quarter and side inspection cameras.

## Quick numerical edits

For relaxed idle/movement carry, adjust `carry_angles_degrees` and
`carry_grip_position` on the demo or runtime adapter root in the Inspector.
The rifle angles blend to the shouldered orientation during aim/shoot. Both
hand targets use the same rifle rotation, so the support hand follows the
foregrip through the transition. Movement raises the carry slightly and adds
an 8 mm bounce; elbow poles are tucked closer during carry.

The clip builders in `character_animation_controller.gd` are `_make_idle()`, `_make_move()`, `_make_aim()`, `_make_shoot()`, `_make_hit()`, and `_make_defeat()`. Rotations are degrees relative to the imported rest pose; key times are seconds.

Weapon-pose controls live in `runtime/character_rig.gd`:

- `grip_offset` places the AUG relative to the firing hand.
- `sight_offset` identifies the optic reference.
- `carry_grip_position` controls low ready.
- `aimed_grip` derives the sighted pose from the aiming eye.
- The elbow-pole positions control elbow bend direction.

This is useful for small corrections. Visual tools are better for timing, weight, arcs, hands, and believable body mechanics.

## Recommended visual workflow

Use Blender for finished skeletal clips and Godot for blending, IK correction, effects, and gameplay integration.

1. Open `art/characters/vroid_proof/source/vroidTest_runtime.blend` and Save As a working copy. The current Godot-generated clips are **not** Blender actions in this file; this route authors replacements, not a round trip of the existing keys.
2. Select `VRoidProof_Armature` and enter Pose Mode.
3. Open the Dope Sheet and switch to Action Editor.
4. Start with one action named `rifle_idle`; later use the clip names in the table above. Keep actions saved/stashed so Blender retains them.
5. Pose and key only intended bones. Inspect every clip from front, side, and three-quarter views.
6. Keep locomotion in place. FuseFire moves the actor between exact tiles.
7. Save the Blender file before exporting.
8. Export a separate glTF Binary (`.glb`) with animation enabled, using the existing armature and bone names. Export only skeletal animation; avoid object transform, shape-key, and scale animation in this first handoff. Use the exporter's Actions mode when available, and bake control-rig/constraint motion into bone keys. Do not regenerate weights, apply the armature modifier, change the rest pose, or rename bones. Do not overwrite `vroid_test_runtime.glb`.
9. Put the exported file under `art/characters/vroid_proof/animations/`, let Godot import it as a **Scene**, and inspect its AnimationPlayer. Check the exact imported animation name and that the skeleton still matches. Exporter options vary with Blender version; see the [official Blender glTF manual](https://docs.blender.org/manual/en/latest/addons/scene_gltf2.html).
10. Convert one imported clip to the runtime's skeleton-relative paths with the helper below. It checks bone names/rest transforms, strips constant identity scale tracks, rejects unsupported tracks, and refuses to overwrite an existing output. It does not retarget a different rig.
11. In the workbench AnimationPlayer's animation/library management, replace only the corresponding animation in the unnamed library with the converted `.tres`, retaining its exact gameplay name. Save `prototype_clips.tres`. Keep the rest of the library and RESET. Configure the appropriate loop mode, then test in the demo and a match.

Example command from the project root (replace the input filename and imported animation name with your actual export):

```powershell
godot_console --headless --path . --script tools/import_animation_clip.gd -- res://art/characters/vroid_proof/animations/my_idle.glb rifle_idle res://art/characters/vroid_proof/animations/my_idle_clip.tres
```

If conversion reports a rest mismatch, return to the runtime Blender copy and check export transforms; do not bypass the check. A raw imported animation library uses different track paths and is not a drop-in replacement for the Clip Library field. Godot's general import/save-to-file options are described in its [import configuration documentation](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html).

The converter has been tested with the existing same-rig scene. A newly authored Blender export still needs its first end-to-end visual check. Ask for help with that first clip if the exporter introduces extra tracks or changes the rest pose.

Work on copies of the runtime Blender file until export is proven. The untouched VRM and intake Blender file remain recovery sources.

## Aiming and stock contact

The current prototype anchors aimed rifle placement to `ShoulderContact`, sampled
from the animated right upper-arm origin. `ButtstockContact` marks the rifle pad.
Tune `stock_contact_offset` and `shoulder_contact_offset` on the presentation
script in the Inspector. Both the demo and live adapter use this calculation.
Chest animation carries the recoil; independent rifle compression is about 5 mm.
These are approximate contact locations for the proof model. This pass prioritizes
shoulder contact: the aiming eye currently sits about 11 cm from the optic line,
so a later cheek/head pose pass is needed before calling the sighted pose finished.


The current generated markers are `ButtstockContact` on the weapon and `ShoulderContact` on the character; these are presentation markers, not gameplay collision.

Solve the weapon pose in this order:

1. Put the stock against the shoulder contact.
2. Rotate the weapon so its optic aligns with the aiming eye and target direction.
3. Put the firing hand on `WeaponOrigin`.
4. Make the left hand follow `SupportHandTarget`.
5. Use `MuzzleSocket` for shots and effects.

Do not let the shoulder, eye, and both hands independently move the rifle. That overconstrains it and causes jitter. The presentation weapon pose should drive the hands.

## Hands and fingers

Arm IK places wrists; it does not create a convincing grip. Finished poses need wrist orientation, curled fingers, thumb placement, and a distinct trigger-finger pose. Create reusable hand-pose animations and layer them over idle, movement, aim, and firing. Low ready can keep the trigger finger outside the trigger guard; firing can place it on the trigger if that distinction remains visible from the tactical camera.

## Porting another VRoid

Another standard VRoid should reuse most animation work because VRoid humanoids generally share bone names and hierarchy. Validate each character's height, arm reach, elbow poles, eye height, shoulder contact, hand size, stride, foot contact, and loose clothing or hair.

Similar proportions may need only adapter offsets. Short, tall, or unusual proportions require a correction profile. Non-humanoid MIRAs need separate rigs and animation libraries behind the same presentation interface.

## Validation

```powershell
godot_console --headless --path . -s tests/animation_handoff_test.gd
godot_console --headless --path . -s tests/vroid_asset_import_test.gd
godot_console --headless --path . -s tests/vroid_weapon_ik_test.gd
godot_console --headless --path . -s tests/vroid_vertical_slice_animation_test.gd
godot_console --headless --path . -s tests/vroid_pose_refinement_test.gd
```

Tests cover structure, reach, knee direction, forward foot swing, and sight alignment. Visual review remains necessary for style, timing, weight, clipping, and believability.
