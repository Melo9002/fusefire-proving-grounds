# MIRA Zero animation editing guide

MIRA Zero is FuseFire's supported character presentation path. Open `tools/animation_workbench/pose_workbench.tscn` to inspect poses and action states, and `art/characters/mira_0/runtime/mira_0_unit_visual.tscn` to tune the live unit.

The [asset-edge/hybrid workflow](asset-edge-placement.md) adds physical contacts to authored poses and enables supported within-cell standing points throughout current maps and editor previews/tests. Its movement, LOS and saved replay share the committed point; the visual adapter does not apply a separate cosmetic root shift. Existing cover and corner-shooting clips remain placeholders. New over-low-cover sequences and wall-hand/foot IK can follow without animation changing tactical authority.

## Where to edit

| Goal | Location |
| --- | --- |
| Model, scale, skeleton mapping, hand targets, and camera anchors | `art/characters/mira_0/runtime/mira_0_unit_visual.tscn` |
| Pose and action preview | `tools/animation_workbench/pose_workbench.tscn` |
| Gameplay-to-animation requests and return timing | `presentation/tactical/tactical_character_adapter.gd` |
| Blend states and fallback clips | `presentation/characters/rig/character_animation_controller.gd` and `character_fallback_animation_builder.gd` |
| Weapon sockets, IK, recoil, carry offsets, and model validation | `presentation/characters/rig/character_rig.gd` |
| Cover and traversal pose selection | `presentation/tactical/tactical_pose_context.gd` |

The generated fallback clips are placeholders and keep every tactical action functional while authored MIRA clips are prepared. Assign an `AnimationLibrary` to **Model Assets → Clip Library** on the MIRA scene when authored clips are ready. Keep the existing state names: `rifle_idle`, `move`, `aim`, `shoot`, `hit`, `defeat`, cover and traversal states, pickup/carry, and boarding.

Run `tests/unit_visual_adapter_test.gd`, `tests/locomotion_foundation_test.gd`, and `tests/tactical_pose_test.gd` after changes. Presentation may alter transforms, poses, effects, and timing; it must not change HP, AP, occupancy, objectives, or action results.

## Held Aim pose

A committed Aim keeps the sights up for as long as it lasts: until its attack, an action that cancels it (a Move), a Reload, or the next activation. `TacticalCharacterAdapter` follows the committed `tactical_state.is_aiming` flag each frame and never writes it, so replays and AI units behave the same. The Aim presenter also calls `present_aim()` so the sights come up the moment the action commits.

- The pose is the existing `aim` state. In cover the cover pose stays and only the weapon comes up. A carrying unit never raises a rifle. A shot, hit, defeat, move or traversal is never interrupted.
- After the flag clears the sights stay up for `AIM_RELEASE_GRACE` (1 s) so the rifle does not dip while the attack camera moves in before the shot. The shot or any other action takes over sooner.
- Test: `tests/aim_hold_presentation_test.gd` (24 checks, using the real Aim, Attack and Move actions). Before/after: [aim-hold-before-after-2026-11-18.png](quality/images/aim-hold-before-after-2026-11-18.png).
- Not done yet: the aim pose itself is still the old placeholder, so the stock is not yet solved onto the shoulder and the eye is not yet on the sight line. Reload, Guard and Shield still have no visuals.
