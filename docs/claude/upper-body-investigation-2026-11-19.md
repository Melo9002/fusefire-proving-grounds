# Upper-body coordination investigation (animation improvement 05) — 2026-11-19

Investigation only. Production behaviour unchanged: the temporary `exp_kick` hook added to `character_rig.gd` for the experiments was removed and the file restored byte-identical (sha256 4157ee77...5da5). Probes and variants live in the session scratchpad, not the repo.

Method: production `UnitVisualAdapter` path, sampled in the skeleton's post-modifier callback (HandContactDiagnostics plus extra bone landmarks). Direct: bone positions, elbow angles, wrist-to-target error, stock vs shoulder pocket. Approximate: eye position (no eye bones or meshes: head top minus 0.12 m, 0.085 m forward; sweep of 0.08-0.16 m / 0.06-0.11 m gives +/-3 cm), sight (profile point; checked against mesh: optic top 0.143 m, profile 0.13 m at the optic's rear end, bore 0.064 m).

## Drift at the shot (support palm shift in the weapon frame, mm; elbow degrees)
| Variant | Standing | Crouch | Kneel |
| --- | --- | --- | --- |
| Production | 25.8 (165 to 180) | 31.7 (174 to 180) | 30.9 (180) |
| Chest kick removed | 0.0 | 0.0 | 3.4 (pre-existing at-limit deficit) |
| Chest kick x0.5 | 9.6 | 15.8 | 14.8 |
| Weapon follows chest kick (torso frame) | 0.6 | 5.1 | 5.6 |
| Weapon-only kick 2.35 deg, no chest | 2.4 | 2.4 | 3.4 |
| Chest x0.4 + weapon 1.9 deg | 6.4 | 12.6 | 11.8 |
The earlier 33.1 / 45.8 mm figures included the body rising from hide to peek during the shot; held-aim shots measure 25.8 / 31.7 / 30.9.

Cause: the shot clip kicks the chest (yaw about +8 deg, pitch/roll a few degrees). The weapon stays in the root frame and only follows the right shoulder's position, while the support shoulder turns with the chest, so the support target moves away from the support shoulder; the arm, already near full reach, cannot follow. The drift peaks at ~0.19 s (chest yaw peak), not at the pitch kick (0.07 s).

## Elbows and reach (aim, standing / crouch / kneel)
Production 165 / 174 / 180 deg. 10 deg torso twist (left shoulder forward): 130 / 134 / 137 deg and protraction need falls to the 14 deg base. 20 deg: 109 / 112 / 114. Support grip moved 20 to 14 cm: 129 / 132 / 135; to 10 cm: 114 / 116 / 118 (grip location is profile data; not recommended without review). Cause: stock-to-support-grip (~0.49 m) is about the arm length (shoulder to wrist ~0.47 m).

## Eye to sight (perpendicular distance, standing aim / crouch / kneel)
Production 0.148 (0.119-0.181) / 0.130 / 0.120 m: eye ~11.6 / 7.4 / 5.4 cm above the optic axis and 9-11 cm left of it. Bounded head+neck adjustment (yaw 25, pitch 20, roll 15 deg total): 0.066 / 0.035 / 0.030 (saturated in standing). With a 10 deg twist as well: 0.061 / 0.018 / 0.002. The adjustment as built jumped 98 mm in one frame (unsmoothed search), so it needs smoothing.

## Verdict
Recoil/torso: a torso-relative weapon frame fixes drift; a small weapon-only kick is the physically better recoil model. Elbows: whole-body torso turn, not more protraction. Eye: head/neck adjustment is bounded and helps only when combined with torso lean/turn. Details, candidates and acceptance criteria are in the task report.
