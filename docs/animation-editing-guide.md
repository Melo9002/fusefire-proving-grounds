# MIRA Zero animation editing guide

MIRA Zero is FuseFire's supported character presentation path. Open `art/characters/mira_0/demo/mira_0_pose_workbench.tscn` to inspect poses and action states, and `art/characters/mira_0/runtime/mira_0_unit_visual.tscn` to tune the live unit.

## Where to edit

| Goal | Location |
| --- | --- |
| Model, scale, skeleton mapping, hand targets, and camera anchors | `art/characters/mira_0/runtime/mira_0_unit_visual.tscn` |
| Pose and action preview | `art/characters/mira_0/demo/mira_0_pose_workbench.tscn` |
| Gameplay-to-animation requests and return timing | `presentation/characters/runtime/unit_visual_adapter.gd` |
| Blend states and fallback clips | `presentation/characters/runtime/character_animation_controller.gd` and `character_fallback_animation_builder.gd` |
| Weapon sockets, IK, recoil, carry offsets, and model validation | `presentation/characters/runtime/character_rig.gd` |
| Cover and traversal pose selection | `presentation/characters/runtime/tactical_pose_context.gd` |

The generated fallback clips are placeholders and keep every tactical action functional while authored MIRA clips are prepared. Assign an `AnimationLibrary` to **Model Assets → Clip Library** on the MIRA scene when authored clips are ready. Keep the existing state names: `rifle_idle`, `move`, `aim`, `shoot`, `hit`, `defeat`, cover and traversal states, pickup/carry, and boarding.

Run `tests/unit_visual_adapter_test.gd`, `tests/locomotion_foundation_test.gd`, and `tests/tactical_pose_test.gd` after changes. Presentation may alter transforms, poses, effects, and timing; it must not change HP, AP, occupancy, objectives, or action results.
