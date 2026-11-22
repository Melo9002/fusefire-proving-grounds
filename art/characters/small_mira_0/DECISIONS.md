# small_mira_0 skinning fix: decisions (applied 2026-11-21 as proposed)

Source: the Tripo export `asset making/test dummy/references/small Mira/MIRA-00.glb` (untouched; no copy is kept here).
Table: `tools/decisions.json`. Dry run: `tools/apply_weights.py ... preview` (writes a scratch .blend, no .glb).

Result of the dry run: verts with 2+ bones over 0.15 go from 5,930 to 2,091 (all in the soft joint pieces), max influences go from 4 to 3, normalized.

## Rigid (100% one bone)
| Bone | Pieces (island ids) |
|---|---|
| Head | helmet, ears, ear discs, face plate (46 75 137 47 116 78 45 115 76 136) |
| Spine2 | chest shell 36, collar/yoke 44 69 71, backpack 68 72 73 74 133 |
| L/R Shoulder | tiny clavicle caps 67 132 |
| L/R Arm | shoulder pauldrons 61 128, upper-arm pins 58 59 60 129 130 131 |
| L/R ForeArm | forearm cylinders 25 99 |
| L/R Hand | palms 13 97 |
| finger bones | every finger segment and knuckle: its dominant bone |
| Hips | pelvis/briefs shell 32, front crotch plate 33, rear plate 55, pelvis ball and small pelvis bits 38 39 43 64 65 |
| L/R UpLeg | thigh shells 31 86, **side hip plates 29 87** |
| L/R Leg | shin/boot shafts 1 80, below-knee pieces 4 84 |
| L/R Foot | foot shells 0 79 and small foot bits 2 3 48 81 82 117 118 |

## Soft (blended, restricted to these bones, cap 4, normalized)
| Allowed bones | Pieces |
|---|---|
| Spine2 Neck Head | neck column 70 |
| Neck Head | neck side pieces 77 135 |
| Shoulder + Arm (same side) | shoulder ball joints 34 114 |
| Arm + ForeArm (same side) | elbow joints 56 57 62 126 127 134 |
| UpLeg + Leg (same side) | knee joints 30 85, kneecaps 5 83 |
| Hips Spine Spine1 | abdomen/waist segments 35 37 40 41 42 63 66 111 112 113 125 |

## Calls to confirm
1. Side hip plates follow the thigh (UpLeg), not the pelvis. Alternative: Hips (they stay put, the thigh swings out under them).
2. Pelvis shell rigid to Hips: no tearing, but the thigh passes through it in a high kick.
3. Chest shell rigid to Spine2 (not Spine1).
4. Foot shells rigid to Foot: the toe joint (ToeBase) drives nothing, the boot does not bend at the toes.

## Applied
`models/small_mira_0.glb`: 1 mesh, 65-joint skin, 22 animations, same material as the source. Re-audit (`audit_after.json`): 138 islands, every rigid island has exactly 1 influence, max 3 influences, 2,091 multi-bone verts (soft joints only). The export split one vertex on a seam (11,111 -> 11,112).

## Other findings
- The `Icosphere` that appears after import is Blender's bone display shape from the glTF importer, not a stray mesh in the file (the glTF has 1 mesh).
- Tripo baked `.001` into every animation name in the source glb; stripped in `models/small_mira_0.glb` with `tools/rename_animations.py` (JSON chunk only, mesh and animation data byte-identical).
- Boot/shin flare edges are jagged in the mesh itself (visible at rest), not a skinning problem.
- No baked crouch clip; crouch not verified.

## Godot (4.7.2) setup
Layout: `models/small_mira_0.glb` (the fixed model), `small_mira_0_rig_profile.tres`, `tools/` (Blender + Godot scripts, `.gdignore`). Renders and audit JSON were review material and are not kept; to redo the fix, run `tools/audit_islands.py` on the original (its island ids must match `tools/decisions.json`), then `tools/apply_weights.py ... apply`, then `tools/rename_animations.py`.

Rig profile: same Mixamo role map, joint specs and sockets as MIRA's; `character_scale = 1.0` (shown at true size, ~1 m; MIRA is 1.6). `tools/validate_profile.gd` (headless): **no errors or warnings**; A-pose (arms 68 degrees below horizontal); hip height 0.54 m, leg 0.45 m (thigh 0.22, shin 0.23), ankle 0.08 m, standing height 0.88 m (measured at the HeadTop_End joint; the ears reach 1.0 m); 11 capabilities SUPPORTED, the 2 unimplemented ones NOT_IMPLEMENTED as for MIRA. Body up is tilted 6 degrees backward (the head joint sits 2.7 cm behind the hips), under the warning threshold.

On the real rig stack (`tools/rig_capture.gd`, exploration host, unarmed, swapped in memory; nothing in production references small_mira_0): no absent roles, nothing degraded, no foot-point problems; idle, walk, climb, hit and defeat build and look sane.

### Found
- **Crouch is far too deep.** Posture depths are absolute metres tuned for MIRA (exploration host `crouch_depth` 0.41 m, rescue 0.5 m, cover profile depths). On a 0.54 m hip height that folds her into a ball, thighs through the forearms. Needs depths scaled by the measured hip height (or per-character values) in production code: not changed here.
- The baked Tripo clips are not used by the rig (it builds its own clips from roles; MIRA imports with `animation/import=false`). If you ever want them: none is flagged to loop, and walk (1.57 m), run (3.07 m), swim, flip, shoot, climb carry root motion on Hips (there is no root bone).

### Scale correction (2026-11-22)
The robot is meant to stand 1.20 m (mesh, ears included). `character_scale` is 1.2 in the rig profile and the rig scene (the .glb is unchanged, ~1.0 m); the numbers authored for it in the scenes and the handling profile are MIRA's scaled by the leg ratio (0.695).
