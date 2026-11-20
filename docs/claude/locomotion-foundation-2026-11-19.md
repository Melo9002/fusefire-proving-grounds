# Humanoid locomotion foundation (stabilization 01)

## 1. Root cause

The movement pipeline was traced end to end:

| Stage | Code | Finding |
| --- | --- | --- |
| Command and path | `TacticalUnit.move_along_path`, `_physics_process` | The unit moves at `movement_speed` toward each waypoint. Untouched. |
| Facing | `UnitVisualAdapter.update_locomotion` | The rig turns to the travel direction (`rotate_toward`, 360 deg/s) and always asks for the forward clip, direction (0, 1). Ordinary tactical movement is "turn and advance"; the tactical layer has no backward or strafing movement. Correct. |
| Cadence | `set_locomotion(.., speed / stride_length)` | Correct in form; the stride constant (1.6 m) did not match the gait. |
| Clip selection | `CharacterAnimationController` blend space (`move`, `move_back`, `move_left`, `move_right`) | Structure fine. The left/right clips were mislabeled against the direction axis (see below). |
| Clips | `CharacterFallbackAnimationBuilder._make_move`, `_make_directional_move`, loaded `carry_move` | **The defect.** |

**Measured cause** (`leg_probe` on the MIRA skeleton, character frame x = left, y = up, z = forward): on this imported rig a rotation about a leg bone's
local **x** swings the leg **sideways** (22 deg moves the knee 0.144 m laterally and 0.005 m fore-aft), local **z** swings it fore-aft, and the knee
hinge is local z. The old walk authored thigh swing and knee flexion about local x (it assumed x is the hip hinge). So the knees and feet travelled
sideways through the whole stride: the sampled `move` clip put the ankles up to 0.36 m to the side of the hip and the knees 0.13 to 0.16 m, with
almost no fore-aft motion. The old `move_left/right` clips swapped the two axes, so they also looked wrong. The Animation 06 loaded gait copied the same
axes (0.10 m lateral knee). The facing, character root and blend selection were correct: this was **wrong local-axis assumptions in the procedural
clips**, not a rotation or controller problem. No new controller was needed.

## 2. Movement coordinate contract

* **Anatomical forward**: the way the toes point, measured from the rest pose (ankle to toe base, vertical removed), in skeleton space. **Up**: hips to
  head. **Hip hinge**: forward x up (`CharacterFallbackAnimationBuilder.measure_axes`, `anatomical_forward/up`, `hip_hinge`). Tested: forward is the
  visual root's +Z, up +Y, the hinge the lateral axis, left is +X.
* **Visual root**: the rig's `Character` node, forward +Z. **Tactical facing**: the unit turns its rig to the travel direction, so for ordinary
  movement travel direction = visual forward = anatomical forward. Nothing is corrected per clip.
* **Locomotion direction** (`Vector2`): x toward the character's **left**, y forward. (0,1) `move`, (0,-1) `move_back`, (1,0) `move_left`, (-1,0)
  `move_right`. The blend points were corrected to this; the workbench arrow keys follow it.
* The imported bones' local axes are never assumed. Every gait rotation is "about the hip hinge / vertical / forward" and is converted to each bone's own
  local axis from its rest orientation (`_about`); position offsets likewise (`_local_offset`).

Directional gaits exist for the workbench and future movement styles. Ordinary tactical movement only ever selects forward (as before and by design);
backward and side steps are not reachable through current controls and no mechanic was added for them.

## 3. The gait

`LocomotionGait` (a `Resource`; `CharacterRig` exports `locomotion_gait` and `loaded_locomotion_gait`) holds the numbers; the stride shape is a phase table
(hip, knee, ankle at nine points of the cycle, smoothed periodic Catmull-Rom, 16 keys per clip). It uses anatomical angles (hip flexion +, knee flexion >=
0, ankle toes-up +), so knee hyperextension cannot be authored by accident.

Per leg: hip swings about the hinge, the knee flexes about the hinge (the shin swings back), the ankle follows the table plus a foot-flat term that cancels the
shin's pitch while the foot carries weight and fades through push-off and swing. A small stance spread (hip abduction). Pelvis: rise at mid-stance, shift
over the stance leg, yaw toward the swinging leg, with the chest counter-rotating. Arms are not animated (the weapon system owns them: ready grips, arm IK,
elbow guidance; no hardcoded rifle pose). Loaded carry (`LocomotionGait.loaded()`): shorter hip swing and knee lift, wider stance, and a square trunk (no
pelvis yaw: the passenger contacts ride on the chest and a yawing pelvis moved them 5.8 mm).

Start and stop use the existing AnimationTree cross-fades (0.12 s) and the pace scale follows speed; commands are never delayed. Cadence =
speed / `UnitVisualAdapter.stride_length` (1.3 m) or `loaded_stride_length` (0.9 m); the test checks these equal what the feet actually cover (2 x the
measured fore-aft foot travel: 1.32 m and 0.88 m).

### Corrected knee behaviour

Before: knee flexion about local x moved the ankle 0.29 m sideways. Now: the knee hinges about the measured hip axis, so the knee-plane normal is lateral
(sagittality >= 0.96 for the forward walk; >= 0.97 loaded; 0.94 to 0.95 for the side steps), flexion runs 8 to 58 degrees (loaded 7 to 42), never negative
(no hyperextension), and the leg bone lengths change by < 0.001 mm over the stride. No IK or pole vectors were needed.

## 4. Parameters

| Where | What |
| --- | --- |
| `LocomotionGait` (`locomotion_gait.gd`) | hip/knee/ankle scales, stance spread, pelvis bob/sway/yaw, torso counter-rotation, backward scale, side-step swing and knee lift; phase tables `THIGH`, `KNEE`, `ANKLE` |
| `CharacterRig` "Locomotion" | `locomotion_gait`, `loaded_locomotion_gait` |
| `UnitVisualAdapter` | `stride_length`, `loaded_stride_length`, `turn_speed_degrees` |
| `CharacterFallbackAnimationBuilder` | `make_gait`, the contract and axis measurement, `_stance_weight` |

## 5. References actually consulted

* Gait-cycle structure and typical joint angles: web search summarising the phases (about 60% stance, 40% swing; initial contact hip about 20 to 30 deg flexion,
  knee about 5, ankle neutral; loading response knee about 15; midstance hip about 0; push-off knee 35 to 40 and ankle plantar-flexed about 20; swing peak knee 60 to
  65). Sources listed by the search included
  [Physiopedia, The Gait Cycle](https://www.physio-pedia.com/The_Gait_Cycle), [AAPM&R, Biomechanics of normal gait](https://now.aapmr.org/biomechanics-normal-gait/) and
  [Univ. of Missouri PM&R, Normal Gait](https://www.medicine.missouri.edu/sites/default/files/pm-r/2020_Normal_Gait.pdf); only the search summary was read, and
  it notes some figures come from teaching slides. The phase table follows these ranges (hip 26 to 30 deg at contact, knee 4, loading knee 16, push-off hip -13 / knee 30 /
  ankle -14, swing knee 55).
* [Arek Dembinski, rifle movement in low and high ready](https://www.youtube.com/watch?v=kmKli6wXqCo): **video playback was not possible.** Only the page
  title could be read (a Polish title about running with a weapon in low and high ready). Nothing was learned from the footage and no claim is made about it.
* [US Army TC 3-22.9](https://rdl.train.army.mil/catalog-ws/view/100.ATSC/492701D5-25E9-40A7-9498-74C22831F268-1463059585416/tc3_22x9wc1.pdf): the fetch failed
  and it was **not read**.
* [Univ. of Iowa, Warfighter load (ETOWL)](https://iti.uiowa.edu/sites/iti.uiowa.edu/files/2021-01/Enhanced%20Technologies%20for%20Optimization%20of%20Warfighter%20Load%20%28ETOWL%29.pdf):
  downloaded, but the PDF text was compressed and could not be extracted here, so it was **not read**.

So the weapon-carrying style rests on the existing weapon system (ready posture, both hands on the rifle, arms not swung) rather than on the military sources, which
were unavailable. That is the main research gap; the gait itself is reference-informed from the gait-cycle summary only.

## 6. Evidence and limits

Workbench (`wb_gait` sheets): forward and loaded walk, eight phases x side / front / three-quarter. Real gameplay: a battle launched from the normal match-setup scene, a
unit walking an L-shaped path through `TacticalUnit.move_along_path`; its heading follows the travel direction and it returns to idle.
Not reachable through current tactical controls, so not exercised in play: backward and side-step gaits, crouched movement (crouching only occurs in cover; the
crouch modifier owns the legs there and was not changed). Movement speed is 5 m/s, so the walk plays at about 4 cycles per second, which reads as a jog; speed is
out of scope and the stride matches the ground covered. Remaining simplifications: no start/stop steps, no turn-in-place steps, flat-ground only, no heel/toe
roll beyond the ankle table, no arm motion, side and backward gaits unrefined.
