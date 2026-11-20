# Cover posture, firing stability and pose ownership (stabilization 03)

## 1. Root causes (measured, not assumed)

| Symptom | Cause | Evidence |
| --- | --- | --- |
| Units take cover "turned away from threats" | The cover pose was a **fixed yaw offset**: `HIDE_YAW_DEGREES = -150` (back to the wall) while protected, `-90` side-on to peek around full cover, always to the unit's own right. It knew nothing of the wall's ends. | `cover_probe`: protected `rootyaw -150`. Tests `cover_crouch_test` / `cover_crouch_battle_test` asserted "her back is to the wall". |
| Rifle swings wildly when firing from cover | (1) Aiming swept the body through 150 degrees at 320 deg/s (muzzle yaw 110 degrees in half a second). (2) On the return to cover `present_idle()` called `face_world_position(wall)`, which **snapped the whole rig** by the angle between target and wall (a 43 degree single-frame muzzle jump). (3) **Ownership conflict:** `CharacterAnimationController._apply_visual_root_state` tweened the visual root's *whole rotation* (yaw included) to zero on every `play()`; the cover yaw, written each frame, was overridden while a tween was alive and released with a jump when it ended. | Per-frame muzzle samples: before, worst step 43.3 deg/frame; the root yaw read 0.0 while `_cover_yaw` was -10..-23, with the tween running, then jumped to -23 in one frame. After: worst 1.3 deg/frame. |
| Cover pose lost during a hit | `_cover_kind()` only recognised cover/shoot states, so the `hit` state read as "no cover": the unit stood up and unturned for the hit clip, then went back. | Code reading; now held (`_held_cover_kind`) and tested (crouch depth stays above 0.2 through a hit). |
| Stock in the shoulder when moving | Held (ready) carry placed the firing hand with a *backward* 2 cm walking offset, in the character's frame (it did not follow the shoulder's lean or bob). | Stock to shoulder joint 0.084 m idle, 0.08 m running (inside the shoulder); now 0.119 / 0.136 / 0.136 m. |

Defect classes: tactical-facing defects: none (facing, cover contact and protection rules are untouched); the awkward look was entirely the presentation offset, the snap on facing changes, and the controller/adapter ownership conflict.

## 2. Edge selection (`CoverEdgeSelector`, pure geometry)

Rules: each end of the wall (left and right as the unit faces it) is a candidate with a distance along the wall. An edge is **usable** when within `edge_reach` (2.2 m) and the
ground just past the end, and every cell between the unit and it, is walkable, not cover and not occupied. One usable edge: that one. None: `NONE` (protected posture, no pretence of
seeing around the wall). Both usable: the nearer; if within `tie_tolerance` (0.25 m), the right. **Hysteresis**: the current side is kept unless the other is nearer by more than 0.35 m.
Independent of facing and of enemies (the analysis holds geometry only).

Wall extent: tile maps scan neighbouring cover cells (`wall_scan_limit`); surface maps use the contact's AABB (`bounds`, added to `cover_at`, from authored shot parts and
box presentation parts). **Cylinders and other round obstacles have no clean end, so they give `NONE`** (documented limitation; their AABB is not exposed).

## 3. Facing contract

The rig's yaw is the tactical/observation facing (toward the wall idle, toward the target attacking); nothing here rewrites it. The cover pose is a yaw **offset** (`character_root`):
protected turns `protected_yaw_degrees` (45) toward the chosen edge; aiming over LOW cover is square; aiming round FULL cover turns `peek_yaw_degrees` (20) toward it and leans that way
(`shoot_left/right` follow the chosen side). A facing change that arrives at once is absorbed into the offset (world yaw continuous) and the body eases at `turn_degrees_per_second`; outside cover
the same change is the locomotion turn-in-place twist.

## 4. Ownership

Modifier order verified (Locomotion, CoverCrouch, WeaponPose, WeaponArmIK, HandGrip). Cover owns hips drop, legs, kneel, spine lean (CoverCrouch) and the root yaw (adapter). The weapon pose and arm IK own
the arms and rifle; a hit reaction (animation clip) plays over the cover legs/yaw, which are held. The controller's visual-root tween now resets only the lean axes and position, never yaw.
Shared pure functions (`CoverPostureProfile.yaw_offset`, `crouch_request`) are used by both the game and the workbench.

## 5. Cover bench (workbench)

The test panel's Cover row: Low, Low aim, Left edge, Right edge, Tie (right), No edge, Peek aim, Leave, plus an optional diagnostics overlay (wall, edge markers: green usable/red not, chosen larger;
facing blue, weapon red, wall normal green) and a Behind camera. Default off. Production selector and profile, synthetic wall.

## 6. Parameters

`CoverPostureProfile` (exported by `CharacterRig.cover_profile`): edge reach, tie tolerance, tie side, hysteresis, wall scan; protected and peek yaw, turn rate; crouch depths and clearances, crouch and kneel speed.
`WeaponHandlingProfile.ready_clearance` (stock clearance of the held rifle).

## 7. Limitations

Round obstacles give no peek side. Tall-wall firing needs a tactically legal attack, which needs line of sight: from directly behind a full wall there is none, so the aim pose around a full wall is exercised in the bench
and by the `shoot_left/right` mapping, not by a live shot in the test fixture. The existing `shoot_left/right` clips lean by a fixed hip offset; their direction was not re-verified against every orientation. No
distinct elevation-dependent firing posture. Hit reactions are the existing single clip.
