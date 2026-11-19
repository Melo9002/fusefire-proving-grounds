# Hand contact diagnostics (animation improvement 01) — 2026-11-18

Diagnostic tools only: nothing here changes how MIRA Zero is posed. Code is in `presentation/diagnostics/` and is created only by the pose workbench, tests and capture scripts; gameplay never carries it.

## Using it in the pose workbench

Open `art/characters/mira_0/demo/mira_0_pose_workbench.tscn`. The existing controls are unchanged. New keys:

| Key | Action |
| --- | --- |
| H | Hand diagnostics on or off (overlay and readout; nothing exists until the first press) |
| J | Marker labels on or off |
| G | Mark the current hand contact as the reference for the "contact shift" readout |
| Z | Pose preset: standing, crouch, half-kneel (drives the existing `CoverCrouchModifier` with the adapter's ramp speeds; no cover yaw) |
| X | Diagnostic camera: workbench, full body, dominant-hand close-up, support-hand close-up, both hands and weapon (the close-ups follow the hands) |

Press 3 (aim) or 4 (shoot) first, then H. The workbench plays the `aim` clip under the crouch presets, while the game plays the `cover_low` clip with a held aim, so workbench numbers for kneel and aim differ from the production path; use the capture script for production-path baselines.

## Colour key

Dominant hand: IK target orange, wrist yellow. Support hand: IK target blue, wrist cyan. Palm (approximate, from bones) magenta; intended palm (from the weapon profile) green; the line between them is red. Weapon points white. Elbow violet, elbow pole pink. Fingertips take their hand's wrist colour. Reach line (shoulder to wrist) runs green to red as the arm runs out of length (a drawing scale, not a limit). Axes from each palm: finger direction red (actual) and pale red (intended); palm normal lime (actual) and pale lime (intended).

## What is measured

Everything is world space, metres, sampled in the `skeleton_updated` callback (the final pose).

| Measurement | Kind |
| --- | --- |
| Wrist to IK target; wrist and elbow and shoulder positions; elbow angle | direct |
| Arm reach, arm length (from the rest pose), reach margin and fraction | direct |
| Finger direction error against the weapon-derived direction | direct (from the hand bone) |
| Palm centre (midpoint of wrist and the knuckle line), palm to intended contact, palm in the weapon's frame, contact shift since mark | approximate (the skeleton has no palm bone) |
| Palm normal error | approximate (the knuckle plane; sign from the rest pose) |
| Finger joints and thumb tip to the grip centre point | approximate (the profile has no grip radius or surface) |
| Weapon orientation against the rig's expectation | direct |

## Why only the post-update sample is final

Outside the `skeleton_updated` callback, `Skeleton3D.get_bone_global_pose` returns the animation pose without the crouch, arm IK and hand grip modifiers. Sampled from a `_process` while the character moves, wrists came out up to 0.75 m from where they are drawn (palms 0.82 m, weapon orientation 0.04 deg). That is a different pose, not a slightly old one. So `HandContactDiagnostics.latest` is only written from a listener connected after the rig's own weapon alignment, and `sample_unsynchronised()` exists only to show the difference. The production update order was not touched.

## Baselines and captures

`tests/hand_contact_capture.gd` (explicit-only) drives the production `UnitVisualAdapter` through the game's own states and cover contexts and writes full-body sheets, hand close-up sheets and `docs/claude/hand-contact-baseline-2026-11-18.json`:

    godot_console --path . --script res://tests/hand_contact_capture.gd -- <directory> <tag> [poses]

Without a display it writes the numbers only. The numbers for settled poses are repeatable; transition peaks depend slightly on frame timing.

## Limits

No mesh contact or penetration is measured. The palm is estimated. Palm roll is compared with an assumption the production grip also makes (rest palms face down); the measurement shows the rest palm is tilted 11.0 deg (dominant) and 9.2 deg (support), which is what the constant 9 to 11 deg palm-normal error is. Not play-tested by a person; headless numbers are not visual confirmation, the screenshots are.
