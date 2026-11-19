# Weapon pose modifier (animation improvement 02) — 2026-11-18

Corrects the stale-shoulder dependency found in the support-hand reachability investigation. Production change, not committed.

## What it does

`WeaponPoseModifier` (`presentation/characters/runtime/weapon_pose_modifier.gd`) is a `SkeletonModifier3D` that runs between the crouch layer and the arm IK. Modifier order is now:

    CoverCrouch -> WeaponPose -> WeaponArmIK -> HandGrip

It reads the right shoulder in the current skeleton pass (which includes CoverCrouch's hips, spine lean and clavicle changes) and calls `CharacterRig.apply_weapon_targets(shoulder_world)`, which holds the unchanged formulas for the stock pocket, both hand targets and the elbow poles. `CharacterRig._update_weapon_pose` still runs in `_process` but now only prepares what does not need the shoulder (carry sway, crouch and grip inputs). No previous-frame cache is used.

`weapon_pose_modifier_enabled = false` on the rig restores the legacy path (targets from the animation-only shoulder). It is also the fallback for the editor preview and the A/B switch used by the tests and by `tests/hand_contact_capture.gd ... legacy`.

## Reach adjustment

CoverCrouch still applies the base support-shoulder protraction (`SUPPORT_REACH_DEGREES`, 14 degrees while the weapon is up). After the targets are placed, the modifier checks how bent the support elbow would be at the target's distance (law of cosines on the arm's own two segment lengths, measured from the rest pose). If the elbow would be straighter than `support_elbow_comfort_degrees` (default 165), it adds the least extra protraction that reaches that bend, found by bisection on the existing clavicle rotation (`CoverCrouchModifier.set_support_reach`). It never exceeds `support_protraction_limit_degrees` in total (default 18), never applies extra when it would not bring the hand closer, never stretches a bone, never moves a target, and leaves the shoulder exactly as the animation had it when nothing is added. Whatever the limit leaves unreached is published as `report` (`deficit`, `comfort_deficit`, `limited`, `elbow_degrees`, protraction values) and shown by the hand-contact diagnostics.

### Why 18 degrees

Anatomy references (StatPearls, Kenhub, GPnotebook, Wikimsk) give about 30 to 35 degrees for the whole protraction-retraction range of the sternoclavicular joint. From neutral that is roughly half in each direction: about 17 to 18 degrees of protraction. The existing base of 14 degrees leaves 4 degrees. The scapula also glides on the ribs, so real shoulders protract further, but that is not claimed. The sweep values 22, 26 and 30 degrees from the investigation were not adopted. Both limits are exported on the rig (`Weapon Pose` group), so another character or weapon sets its own; they are not universal constants.

## Result

Production path, before and after. Full tables and screenshots are in the task report; numbers are in `hand-contact-baseline-2026-11-18.json` (before) and `weapon-pose-baseline-after-2026-11-18.json` (after).

| Pose | Support wrist error | Support reach margin |
| --- | --- | --- |
| Standing aim | 0.0 to 0.0 mm | 26.7 to 3.9 mm (elbow 141 to 165 deg) |
| Crouch + aim | 0.1 to 0.0 mm | 0.0 to 0.6 mm |
| Half-kneel | 23.5 to 0.0 mm | 0.0 to 138.6 mm |
| Half-kneel + aim | 229.9 to 3.4 mm | 0.0 to 0.0 mm (limit reached, 3.4 mm still short) |

The stock sits in the real shoulder pocket (0.0 mm; was 26.9, 50.2 and 248.7 mm). Half-kneel to half-kneel + aim: support palm shift in the weapon's frame 182.6 to 3.8 mm.

## Known costs

- **Shot transient.** The weapon now follows the shoulder through the shot's chest kick, which asks the support arm for more reach than the limit gives: support palm shift peaks at 25.8 mm during the kick (was 10.9 mm). It lasts about 0.15 s.
- **Standing aim support elbow** is straighter (165 deg against 141) because the old margin depended on the stale shoulder.
- **Eye to sights** moves about 2 cm further from the rear sight in standing aim, because the stock now sits in the real shoulder pocket.
- **Crouch + aim and half-kneel + aim** reach their targets with a nearly straight support arm at the limit.
- **Low-ready hands in cover poses** now follow the real chest, by exactly the amount the real and animation-only chests differ (tested). The rifle no longer rides at head height in the crouch-hide pose.

## Tests

`tests/weapon_pose_modifier_test.gd` (50 checks): modifier order; the modifier's shoulder is the final one and a `_process` reading is 15 cm off in the half-kneel; stock within 2 mm of the pocket; wrist errors; reachability of each baseline pose; protraction never beyond the limit and unchanged where not needed; shoulder movement and bone lengths; a shorter support arm and a farther front grip give larger, reported, bounded deficits; transitions; the shot; unrelated states (idle, move, hit) unchanged against a legacy-to-legacy noise floor; carrying leaves the modifier idle. `tests/unit_visual_hand_contact_diagnostics_test.gd` still passes.
