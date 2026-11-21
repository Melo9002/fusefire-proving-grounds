# Animation editing: quick reference

The maintained architecture and developer guide is [animation.md](animation.md). This page is only the shortcut for the common edits; paths are current.

| Goal | Location |
| --- | --- |
| Model, scale, rig profile, weapon, hand targets | the `Rig` node of `art/characters/mira_0/runtime/mira_0_unit_visual.tscn` (and `art/characters/mira_0/mira_0_rig_profile.tres`) |
| Camera anchors, timing of pickup/landing/hit returns, team ring | the root of the same scene (`TacticalCharacterAdapter`) |
| Pose and action preview | `tools/animation_workbench/pose_workbench.tscn` |
| Gameplay-to-animation requests, cover policy | `presentation/tactical/tactical_character_adapter.gd`, `cover_edge_selector.gd`, `cover_edge_policy.gd` |
| Blend states and fallback clips | `presentation/characters/rig/character_animation_controller.gd`, `character_fallback_animation_builder.gd` |
| Weapon sockets, IK, recoil, carry offsets, unarmed arms | `presentation/characters/rig/character_rig.gd` |
| Gait, stairs, ladders, paths | `presentation/characters/motion/` |
| Cover body motion (crouch, yaw, clearance) | `presentation/characters/motion/cover_posture_profile.gd` |

The generated fallback clips are placeholders and keep every tactical action functional while authored MIRA clips are prepared; assign an `AnimationLibrary` to the rig's **Clip Library** when authored clips exist. Run `.\tools\run_tests.ps1 fast -Subsystem animation` after changes. Presentation may alter transforms, poses, effects and timing; it must not change HP, AP, occupancy, line of sight, legality or replay outcomes.

The [asset-edge/hybrid workflow](asset-edge-placement.md) adds physical contacts to authored poses and enables supported within-cell standing points throughout current maps and editor previews/tests.
