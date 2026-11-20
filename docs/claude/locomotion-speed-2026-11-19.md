# Speed-responsive locomotion, turning and transitions (stabilization 01B)

Builds on `locomotion-foundation-2026-11-19.md` (measured anatomical axes, the movement coordinate contract, the corrected walk). That work is kept: every
gait here is built the same way (rotations about the measured hip hinge, the vertical and forward axis; no bone-local axis is assumed).

## 1. Architecture findings and the chosen approach

* **The existing animation controller was enough.** `AnimationTree` + `AnimationNodeBlendSpace1D/2D` already provide phase-synchronised blending, and every
  gait is a one-second loop that starts at the left heel strike, so blending walk, jog and run is foot-for-foot. No replacement or second controller.
* **What was missing** was not clips but speed information: the adapter ignored speed except for a cadence of speed / one stride constant, which made the
  game's 5 m/s walk cycle at four cycles per second. Now the tactical layer's actual speed and heading rate (both already computed in
  `TacticalUnit._physics_process` and `UnitVisualAdapter.update_locomotion`) drive a profile.
* **Techniques considered.** Phase-synchronised blend spaces (used). Speed-driven gait selection with a per-gait stride model (used; stride and cadence,
  not playback speed, absorb the mismatch). Foot locking / IK, stride warping, motion matching, root motion: not used. The rig is procedural and in place;
  the unit's position is the tactical layer's, so root motion would invert authority, and motion matching needs a database that does not exist. Turn-in-place
  is a small procedural layer, not clips.
* **Layer contract.**

| Tactical layer owns | Presentation owns |
| --- | --- |
| destinations, paths, speed (`movement_speed`), action costs, collision, facing, turn order | gait selection, blending, cadence, body posture, turn presentation, foot placement, weapon stabilisation |

  The presentation receives the actual speed and heading rate every frame and answers with a pose. The speed the legs follow lags the real speed
  (`speed_rise`/`speed_fall`) but never leads it and nothing flows back. No tactical state is duplicated.

## 2. Pieces

* `LocomotionGait` (resource): one gait: phase tables (hip, knee, ankle), stride length, stance fraction, scales, pelvis bob (and the phase it peaks at: mid-stance
  for walking, flight for running), sway, yaw, forward lean. Factories `walk()`, `jog()`, `run()`, `loaded()`, `loaded_fast()`.
* `LocomotionProfile` (resource, exported by `CharacterRig.locomotion_profile`): the five gaits, the speed thresholds, cadence limits, responsiveness, turning
  and start/stop settings. Thresholds are in m/s and belong to the profile, not to the current tactical speed.
* `CharacterFallbackAnimationBuilder.make_gait` builds a clip from a gait; the controller builds `move` (walk), `move_jog`, `move_run`, `carry_move`,
  `carry_move_fast` and the directional clips. The forward point of the direction blend space is a `BlendSpace1D` (walk, jog, run); `carry_move` is a
  `BlendSpace1D` (loaded walk, loaded trot).
* `CharacterRig.update_locomotion_presentation(speed, heading_rate, delta)`: the single entry point (the adapter calls it every frame from the tactical
  unit's reported speed; the workbench from its panel). It filters speed, derives the gait blend, the stride at that blend, the cadence, and the lean.
* `LocomotionPoseModifier` (new, **first** in the modifier order: Locomotion, CoverCrouch, WeaponPose, WeaponArmIK, HandGrip): the situational body
  adjustments below. It never touches the arms or weapon targets.

## 3. Walk, jog, run

| | stance | stride | knee recovery | pelvis rise | lean |
| --- | --- | --- | --- | --- | --- |
| walk | 0.58 | 1.1 m | 55 deg | 12 mm, peak at mid-stance | 0 |
| jog | 0.45 | 1.6 m | 80 deg | 20 mm, peak late in the cycle | 4 deg |
| run | 0.36 | 2.5 m | 100 deg | 30 mm, peak in flight (both feet off the ground), low at mid-stance | 9 deg |

The walk table is unchanged from stabilization 01 (stride re-measured: see below). Jog and run have their own tables, wider hip excursion (x1.12, x1.25),
shorter stance, higher heel recovery, and a held forward trunk lean on the spine. Arms are not animated: the weapon system holds the rifle at the ready; the rifle
moves 10 to 16 mm vertically at a full run (measured).

## 4. Speeds, blending, cadence

Defaults: idle below 0.15 m/s, pure walk up to 1.6, pure jog at 3.0, pure run from 4.6 (the tactical 5 m/s is a run by threshold). The gait blend is continuous
(0 walk, 1 jog, 2 run) and smoothed. Cadence = speed / the blended stride, clamped to 0.35..2.3 cycles/s. The stride of each gait equals what its stance foot
covers (stance foot travel / stance fraction), measured by the tests: walk 1.09 vs 1.10, jog 1.59 vs 1.60, run 2.46 vs 2.50, loaded 0.73 / 1.12 vs 0.75 / 1.20.
Cadence x stride matches speed to within 0% across 1 to 5 m/s (the cadence cap only binds beyond ~5.7 m/s, where the feet would start to slide).

Transitions are phase-synchronised blends; measured: during an idle to run ramp the left foot moves no more per frame than in the steady run (0.062 vs 0.053 m).
The start ramp is `speed_rise` 8 m/s^2 (about 0.6 s to 5 m/s); braking is `speed_fall` 28. Because the tactical unit starts and stops instantly, a brief mismatch
between the body and the feet while the ramp runs is inherent and accepted (documented limit).

## 5. Turning, start and stop

* **Moving turns.** The unit already rotates to its travel direction at 360 deg/s (gradual, unchanged). The presentation adds a lean into the turn
  (degrees = turn rate x speed x `bank_gain`, capped at `bank_max` 8): the body banks left or right. None while carrying.
* **Turn in place.** When the facing changes at once (shots, cover turns, `face_world_position`) the chest, head and weapon are at the new facing immediately, as aiming
  needs. The hips and feet are shown still turning: the hips start up to `turn_twist_limit` (70 deg) behind and unwind at `turn_unwind_rate` (300 deg/s) with the spine
  giving the rotation back so the chest's net yaw is zero (checked). Turns over 25 deg add two repositioning steps (the foot on the turning side first); small turns are
  torso and hips only. Facing beyond the twist limit is partly instant (documented compromise: nothing is delayed so that no aim is ever misleading).
* **Reversals.** A 180 deg heading change while moving is the 360 deg/s turn (half a second) plus banking; at rest it is the twist and steps above. No cinematic turn.
* **Start/stop.** Trunk pitch follows the speed change (forward when speeding up, back when braking, `accel_lean_gain`/`max`); the gait ramps through walk and jog; stopping
  settles the blend and returns to the idle pose through the existing cross-fade. No dedicated start/stop step clips.

## 6. Loaded carry

Kept distinct: its own gaits (`loaded_walk`, `loaded_fast`), a trot (never a run) when the carrier moves fast, trunk held square (no bank, pitch or twist; a turn does not twist a
carrier), passenger secondary motion and contacts unchanged. **Pelvis yaw investigation:** the 5.8 mm wrist-target drift reproduced at 2 deg of loaded pelvis yaw and vanishes at
0. The contact targets are computed in the WeaponPose pass from the chest anchor and the carrier's shoulders; I did not find a modifier-ordering fault (the Locomotion modifier is first
and these gaits do not use it). Cause not isolated; left at 0 deg, which is also what a carrier does, and the passenger contact tests hold at speed.

## 7. Workbench

The workbench now carries an interactive **Locomotion Test Bench** panel (top right, `locomotion_test_panel.gd`): a speed slider with the gait it selects, Idle / Walk / Jog / Run,
a loaded-carry toggle, direction buttons, turns in place (-180..+180), moving 90 and 180 turns, scripted transitions (start-run-stop, 0 to 6 m/s ramp, walk-jog-run), six camera views
(front, side, back, three-quarter, feet, top), a slow-motion slider and a live readout (legs' speed, gait blend, cadence, twist, bank, pitch). It drives the production
`update_locomotion_presentation`; there is no second implementation. Existing keys still work (`[` `]` change the preview speed in 0.5 m/s steps).

## 8. Parameters

| Where | What |
| --- | --- |
| `LocomotionProfile` | thresholds, cadence range, speed rise/fall, gait smoothing, twist limit and unwind, step lift, bank, accel lean |
| `LocomotionGait` | phase tables, stride, stance fraction, scales, pelvis, lean |
| `CharacterRig` "Locomotion" | `locomotion_profile` |

## 9. References actually used

* Godot [AnimationNodeBlendSpace1D](https://docs.godotengine.org/en/stable/classes/class_animationnodeblendspace1d.html): `sync` (deprecated; equals independent sync mode: inactive clips keep
  advancing at weight 0, so equal-length loops stay in phase), `sync_mode` alternatives, named blend points. Used as described.
* Web search on phase-synchronised blending and foot sync (Gears of War 4 animation talk, Unreal sync-marker threads, Animancer's note that Unity blend trees use foot-phase sync):
  confirmed the phase-match requirement for walk/run transitions and that foot sync is a trade-off with speed matching. Search snippets only; the talk's content was not read.
* Gait-cycle ranges: as in the foundation document.
* Not available: footage of rifle movement (video playback not possible), TC 3-22.9 (fetch failed), the Iowa PDF (text not extractable). The rifle posture during fast movement is
  therefore not reference-derived; it is the existing weapon pose system holding the ready posture, with the trunk lean and pelvis bob kept small enough that the rifle moves < 2 cm.

## 10. Limits

No start/stop step clips (lean and blend only); the unit's instant tactical start/stop is not hidden, only softened; the run's 2.3 cycles/s cap makes the feet slide above ~5.7 m/s; no
heel/toe roll beyond the ankle table; backward and side-step gaits remain unrefined and unreachable in tactical play; crouched movement is not part of this (the crouch modifier owns the
legs); the rifle is not lowered at speed; turns beyond 70 deg are partly instant at rest.
