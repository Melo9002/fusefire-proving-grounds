# Generated Test Dummy Optimization

Source: `base_basic_pbr.glb`

## Candidates

- `generated_dummy_100k_160cm.glb`: 100,000 triangles, 1.600 m. High-detail reference candidate.
- `generated_dummy_50k_160cm.glb`: 50,000 triangles, 1.600 m. Recommended runtime candidate.
- `generated_dummy_25k_160cm.glb`: 25,000 triangles, 1.600 m. Visible loss in face, seam, hand, and joint detail.

Each GLB retains the source UV set and 2048 px diffuse, metallic/roughness, and normal textures. Matching `.blend` files and review renders are included.

## Rigging assessment

The 50k candidate is one mesh object but contains 5,315 disconnected geometry islands; 4,472 islands contain fewer than ten vertices. It has no armature or animations. The visual asset is usable, but it needs a rig-preparation pass before deformation animation. Keep rigid armor shells separate where useful, and rebuild or retopologize deforming areas around shoulders, elbows, hips, knees, neck, hands, and torso.

The weapon is intentionally postponed until the free weapon package is selected.
