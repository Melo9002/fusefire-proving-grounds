# Procedural animation layer: approach and next steps

Status 2026-11-18. This records how the procedural pass on MIRA Zero and the AUG was built, how it was checked, what it does not do, and the order in which to continue. It is **presentation only**: nothing here reads or writes tactical state, replay data or pathing. The result was reviewed by the project owner, who judged it considerably better than the previous placeholders and far from finished.

## What it does today

- **Held Aim.** A committed Aim keeps the sights up until the attack, a cancelling action or the next activation (`unit_visual_adapter.gd`, `AIM_RELEASE_GRACE`).
- **Low-cover stance** (`cover_crouch_modifier.gd`). Behind low cover the unit crouches only as deep as the cover is tall, never past what a person can do. Cover lower than a crouch can hide behind sends her down on one knee. She hides with her back to the wall, and turns to face it, sights up and eyes just over the top, when she aims.
- **Weapon handling** (`weapon_handling_profile.gd`, `character_rig.gd`). The stock sits in the shoulder pocket, each palm is placed on its grip (pistol grip and front handle) and both hands are turned to face them.
- **Hands** (`hand_grip_modifier.gd`). Fingers curl around the grips and the trigger finger pulls on each shot.

## How it was built

**1. Measure first.** Scripts cannot judge motion, so every claim is backed by a number or a rendered sheet.

| Question | Tool |
| --- | --- |
| Where is the eye, stock, hands and muzzle in each pose? | `tools/quality/aim_pose_report.gd` |
| Which local bone axis swings a limb forward or sideways? | `tools/quality/bone_axis_probe.gd` |
| Is the crouch within limits, feet planted, balanced? | `tools/quality/crouch_probe.gd` |
| Where are the grips in the weapon mesh? | `tools/quality/weapon_clusters_probe.gd`, `weapon_profile_probe.gd` |
| Where are palms, wrists and the stock relative to the grips and shoulder? | `tools/quality/grip_probe.gd` |
| What does it look like? | `tests/pose_review_capture.gd` (front, side, back, three-quarter, eye along the sights), `hand_views_capture.gd`, `weapon_closeup_capture.gd` (rendered, explicit-only) |

Rendered review sheets use cameras that follow the character's facing. Fixed world cameras gave false pictures once she turned away from them.

**2. Read the real pose.** `BoneAttachment3D` follows the rendered, skinned pose including IK. Reading bone poses directly gave misleading numbers.

**3. Measure each skeleton's axes instead of assuming them.** On this MIRA skeleton, local X swings limbs sideways and local Z swings them forward and back. The old generated leg recipes assumed the opposite, which is why knees bent sideways. `CoverCrouchModifier` and `HandGripModifier` detect the forward and curl axes from the rest pose at setup, so they work on other skeletons too.

**4. Solve, do not animate, the parts that depend on the situation.**

- *Crouch:* an analytic two-bone solve (thigh and shin) for a requested hip drop with the ankle planted, plus a level foot. Knee flexion, hip flexion and shin lean are capped, which defines the deepest natural crouch.
- *Balance:* the hips move back until the whole body's centre of mass lies over the feet (a mass-share model, found by bisection), and the torso leans forward with depth. A leaning torso therefore needs the hips further back, as in life.
- *Cover height to depth:* hiding wants the head just under the top, peeking wants the eyes just over it, blended by the aim pose. Anything beyond the human limit becomes the half-kneel.
- *Half-kneel:* the rear knee rests on the ground under the hip, so hip height follows from the thigh length; the front leg is solved with its shin leaning slightly forward. No per-body tuning.
- *Hands:* a hand frame is built from its finger direction and palm normal and mapped from the rest T-pose (palms down) onto the weapon's grip axes. Wrists are placed by the arm IK; this step fixes the hand's roll, which the IK leaves to chance.

**5. Derive placement from data.** The grips were located by clustering the AUG mesh vertices below the barrel line. The profile holds the rifle's scale, the stock's rear plate, the pistol grip, the front handle and the hand posture, in the model's own frame. The rig derives the stock, hand and wrist offsets from it and from the real hand size. Another weapon needs only another profile.

**6. Respect physical limits instead of hiding them.** The support arm is 0.47 m long and was already fully extended with the stock correctly in the pocket, so a full-size AUG's front handle was out of reach. The rifle is drawn at 82% (`WeaponHandlingProfile.scale`); the shoulder reaches forward and the torso leans slightly while aiming.

## Pitfalls found (so nobody repeats them)

- The rig rewrites `weapon.basis` every frame; a node scale set elsewhere is silently lost. The scale is now re-applied with the basis.
- A newly added `class_name` needs a second `godot --headless --import` pass before scripts that use it will load. A fresh clone needs one editor import. Parse errors can be hidden in import output; load the script directly to see the real message.
- Skeleton modifiers run in child order: crouch, then arm IK, then hand grip. Reordering breaks the pose.
- `get_bone_global_pose` is only reliable inside a modifier's own processing.
- GDScript's `:=` cannot infer a type from an untyped array element.
- A test must be able to fail: one placeholder assertion (`... or true`) was caught and replaced by a real check.

## Verification

- `tests/cover_crouch_test.gd`: limits, planted feet, forward-only knees, kneel on very low cover, standing back up, aiming never deeper than hiding.
- `tests/cover_crouch_battle_test.gd`: a real battle unit goes to the cover pose beside a 0.9 m wall, kneels, rises to aim, faces the wall, and writes no tactical state (fingerprint compared).
- `tests/aim_hold_presentation_test.gd`: the held Aim.
- All subsystem suites (assets, combat, movement, AI, replay, UI) passed before each push.

**What this does not prove:** that the motion looks natural. Headless success establishes constraints, not appearance. The only judge of quality here was rendered review and the owner's eye.

## Known limits

- The eye sits about 20 cm above the sights when aiming; the sight picture from the eye is off.
- The hand mesh is blocky, so fingers on grips look rough close up. Finger poses are a single curl value, not authored shapes.
- The generated leg clips for move, vault, climb and descend probably bend the legs the wrong way on this skeleton (same cause as the old crouch). Not checked.
- The kneel is one fixed pose family (right knee down); there is no transition animation, only blending, and no foot or ground-contact IK.
- The rifle is scaled to 82% and the stances were tuned on one body and one weapon.
- No reload, Guard or Shield visuals, no recoil additive, no wall probe, and defeat is still a simple topple.

## Next steps, in order

1. **Author the base clips in Blender 5.2** (idle, move, aim, shoot, cover, traverse). Keep the skeleton's `mixamorig_*` names and import through `tools/import_animation_clip.gd` and the animation workbench. The procedural layers stay on top of authored clips: they only set hips, legs, spine lean, hands and fingers, and act only in the states that request them (low cover, the aim pose, holding the weapon). Confirm each against the authored clips when they arrive.
2. **Align the eye with the sights.** Add a head, neck and upper-spine pitch solve with a small shoulder-pocket raise, accepting `eye_off_sight_line` of about 0.05 m or less from `aim_pose_report.gd` while keeping the stock at the shoulder and the support hand on its grip.
3. **Fix or replace the leg clips** using the measured axes (`bone_axis_probe.gd`), then check each state with the review sheets.
4. **Author finger and grip poses** in Blender (one pose per grip type) and drive them from the profile instead of one curl value.
5. **Reload, Guard and Shield** as masked upper-body layers that look the same in cover or in the open.
6. **Ragdoll on defeat** with soft joint limits and tension, presentation only, skipped in headless.
7. **Second weapon profile** (non-bullpup) to prove the profile is general, plus a wall probe that lifts to a high ready near geometry.
8. **Foot and ground-contact IK, recoil additive, kneel transitions.**

Review every change with the capture tools above and the owner's eye. Do not claim motion quality from headless tests.
