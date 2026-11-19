# Swivel-preserving elbow guidance (animation improvement 05B)

## Cause and approach

The aim elbow poles (`right_elbow_aim`, `left_elbow_aim`) are fixed coordinates in standing character space. Only the
relaxed poles received the crouch body offset. When the body dropped, the shoulder and wrist went down but the pole stayed
at standing height, so the bend plane rotated about the shoulder-wrist axis: the right elbow went from 9.0 cm below the
shoulder (standing) to 5.0 cm above (crouch) and 16.3 cm above (half-kneel), flared 14 to 18 cm outward. Reach was not the
cause (192 mm of margin); the pole alone dictated it.

The guidance builds the pole each pass from the shoulder, the wrist target and the chest's down, using the swivel the
elbow has in the standing aim. The bend plane is therefore carried with the torso. Moving the pole down by a constant
would fix one posture and break another, and would also ignore lean, kick and arm geometry. This keeps whatever elbow
direction the standing guides already define, in every posture.

## Algorithm and coordinate spaces

`CharacterRig.apply_elbow_guidance(shoulders, chest_world)`, called from `WeaponPoseModifier._guide_elbows` after the hand
targets and the support-reach adjustment, in the same pass and before WeaponArmIK. Order is unchanged:
CoverCrouch, WeaponPose, WeaponArmIK, HandGrip.

World space throughout; poles written in their parent's local space.

1. `axis` = normalized (wrist target - shoulder), both in this pass.
2. `down` = minus the Y of the chest's world orientation. The chest orientation is the root frame turned by the chest's
   change from its rest pose (this carries crouch lean and shot kick, not the rest-pose bone axes).
3. `reference` = `down` with its component along `axis` removed.
4. `swivel` = signed angle about `axis` from `reference` to the elbow direction of the standing guide. It is read from the
   guide (plus the crouch body offset, which is zero standing) every pass until the aim has fully raised
   (`weapon_blend() >= 0.99`), then held. Per arm.
5. Pole = midpoint of shoulder and wrist + `reference` rotated by `swivel` about `axis`, at 0.35 m. Only direction matters
   to the solver.
6. Final pole = `lerp(ready pole, aim pole, weapon_blend())`: relaxed handling is exactly unchanged (blend 0 returns early).

Fallbacks: if the chest-down reference is unstable (arm axis nearly vertical, `ELBOW_REFERENCE_MIN`) the existing guide is
kept for that arm; a degenerate arm axis is skipped. `elbow_guidance_enabled = false` restores the fixed guides (A/B
reference). Neither wrist target, reach nor flexion changes: the pole only picks the bend plane.

## Measurements (production path, `tests/unit_visual_elbow_guidance_test.gd`)

Right (firing) elbow, chest-local, before / after:

| Pose | Height vs shoulder | Swivel | Flexion | Wrist error | Reach margin |
| --- | --- | --- | --- | --- | --- |
| Standing aim | -9.0 / -8.3 cm | -65 / -67 deg | 72 / 72 | 0.00 / 0.00 mm | 191.9 / 191.9 mm |
| Crouched aim | +5.0 / -3.8 cm | -95 / -67 deg | 72 / 72 | 0.00 / 0.00 mm | 191.9 / 191.9 mm |
| Half-kneel aim | +16.3 / -1.9 cm | -129 / -67 deg | 72 / 72 | 0.00 / 0.00 mm | 191.9 / 191.9 mm |

The standing swivel differs by 2 degrees because the guidance measures against the chest's down rather than the root's.
The support (left) arm is nearly straight in every pose (flexion 165/174/180 deg, bend offset under 2 cm), its wrist error
and reach margin are identical before and after (0.00/0.00/3.43 mm error; 3.9/0.6/0.0 mm margin). Its swivel is not
claimed.

Shots (support palm shift / stock / firing wrist / elbow-plane change during the kick): standing 0.6 mm / 5.2 / 0.000 / 0.0
deg; crouch 4.0 / 5.2 / 0.000 / 0.0; half-kneel 4.4 / 5.2 / 0.000 / 0.0. Identical to the 05A results.

## Transitions (per-frame worst over 3 s, after / before)

| Transition | Swivel jump | Elbow jump | Pole jump | Wrist error | Highest right elbow vs shoulder |
| --- | --- | --- | --- | --- | --- |
| aim to crouch | 0.00 / 2.04 deg | 5.8 / 6.6 mm | 8 mm | 0.00 / 0.00 mm | -3.8 / +5.0 cm |
| crouch to half-kneel | 0.00 / 2.14 deg | 9.2 / 9.2 mm | 13 mm | 8.22 / 8.22 mm | +0.1 / +17.8 cm |
| half-kneel to aim | 0.00 / 2.66 deg | 8.1 / 11.3 mm | 15 mm | 3.66 / 3.66 mm | -0.8 / +18.3 cm |
| aim to half-kneel | 0.00 / 3.12 deg | 10.1 / 10.7 mm | 14 mm | 4.56 / 4.56 mm | -1.4 / +16.5 cm |

No flips, no pole snapping, and the existing transition wrist errors (support reach, 05 baseline) are unchanged.

## Remaining

- The swivel latches at the first fully raised aim. A unit whose first aim happens in cover latches from the guide shifted
  by the body offset (about 3 degrees different from a standing latch; measured -62 vs -65). Order-dependent, presentation only.
- The right elbow stays about 2 to 4 cm higher relative to the shoulder than standing when kneeling, because the torso
  leans; the swivel itself is constant.
- Support arm stays near-straight (layout: stock-to-support-grip distance is about the arm length). Torso turn and head
  alignment remain out of scope.
- Hit reactions still keep the root-frame weapon (05A).
