# Android Test Dummy topology notes

## 26B cleanup result

The project runtime mesh is `../models/android_test_dummy_rigprep.glb`.

- Height: 1.60 m
- Faces: 50,000 triangles
- Vertices before cleanup: 58,686
- Vertices after exact weld: 53,520
- Duplicate seam vertices welded: 5,166
- Faces removed: 0
- Connected components before cleanup: 5,315
- Connected components after cleanup: 2,688
- UV set and PBR textures retained

A one-micrometre weld threshold was selected because it joins numerically duplicated seam vertices without collapsing visible panel gaps, fingers, facial features, or armor details. Larger thresholds joined more surfaces but began changing geometry and were rejected.

## Rigging strategy

The generated character is built from many armor and surface shells. A forced watertight remesh would discard the existing UV layout and soften the design. The rig will therefore use controlled anatomical weights:

- torso, head armor, forearm shells, thigh shells, and shin shells should behave mostly rigidly;
- black undersuit regions around the shoulders, elbows, hips, knees, neck, and waist provide the primary deformation areas;
- the right hand owns the weapon socket;
- the left hand follows a foregrip IK target;
- test poses must cover deep knee bend, raised rifle aim, elbow bend, torso twist, and low-cover crouch before animation production begins.

The original pre-weld working mesh remains in `android_test_dummy_50k.blend`, and the external generation folder remains a second backup.