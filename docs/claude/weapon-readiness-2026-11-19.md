# Weapon readiness and attack sequencing (animation improvement 04) — 2026-11-19

Production change, not committed. Presentation only: no tactical code, AP, damage, legality, replay data or AI was touched.

## Model
`WeaponReadiness` (presentation/characters/runtime/weapon_readiness.gd): LOWERED, READY, AIMED, STOWED. Sources request a level by name (`request_readiness` / `release_readiness` on the adapter); the highest wins. The aim stance and a held Aim imply AIMED; a carrier reports STOWED. `aim_blend` stays the single scalar and now follows its target every frame (up over `raise_seconds`, down over `lower_seconds`) instead of a fixed 0.28 s tween. A future Guard asks for READY/AIMED the same way an attack does.

Profile data (`WeaponHandlingProfile`, Readiness group): lowered carry angles and grip (moved from the rig, AUG values unchanged), `ready_blend` 0.6, `raise_seconds`/`lower_seconds` 0.28, `alignment_tolerance_degrees` 1.0, `shot_recover_seconds` 0.34, `max_raise_wait_seconds` 0.8.

## Attack sequence (UnitVisualAdapter.present_attack)
Raise -> Align -> Fire -> Recover -> Release. Aligned means muzzle within tolerance of the firing pose and, in cover, the body turned into its aiming yaw. The shot (flash, recoil, trigger) starts only then; from an aimed pose it is immediate. After `shot_recover_seconds` the attack request is dropped and the unit returns to whatever it otherwise holds. Time is summed frame deltas, not wall time; `attack_timeline` records phase times, blend and muzzle error. A watchdog fires anyway after `max_raise_wait_seconds`. Hit, defeat, move, pickup, boarding and a newer attack cancel a pending sequence. Carriers show the shot at once (legacy path).
The presenter waits (`_wait_for_shot`, bounded) so the target reacts after the shot; the tactical result was committed before presentation and is untouched.

One cover change: a shot from cover keeps the cover pose (`_cover_kind` counts shoot states), otherwise crouched and kneeling attacks stood up mid-shot.

## Before / after (standing, from relaxed)
| | Before | After |
| --- | --- | --- |
| Flash | 0.007 s, muzzle 51 deg off | 0.277 s, muzzle 0.9 deg off |
| Aligned window | ~0.1 s | whole shot |
Cover (crouch, kneel): shot at 0.467 s (body turn limits it). From aimed or a sustained request: 0.000 s.

## Hand contact (production path, mm)
| Case | Firing wrist | Support wrist, raise | Support wrist, shot+recover |
| --- | --- | --- | --- |
| Standing | 0.0 | 0.0 | 25.9 |
| Guard (aimed) | 0.0 | - | 25.8 |
| Crouch (cover 1.1) | 0.0 | 2.3 | 33.1 |
| Kneel (cover 0.9) | 0.0 | 12.1 | 45.8 (aimed control 46.5) |
The 25.8 mm shot transient is unchanged; raising first adds none. Stock is within about 2.5 mm of the shoulder pocket at the shot (it was 6.6 mm at a 3 deg tolerance, hence 1 deg).

## Known issues
Support elbow near-straight (165-180 deg) at the shot in standing/crouch/kneel (improvement 02 limit). Weapon orientation still follows the character root, not the torso; no spine IK or general recoil. Cover raise takes ~0.47 s because the yaw turn (320 deg/s) gates alignment. Eye-to-sight not re-measured. Hit-reaction peak pose unverified.

## Tests
`tests/unit_visual_weapon_readiness_test.gd` (81 checks); `tests/weapon_readiness_capture.gd` (explicit-only filmstrips + JSON). Suites: assets 12, combat 42, replay 19, missions 17, ui 27 all pass.
