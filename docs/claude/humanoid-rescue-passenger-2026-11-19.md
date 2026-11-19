# Humanoid rescue passenger and fireman's carry (animation improvements 06 and 06A)

The orange box mannequin on a carrier is replaced by a second MIRA humanoid with its own skeleton, draped over the
carrier's shoulders in a static fireman's carry. Visual only: tactical pickup, carry, release, AP, occupancy and replay
data are untouched. Pickup and release timing, hand contact and passenger physics are not part of this stage.

## Architecture assessment (06A)

Ownership today:

| Concern | Owner |
| --- | --- |
| Rescue state (carrying, speed, hidden actor) | `TacticalUnit.carry_unit` / `release_carried_unit`, `ObjectiveManager` |
| Passenger creation, lifetime, boarding shrink | `UnitVisualAdapter.present_pickup` / `present_boarding` |
| Passenger skeleton, pose, placement on the carrier | `rescue_passenger.gd` + `passive_passenger_pose.gd` |
| Carrier clips (pickup, carry_idle, carry_move, boarding) | `CharacterFallbackAnimationBuilder._make_rescue_pose` |
| Carrier forward lean while carrying | `UnitVisualAdapter` (`CARRY_LEAN_DEGREES`) through `CoverCrouchModifier.aim_lean_degrees` |
| Weapon stowing, arm IK off while carrying | `UnitVisualAdapter.present_pickup` calls `CharacterRig.stow_weapon()`; where it hangs is `WeaponHandlingProfile` (Stowage) |
| Carrier hand targets | none: the carrier's arms are the clip's fixed angles (06B) |

No bone is driven by two systems: the passenger has its own skeleton with no modifiers; on the carrier, the clip owns the
arms and legs, the crouch modifier owns the spine lean, and the WeaponPose/IK layers are inactive while carrying
(`_update_weapon_pose` returns early). Duplication found: the demo workbench built its own passenger (now uses the same
`build` and `attach_to_carrier`). One ambiguity remains: the chest pitch in the old carry clips pitched about the bone's own
x axis, which leaned the carrier sideways on this rig (a 0.11 m lateral shift of the neck); that was an authoring defect, not
a conflict.

Verdict: the existing architecture is sufficient for 06A. Shared timing, contact constraints and authored blending belong
to 06B to 06D and need no coordinator yet: the passenger is a child of the carrier's presentation and is driven from one
place (the carrier's skeleton update). Nothing generic was added.

## Passenger

- `rescue_passenger.gd`: builds a second instance of the rig's own `character_scene` at the carrier's scale. No animation
  player, IK, grip, weapon, tactical actor or scripts inside the model. The importer's ragdoll scaffolding is removed.
  Public: `build(model_scene, scale)`, `attach_to_carrier(skeleton, root, chest_bone, neck_bone, anchor_from_neck)`,
  `presence` (1 to 0, tweened by boarding), `anchor_point()`.
- `passive_passenger_pose.gd`: the pose is bone DIRECTIONS in the body frame (x = body left, y = up the spine, z = facing).
  The body is face-down, so gravity is body +z: spine and thighs fold forward over the shoulder (`_fold`, `_leg` helpers read
  as angles), head, arms and shins hang near +z. Bone lengths never change. Mixamo names only.

## Reference frames and attachment

- The passenger's abdomen (the `Spine` bone) is the attachment point, never its root origin.
- It is placed `passenger_anchor_from_neck` (rig export, default `(0.05, -0.04, -0.19)` m, carrier frame: x left, y up, z
  forward) from the carrier's `Neck` bone, measured in the carrier's REST pose, so it scales with the skeleton. That relation
  is stored in the carrier's CHEST bone frame once and replayed on every `skeleton_updated` (after all modifiers), so the
  passenger leans, bobs and turns with the carrier's torso. The node's size is `presence`, never `scale`.
- Body orientation: `BODY_TO_CARRY` (face down, spine along carrier -x) then `CARRY_YAW_DEGREES = -45` so the head and torso
  hang behind the carrier and the legs hang at its side and front.

## Carrier posture

- Forward lean: `CARRY_LEAN_DEGREES = 20` through the crouch modifier's measured forward axis, eased over 0.4 s only in
  `carry_idle` / `carry_move`; the net trunk change is about 10 degrees forward of the idle stance. Outside carrying
  `_update_weapon_pose_inputs` rewrites the lean every frame, so nothing is left behind.
- The `carry_idle` / `carry_move` clips no longer pitch the chest about its own x axis (it leaned sideways). `pickup` and
  `boarding` clips are unchanged.
- Arms are unchanged (06B owns hand contact).

## Tests

`tests/rescue_passenger_visual_test.gd` (37 checks), all geometric relations: creation and cleanup, one extra skeleton, no
tactical unit / animation / modifier / script / weapon on the passenger, rifle stowed, abdomen on the anchor, every passenger
bone keeps its rest length, head and feet hang below the abdomen, the body is folded (not a plank), head behind the carrier
and feet further forward, loose elbows and unlocked knees, abdomen at shoulder height behind the neck, no joint within 0.2 m
of the centre of the carrier's head, forward lean under load (+8 to +25 degrees over idle), the carry lean is not in any other
clip, the relation to the chest bone is constant (below 0.5 mm) through walking, a move and a 110 degree turn, the pose is
unchanged while carrying, boarding shrinks it, and it is freed with the carrier. Carrier bones are read inside the skeleton
pass; outside it they lack modifier results.

## Provisional sling stowage (06B requirement)

- Where a weapon hangs while the carrier's hands are busy is weapon data, in `WeaponHandlingProfile` (Stowage group):
  `stowed_offset_from_neck` (the weapon's origin, measured from the carrier's neck bone in the carrier frame, rest pose) and
  `stowed_angles_degrees` (orientation in that frame; the AUG default `(90, 0, 0)` hangs it muzzle-down with the optic
  forward, at the carrier's right-front chest). The old rig exports `stowed_weapon_position/angles` are removed.
- `CharacterRig.stow_weapon()` / `unstow_weapon()` / `is_weapon_stowed()` do the work. The weapon is anchored with the new
  `ChestAnchor` (chest-bone frame, replayed every skeleton update), so it follows the torso's lean, bob and turn. The
  passenger uses the same class. Nothing is drawn, nothing swings, there is no strap constraint.
- Rescue code only calls `stow_weapon()`; it holds no weapon numbers. A different rifle supplies its own profile
  (tested: another profile moves and reorients the hang). A future sling configuration replaces these two values with a
  sling resource that yields an anchor transform (and later a strap); `stow_weapon()` is the one place to change.
- Outside carrying nothing changed: readiness, aim and fire code never run for the stowed weapon, and the existing
  readiness, weapon-pose, hand-contact and torso-frame tests are unchanged and pass.
- Clearance is tested as the weapon's butt-to-muzzle axis staying more than 0.12 m from every passenger bone segment in
  the normal carry pose. The weapon's mesh volume is not tested; against the carrier's own chest and right arm it was
  judged by eye only.

## Two-body contact (06B)

**Architecture.** The existing arm IK (`WeaponArmIK`, a TwoBoneIK3D with a target and an elbow pole per arm), the elbow
guidance (`apply_elbow_guidance`) and the hand grip (`HandGripModifier`) are reused; no second solver. The WeaponPose
modifier already places the targets inside the skeleton pass; while `carry_contacts_active()` it calls
`CharacterRig.apply_carry_targets` instead of the weapon formulas, then the unchanged order runs: CoverCrouch, WeaponPose,
WeaponArmIK, HandGrip. Ownership: while carrying, the weapon targets, torso frame and support reach are skipped, the weapon is
slung, `aim_blend` stays 0 and `HandGripModifier.orient_weight` is 0; the contacts own both wrists. `CharacterRig.begin_carry()`
and `end_carry()` switch this (the adapter's `present_pickup` and the workbench call them); `end_carry()` frees the passenger,
unslings the weapon, clears the contact grip, and the weapon pose rewrites targets, poles and grip on the next update
(tested: aiming afterwards matches a character that never carried, within 0.002 m).

**What was insufficient and the smallest extensions.**
- `HandGripModifier` oriented both hands to one weapon frame: it gained per-hand `contact_weight` / `contact_forward` /
  `contact_normal` (the weapon path is unchanged when the weights are 0).
- `apply_elbow_guidance` takes `carrying`: swivel comes from `carry_elbow_swivel_degrees` (right -60, left +60: elbows hang below
  the shoulder-wrist line and out), blend 1, no latch.
- `RescuePassenger.contact_frame` returns graspable places from the passenger's own bones (`CONTACTS`, a table of two bones, a
  fraction along them and a limb radius) and `anchor_world()`; the modifier uses the passenger's TRUE place from the chest in
  the same pass, because the passenger node itself follows after the pass.
- The arm IK is now ON while carrying (the old test asserted it off; that was the contract of the fixed-arm clip, updated on
  purpose). `carry_contacts_enabled = false` restores the fixed clip arms.

**Hand assignment.** The passenger's torso, head and arms hang behind the carrier's right shoulder and its legs at the
left. Measured with the passenger as built: the carrier's right shoulder reaches the passenger's LEFT wrist only if that arm is
brought forward (the right-hand wrist was 0.66 m away, the arm is 0.46 m); the left shoulder reaches the passenger's left thigh
easily. So: right hand holds the passenger's left wrist, left hand the passenger's left thigh just above the knee (fraction 0.9;
nearer the hip the elbow folded to 51 degrees). `CARRY_CONTACTS` in the rig is the assignment (a third value gives the
direction the hand comes from; the thigh is taken from the front so the hand is not trapped between the leg and the carrier's
hip).

**Passenger refinements (found with a random search over the pose against the carrier's torso, head and the reach window,
bone capsules only).** Anchor from the neck `(0.19, -0.025, -0.17)` (the abdomen over the carrier's left shoulder), yaw -28
degrees, thighs 77 degrees and shins 69 from the body's vertical, legs 0.09 apart, and the held left arm hangs from the shoulder
with the forearm raised toward the carrier's right hand (`held_upper`, `held_fore` in `PassivePassengerPose.DEFAULTS`, computed
from the target and the arm segment lengths). Residual: about 2 to 3 cm bone-capsule overlap of the passenger's thigh with the
carrier's torso (the legs hang against the carrier's hip); the mesh overlap is not measured.

**Measured contact (workbench pose, carry walk plus a 110 degree turn, hand-contact diagnostics sampled after the modifiers).**
Wrist to target 0.00 mm; palm centre to intended place 4.6 mm (right) and 7.0 mm (left); fingers along the intended direction 0
degrees; palm normal within 11 degrees (the palm estimate is approximate, from the knuckle plane); reach margin at least 27 mm
(right arm, elbow 141 degrees) and about 109 mm (left arm, elbow 100); target drift on the chest 0.000 mm; arm bone lengths
unchanged (0.0001 mm). Weapon axis (bone segments): 0.227 m from the carrier's arm bones, 0.195 m from passenger bones.

**Diagnostics.** The sampler uses the contacts as the hands' intent while carrying (intended palm = contact palm,
`contact_point`, intended finger and palm directions), so the existing overlay draws carrier wrist targets, actual wrists, palm
error, elbow, pole and shoulder-reach lines plus a white marker on each passenger contact. Off in normal play: only the
workbench, tests and capture scripts attach them.

## 06B.1: anatomical correction

**What was wrong.** The 06B arrangement came from a numerical search over reach and bone-capsule clearance. It satisfied both and
was anatomically wrong: yaw -28 degrees, abdomen 0.17 m behind the neck and a steeply folded spine hung the passenger down the
carrier's back (a piggyback), the held wrist was 0.65 m from the carrier's shoulder (arm 0.46 m), and the left hand was squeezed
between the passenger's thigh and the carrier's own hip.

**What a fireman's carry is, and the arrangement now.** The passenger lies belly-down ACROSS the carrier's shoulders, the
abdomen on the shoulders (over the carrier's left shoulder), the torso and head hanging down the carrier's right side and the legs
down its left, so the body bridges the neck like a coat over a rail. In carrier terms (x left, y up, z forward, from the neck,
rest pose): anchor `(0.12, -0.03, -0.10)` (abdomen just behind the neck line, over the left shoulder), yaw -8 degrees (almost
exactly transverse), spine fold `[2, 6, 14, 45, 70, 65]` degrees (lying nearly flat across the upper back, hanging only past the
shoulder), thighs 77 and shins 69 from the body's vertical. Measured (carrier frame): abdomen `(0.12, 1.37, -0.04)`, head joint
`(-0.24, 1.15, -0.17)`, feet at x +0.43 and +0.48; head and feet about 0.7 m apart sideways and about 0.3 m front to back.
Carrier lean is unchanged at 20 degrees through the crouch modifier.

**Authoring process.** Start from the real posture, then tune what hangs: the held arm was solved from the target (carrier's right
shoulder plus an offset, the passenger's arm segment lengths and a "bend down" hint), not found by search. A search was only
used earlier to bound the clearance trade-offs; here every value was chosen from the anatomy and checked on the workbench.

**Hands.** Right hand: the passenger's left wrist, which now hangs at the carrier's right front hip; the passenger's arm is
pulled forward and bent (what the carrier's grip does): reach 0.349 of 0.470 m (margin 121 mm), elbow 96 degrees. Left hand: the
passenger's left thigh above the knee, from the front: reach 0.377 of 0.464 m (margin 86 mm), elbow 109 degrees. Both arms hang
at the sides, bent, with no crossing. The AUG moved to the chest centre (`stowed_offset_from_neck = (0, -0.40, 0.20)`): the
right-front place it had is where the held wrist now is.

**Configuration.** One place for the whole arrangement: the rig's "Rescue Carry" group: `passenger_anchor_from_neck`,
`passenger_yaw_degrees`, `passenger_pose_overrides` (any key of `PassivePassengerPose.DEFAULTS`: fold, legs, arms),
`carry_elbow_swivel_degrees`, `carry_contacts_enabled`; the contact points are `RescuePassenger.CONTACTS`, the assignment is
`CharacterRig.CARRY_CONTACTS`, the slung weapon is the handling profile. Overrides can be set in the editor or a script and the
workbench capture accepts them (`anchor=`, `yaw=`, `p.fold=`, ...) so they can be iterated without editing files.

**Test contract changes (06B.1).** The check "head hangs behind the carrier and the feet further forward" encoded the piggyback
and was replaced by transverse-drape checks (head and feet more than 0.5 m apart sideways and less than 0.35 m front to back; abdomen
over the shoulders). The head-below-abdomen threshold went from 0.25 to 0.15 m for the head joint (the skull hangs below it). The
post-carry pole tolerance went from 2 to 5 mm (the measured difference is 2.2 mm, 0.3 degrees, from the swivel latching while
the carry lean eases out). Hand targets match to a micrometre.

## Limits

- The grips are positions and orientations plus a uniform finger curl (0.75): no per-finger wrap and no surface test, so a hand
  can read as a mitten on the limb.
- The passenger's fingers are straight (it has no finger pose); the carrier's fingers wrap with one uniform curl.
- Mesh overlap is not measured: the passenger's chest sits on the carrier's right shoulder and its thigh against the carrier's
  left hip; only bone distances are tested.
- The legs hang with the feet at +0.43 to +0.48 m, a long way out to the carrier's left; a real carry would pull them in.
- The pickup clip's first 0.6 s now shows the contact arms immediately (no reach-in): that is the 06C pickup choreography.
- Clipping is not measured at mesh level (axis-to-bone distance only for the rifle). The passenger's arm overlaps the
  carrier's side in places and the slung rifle lies close to the carrier's right chest. Visual checks only.
- The carry-move leg stride is the existing wide cycle; it looks wide under load.
- The passenger is a rigid pose on the carrier's chest: no secondary motion, and its legs do not sway.
- The lean is applied about the modifier's measured axis; if another rig's spine axes are not measured correctly the
  lean follows that.
- Fingers are not curled; the passenger looks identical to the carrier; other proportions need only a new anchor value.
- The pose table and the anchor are tuned by eye against renders. The editable values are `passenger_anchor_from_neck`,
  `CARRY_YAW_DEGREES`, the angles in `passive_passenger_pose.gd` and `CARRY_LEAN_DEGREES`.

## Proposed 06B

Carrier hands on the passenger's thigh and wrist (reuse the hand-contact diagnostics for both bodies, with targets taken from
the passenger's bones), carrier arm layout that reads as holding, and a stowed-weapon position that clears the passenger.
Anything that would make later editing hard: the anchor, the yaw and the pose angles are interdependent by eye, and the
carry-move stride is shared with unloaded movement.
