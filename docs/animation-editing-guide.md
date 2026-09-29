# Character Animation Editing Guide

This guide covers the Prototype 1 VRoid character and AUG presentation. The current clips are blocking-quality animations generated in Godot. They prove the runtime pipeline, but they are intended to be replaced or refined by visually authored clips.

## Current structure

Run `art/characters/vroid_proof/demo/vroid_weapon_ik_demo.tscn`. `vroid_vertical_slice_controller.gd` creates the clips and `AnimationTree`; `vroid_weapon_ik_demo.gd` places the AUG, drives arm IK, aligns the sight with the eye, and presents recoil and muzzle flash.

The right hand owns the rifle attachment, the left hand follows `SupportHandTarget`, and `MuzzleSocket` drives effects. Movement remains in place because gameplay owns exact tactical positions. Press `C` to switch between three-quarter and side inspection cameras.

## Quick numerical edits

For relaxed idle/movement carry, adjust `carry_angles_degrees` and
`carry_grip_position` on the demo or runtime adapter root in the Inspector.
The rifle angles blend to the shouldered orientation during aim/shoot. Both
hand targets use the same rifle rotation, so the support hand follows the
foregrip through the transition. Movement raises the carry slightly and adds
an 8 mm bounce; elbow poles are tucked closer during carry.

The clip builders in `vroid_vertical_slice_controller.gd` are `_make_idle()`, `_make_move()`, `_make_aim()`, `_make_shoot()`, `_make_hit()`, and `_make_defeat()`. Rotations are degrees relative to the imported rest pose; key times are seconds.

Weapon-pose controls live in `vroid_weapon_ik_demo.gd`:

- `GRIP_OFFSET` places the AUG relative to the firing hand.
- `SIGHT_OFFSET` identifies the optic reference.
- `ready_grip` controls low ready.
- `aimed_grip` derives the sighted pose from the aiming eye.
- The elbow-pole positions control elbow bend direction.

This is useful for small corrections. Visual tools are better for timing, weight, arcs, hands, and believable body mechanics.

## Recommended visual workflow

Use Blender for finished skeletal clips and Godot for blending, IK correction, effects, and gameplay integration.

1. Open `art/characters/vroid_proof/source/vroidTest_runtime.blend`.
2. Select `VRoidProof_Armature` and enter Pose Mode.
3. Open the Dope Sheet and switch to Action Editor.
4. Create actions named `rifle_idle`, `move`, `aim`, `shoot`, `hit`, and `defeat`.
5. Pose and key only intended bones. Inspect every clip from front, side, and three-quarter views.
6. Keep locomotion in place. FuseFire moves the actor between exact tiles.
7. Save the Blender file before exporting.
8. Export with the existing skeleton and bone names. Do not regenerate weights, apply the armature, or rename bones.
9. Connect the imported clips to the existing Godot `AnimationTree` state names.

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


The AUG should eventually expose `StockContact` where the buttstock touches the body. The character adapter should expose `ShoulderContact` near the front of the firing shoulder.

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
godot_console --headless --path . -s tests/vroid_asset_import_test.gd
godot_console --headless --path . -s tests/vroid_weapon_ik_test.gd
godot_console --headless --path . -s tests/vroid_vertical_slice_animation_test.gd
godot_console --headless --path . -s tests/vroid_pose_refinement_test.gd
```

Tests cover structure, reach, knee direction, forward foot swing, and sight alignment. Visual review remains necessary for style, timing, weight, clipping, and believability.
