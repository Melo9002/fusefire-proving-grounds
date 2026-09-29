# VRoid proof-character workflow

## Folder contract

- `source/` contains the untouched `.vrm`, Blender working file, extracted source textures, and conversion scripts. Godot ignores this directory.
- `models/` contains only runtime assets intended for Godot, beginning with the exported `.glb` and any required textures.
- `demo/` contains the Godot inspection scene and its scripts.
- `review/` contains disposable renders and deformation checks. Godot ignores this directory.
- `docs/` contains bone maps, license notes, import reports, and workflow documentation.

## Completed intake and runtime conversion

The untouched `vroidTest.vrm` is preserved in `source/`. The normalized runtime export is `models/vroid_test_runtime.glb`: 1.60 m tall, 229 bones, three skinned meshes, and 57 exported facial morphs.

The intake pass records:

- original filename and VRM version;
- stated author and model permissions;
- height, orientation, mesh and triangle counts;
- armature and humanoid bone map;
- materials, textures, shape keys, and spring-bone data;
- loose accessories or clothing likely to complicate animation;
- the safest Blender-to-GLB conversion settings for this specific model.

The AUG remains a separate runtime asset. Its right-hand origin, support-hand IK target, and muzzle marker are consumed by the demonstration presentation layer rather than baked into the character mesh.

## Animation proof

Open `demo/vroid_weapon_ik_demo.tscn` and run the current scene. Controls:

- `1`: rifle idle
- `2`: in-place movement loop
- `3`: aim
- `4`: shoot, recoil, and muzzle flash
- `5`: hit reaction
- `6`: defeat and side fall
- `Space`: play the entire sequence
- `I`: toggle hand IK
- `Esc`: close

These clips are blocking-quality procedural animations for validating the Godot pipeline. Gameplay movement remains authoritative; the movement clip contains no root motion. The defeat tween rotates only the presentation root and does not move the tactical unit.

Run the automated checks from the repository root:

```powershell
godot_console --headless --path . -s tests/vroid_asset_import_test.gd
godot_console --headless --path . -s tests/vroid_weapon_ik_test.gd
godot_console --headless --path . -s tests/vroid_vertical_slice_animation_test.gd
```

## 26D pose refinement

Knee flexion uses the VRoid leg axis with the heel folding backward. The bent-knee swing travels along the imported humanoid's visual-forward axis (+Z), while the straighter stance leg travels backward. Facing updates from displacement only during tactical movement, so spawn placement cannot overwrite the opposing-team facing. The movement remains an in-place prototype loop; foot planting and speed matching still need refinement.

Aim blends from low ready to an eye-aligned optic reference. The rifle is kept within both arms' reach. Recoil and hit reactions are stronger, and repeated shots restart their clip. Press `C` for the side inspection camera.

Additional regression: `godot_console --headless --path . -s tests/vroid_pose_refinement_test.gd` checks knee direction, forward swing, and eye/sight alignment. These geometric checks supplement visual review; they do not certify animation quality. Clips are generated in Godot, not authored into the Blender source or GLB.

## 26E live tactical adapter

`UnitVisualAdapter` is a presentation child of `TacticalUnit`. It responds to
movement, attacks, HP changes, and defeat. The hidden capsule, grid cell, stats,
combat rules, and replay log remain authoritative.

Run its focused contract test and the record/replay integration test:

```powershell
godot_console --headless --path . -s tests/unit_visual_adapter_test.gd
godot_console --headless --path . -s tests/battle_replay_smoke.gd
```
