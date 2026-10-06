# 🎭 Animation source and retargeting survey

This survey supports `EXP-001`. Its goal is to find useful motion for the current
VRoid proof character, then carry the same animation intent to MIRA-0 without
making either model the permanent owner of FuseFire's animation library.

## Recommendation

Begin with **Mixamo motion + Godot 4.7's built-in humanoid retargeting**, one clip
at a time. Use Blender for cleanup and authored corrections. Evaluate the Mixamo
Animation Batcher only after the manual path works and repeated imports become a
real burden.

This fits the assets we already have:

- MIRA-0 and MIRA-00 use 65 `mixamorig:`-prefixed joints.
- Their current GLBs already include Mixamo-style baked clips.
- The VRoid and MIRA bodies are all bipedal humanoids, which is the body family
  Mixamo supports.
- Godot's retargeter is designed to share humanoid animation across skeletons
  whose names, rest transforms, and proportions differ.

## Source candidates

| Source | Cost / use | Fit | Risks | Decision |
|---|---|---|---|---|
| [Adobe Mixamo](https://www.mixamo.com/) · [official FAQ](https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html) | Free with an Adobe ID; Adobe says its characters and animations may be used royalty-free in personal, commercial, and nonprofit games | Excellent first source for humanoid idle, locomotion, turns, weapon-neutral actions, hits, defeat, traversal, and expressive prototypes | Bipedal humanoids only; generic clips still need tactical posing, loop cleanup, foot work, weapon contacts, and local archival | **Use for the first proof** |
| Existing MIRA baked clips | Already owned in the current GLBs | Immediate comparison set; many names overlap between MIRA-0 and MIRA-00 | Their provenance/export history and artistic quality must be recorded; baked transforms may be noisy | **Inspect and reuse selectively** |
| Original Blender animation | Our labor | Best final control over MIRA personality, weapon handling, contacts, and unusual body families | Slowest path; easier after the import/retarget contract is stable | **Final-quality path** |
| Other free mocap libraries | Varies | Potentially useful for specialist or natural motion | License, skeleton format, cleanup burden, and provenance vary per pack | **Research only when Mixamo lacks a needed motion** |

Adobe also advises saving rigged characters locally because Mixamo retains only
the last used character. Every downloaded source clip should therefore live in a
recoverable source-asset area with its source, download settings, and date.

## Godot 4.7 retargeting path

Use the [Godot 4.7 retargeting guide](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/retargeting_3d_skeletons.html)
as the authoritative starting point.

1. Import the target character as a scene.
2. Assign `SkeletonProfileHumanoid` through a `BoneMap` and verify every mapping.
3. Import the source motion as an `AnimationLibrary`.
4. Map the source skeleton to the same humanoid profile.
5. Test position-track normalization because different hip heights otherwise
   create stride and root-motion problems.
6. Inspect rest-pose and axis correction visually; identical names do not imply
   compatible bone rests.
7. Keep gameplay movement authoritative and treat imported root motion as source
   information to remove, normalize, or adapt deliberately.

The guide warns that aggressive rest-axis correction can damage a skeleton whose
original rests matter. We should preserve source files and change one importer
setting at a time.

## First clip set to search

Do not download a giant library. Find a small set that answers our current
questions:

| Priority | Motion | What it tests |
|:---:|---|---|
| 1 | Relaxed rifle-neutral idle | Silhouette, breathing, foot stability, and MIRA personality |
| 2 | Walk forward in place | Retargeting, stride, loop seam, and speed matching |
| 3 | Run forward in place | Faster stride and transition from walk |
| 4 | Strafe left/right | Directional locomotion and leg crossing/clipping |
| 5 | Walk/run backward | The previous “moonwalk” failure mode |
| 6 | 90° turn left/right | Facing without sliding or snapping |
| 7 | Hit reaction and fall | Short non-looping combat events |
| 8 | Weapon-ready idle or rifle aim | Shoulder stock and hand-contact correction workload |

Prefer **in-place** locomotion when available. Download without skin when the
service permits it, keep the highest practical key quality, and record the exact
download settings. We can derive polished variants only after one source clip
works on both the VRoid and MIRA-0.

## Candidate Godot tools

| Candidate | License / compatibility | Usefulness | Current decision |
|---|---|---|---|
| [Mixamo Animation Batcher](https://github.com/KarnesTH/mixamo-animation-batcher) | MIT; tested with Godot 4.6.2 | Batch-imports Mixamo FBX files into `.res` animations with humanoid retargeting and bone renaming | **Sandbox later.** Promising, but very young; first prove one manual 4.7 import |
| [Animation Node Redirector](https://godotengine.org/asset-library/asset/3627) | MIT; Godot 4.3 | Repairs `AnimationPlayer` node paths after scene-tree reorganization | **Keep in reserve.** Useful recovery tool, not part of normal animation design |
| [Inverse Kinematics 3D Demo](https://store.godotengine.org/asset/godot-foundation/inverse-kinematics-3d-demo/) | MIT; Godot 4.7; marked unstable | Reference implementations for built-in IK and FABRIK | **Study only.** Its current store review reports broken bone positions |

## Acceptance test for the first borrowed animation

- [ ] Source, license, date, and download settings are recorded.
- [ ] The unmodified source file is preserved outside generated Godot imports.
- [ ] The VRoid plays the clip without broken limbs or scale changes.
- [ ] MIRA-0 plays the same clip through an explicit humanoid mapping.
- [ ] Both models face the expected direction and keep usable foot contact.
- [ ] Locomotion speed can match authoritative tactical movement.
- [ ] The clip can be edited in Blender and re-imported once.
- [ ] Removing the experimental animation does not affect P1 presentation.

If that passes, we can evaluate batching and build a deliberate temporary clip
set. If it fails, the failure tells us whether the problem is bone mapping, rest
pose, scale, position tracks, or the source motion itself.

