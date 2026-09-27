# Android Test Dummy rigging notes

## 26C result

The active project model is `../models/android_test_dummy_rigged.glb`.

- Skeleton bones: 26
- Deforming bones: 21
- Control and socket bones: 5
- Weighted vertices: 53,520 of 53,520
- Character height: 1.60 m
- Forward direction in Blender source: negative Y

The weighting process treats small armor fragments as internally rigid pieces with a shared blend between nearby bones. Larger undersuit and body shells receive per-vertex anatomical blends. This preserves armor shapes while allowing shoulders, elbows, torso, hips, knees, ankles, and neck to bend.

## Bone contract

Axial chain:

- `Root`
- `Pelvis`
- `Spine`
- `Chest`
- `Neck`
- `Head`

Limbs use `.L` and `.R` suffixes:

- `Clavicle`
- `UpperArm`
- `Forearm`
- `Hand`
- `Thigh`
- `Shin`
- `Foot`
- `Toe`

Controls and attachments:

- `hand_ik.L`
- `hand_ik.R`
- `weapon_socket_r`
- `carry_socket`

The socketed AUG runtime is `../../../weapons/aug/models/aug_runtime_socketed.glb`. It contains `WeaponOrigin` and `MuzzleSocket` markers.

## Validation performed

A deliberately asymmetric stress pose exercised both elbows, both shoulders, chest twist, hip flexion, knee flexion, ankle compensation, and neck counter-rotation from front, side, rear, and three-quarter views. The refined weights kept the major armor shells together and removed the initial separation of small joint fragments.

Godot validation confirms:

- the rigged GLB imports as a skinned mesh with `Skeleton3D`;
- all required bones and sockets are present;
- all vertices are weighted;
- the character remains 1.60 m tall in its rest pose;
- the AUG remains 0.79 m and exposes its muzzle marker.

## Prototype 1 limits

The rig intentionally omits finger articulation, facial animation, twist bones, mechanical pistons, secondary armor simulation, and production-quality control widgets. Hands use a single bone each. These additions can be evaluated after the locomotion, combat, cover, traversal, and rescue animation requirements are proven.
## Repeating the deformation review

From a terminal with Blender available, run:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --python art\characters\android_test_dummy\source\validate_rig_deformation.py
```

The script creates temporary four-angle stress-pose renders under `art/characters/android_test_dummy/review/`. Inspect the renders and remove that generated review directory before committing unless a particular image is needed as review evidence.
