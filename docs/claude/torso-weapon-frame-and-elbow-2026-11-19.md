# Torso-relative weapon frame and crouched elbow investigation (animation improvement 05A) — 2026-11-19

Production change (torso frame) plus investigation (elbow). Not committed.

## Torso-relative weapon frame
`CharacterRig.update_torso_frame(chest_in_root, delta)`, called from `WeaponPoseModifier` in the same skeleton pass, before the targets are placed. Modifier order is unchanged: CoverCrouch -> WeaponPose -> WeaponArmIK -> HandGrip. The chest's orientation in the character-root frame is compared with a settled reference that follows the chest every pass except while the chest kicks (shoot states), when it is held. While held, `torso_frame` is the chest's rotation since it settled; otherwise it eases to identity over 0.06 s. `_rifle_local_basis()` (weapon orientation and support target) and the aimed grip (`aimed_grip = shoulder - torso_frame * (stock + grip offsets)`) both use it, so the weapon turns about the stock, the stock stays in the pocket and both hands use one frame. Cover yaw and facing turn the root, so they never enter it. `torso_frame_enabled = false` restores the root-frame weapon. Hit reactions are excluded on purpose (their chest swing is ~40 deg and the weapon would whip without any contact benefit).

| Support palm shift at the shot | Before | After |
| --- | --- | --- |
| Standing | 25.8 mm | 0.6 mm |
| Crouch | 31.7 mm | 4.0 mm |
| Half-kneel | 30.9 mm | 4.4 mm |
| Full cover (shoot_left) | 40.2 mm | 7.1 mm |
Firing hand 0.7 mm shift, stock within the recoil's own 5.2 mm, relaxed handling identical on and off. Test: tests/unit_visual_torso_weapon_frame_test.gd (57 checks).

## Crouched elbow: root cause
The dominant (right) arm is 72 deg bent with 192 mm of reach to spare, so its elbow position is set entirely by the IK pole. The aim pole (`right_elbow_aim`) is a fixed point in character space at standing height; only the relaxed pole gets the crouch body offset. As the shoulders drop and the chest pitches forward, the pole stays put:

| Right elbow (chest frame) | Standing | Crouch | Half-kneel |
| --- | --- | --- | --- |
| Height vs shoulder | -9.0 cm | +5.0 cm | +16.3 cm |
| Elbow off the shoulder-wrist line, upward | -8.0 | +1.6 | +11.3 |
| Pole height vs shoulder | -13.7 | +1.5 | +31.1 |
| Swivel | -65 deg | -95 | -129 |
| Upper-arm elevation | -21 deg | +11 | +41 |
Outward flare 14-18 cm in all. The left (support) arm is 165-180 deg, so its bend plane is nearly undefined; it shows no elevation relative to the shoulder-wrist line. Not the solver, not reach, not clavicle rotation: the pole is in the wrong frame.

## Pole strategies (temporary, not in production)
| Strategy | Right elbow up from line (standing / crouch / kneel) | Swivel jump in transitions |
| --- | --- | --- |
| Production | -8.0 / +1.6 / +11.3 cm | 2-3 deg per frame |
| Aim pole follows the body offset | -8.0 / -8.5 / -8.3 | 0.0-1.2 |
| Pole fixed in the chest frame | -7.4 / -6.3 / -5.7 | 0.2 |
| Shoulder-wrist geometry, standing swivel kept in the torso frame | -7.4 / -7.3 / -7.1 | 0.0 |
| Zero swivel (elbow hangs) | -18.8 / -18.4 / -17.9 | 0.0 (changes the standing look) |
Recommended: derive each arm's swivel in the torso frame from the existing standing elbow guides at setup, then build the pole from shoulder, wrist target and torso frame every pass. No posture angles, no new constants, no flips (the 170 deg "jumps" in a first pass were the straight left arm, whose plane is undefined).
