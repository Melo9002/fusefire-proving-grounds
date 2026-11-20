class_name LocomotionProfile
extends Resource
## Everything that decides HOW a humanoid moves, in one editable place: the gaits (walk, jog, run, and the two loaded carry gaits), the speeds at
## which they apply, how cadence follows speed, how quickly the presentation responds, and how turns, starts and stops are shown.
##
## It is a PRESENTATION profile. The tactical layer owns destinations, paths, speed, costs and facing; the rig is told the speed the unit is actually
## moving at and answers with a pose. Nothing here feeds back into movement. Speed thresholds are in metres per second and belong to this profile, not
## to the current tactical speed: another game mode (or a slower unit) simply meets different gaits.

@export_group("Gaits")
@export var walk: LocomotionGait = LocomotionGait.walk()
@export var jog: LocomotionGait = LocomotionGait.jog()
@export var run: LocomotionGait = LocomotionGait.run()
## Carrying a passenger: a shorter step, and a steady trot for when the carrier is moving fast. Never a run.
@export var loaded_walk: LocomotionGait = LocomotionGait.loaded()
@export var loaded_fast: LocomotionGait = LocomotionGait.loaded_fast()

@export_group("Speed thresholds (m/s)")
## Below this the unit is idle.
@export_range(0.0, 1.0, 0.01, "suffix:m/s") var idle_below := 0.15
## Pure walk up to this speed; the walk blends into the jog above it.
@export_range(0.2, 6.0, 0.05, "suffix:m/s") var walk_until := 1.6
## Pure jog at this speed (the walk is fully out, the run not yet in).
@export_range(0.5, 8.0, 0.05, "suffix:m/s") var jog_at := 3.0
## Pure run from this speed.
@export_range(0.8, 12.0, 0.05, "suffix:m/s") var run_at := 4.6
## The same for a loaded carrier: loaded walk up to here, the loaded trot fully in at `loaded_fast_at`.
@export_range(0.2, 6.0, 0.05, "suffix:m/s") var loaded_walk_until := 1.5
@export_range(0.5, 8.0, 0.05, "suffix:m/s") var loaded_fast_at := 3.4

@export_group("Cadence")
## Cycles per second are speed / the blended stride, kept inside this range. When the range binds, the feet cover a little more or less ground than
## the body (a slide) instead of the legs cycling absurdly fast or crawling.
@export_range(0.1, 2.0, 0.05, "suffix:Hz") var min_cadence := 0.35
@export_range(0.5, 5.0, 0.05, "suffix:Hz") var max_cadence := 2.3

@export_group("Responsiveness")
## The speed the legs respond to follows the tactical speed with this much give (m/s per second): it rises and falls over a fraction of a second, so
## a unit that starts at full speed ramps through walk and jog and one that stops settles. It follows, it never leads.
@export_range(2.0, 100.0, 0.5, "suffix:m/s²") var speed_rise := 8.0
@export_range(2.0, 100.0, 0.5, "suffix:m/s²") var speed_fall := 28.0
## Smoothing of the gait blend value itself, seconds.
@export_range(0.0, 1.0, 0.01, "suffix:s") var gait_smoothing := 0.1

@export_group("Turning")
## A facing change that arrives at once (a shot, a cover turn) is shown as the lower body catching up with the upper body: the hips start this far (at
## most) behind the new facing and unwind at this rate. The chest and weapon are at the new facing immediately.
@export_range(0.0, 120.0, 1.0, "suffix:°") var turn_twist_limit := 70.0
@export_range(30.0, 1080.0, 5.0, "suffix:°/s") var turn_unwind_rate := 300.0
## How high the repositioning steps lift the feet during a turn in place (knee flexion, degrees).
@export_range(0.0, 60.0, 1.0, "suffix:°") var turn_step_lift := 28.0
## Leaning into a turn while moving: degrees per (radian/s of turn x m/s of speed), and the most.
@export_range(0.0, 1.0, 0.01) var bank_gain := 0.2
@export_range(0.0, 20.0, 0.5, "suffix:°") var bank_max := 8.0

@export_group("Start and stop")
## Trunk pitch from the speed change: degrees per m/s² of acceleration (forward when speeding up, back when braking), and the most either way.
@export_range(0.0, 2.0, 0.01) var accel_lean_gain := 0.4
@export_range(0.0, 15.0, 0.5, "suffix:°") var accel_lean_max := 7.0


## 0 = walk, 1 = jog, 2 = run for a speed (continuous).
func gait_blend(speed: float) -> float:
	if speed <= walk_until:
		return 0.0
	if speed <= jog_at:
		return inverse_lerp(walk_until, jog_at, speed)
	return 1.0 + clampf(inverse_lerp(jog_at, run_at, speed), 0.0, 1.0)


## 0 = loaded walk, 1 = loaded trot.
func loaded_blend(speed: float) -> float:
	return clampf(inverse_lerp(loaded_walk_until, loaded_fast_at, speed), 0.0, 1.0)


## Stride (metres per cycle) at a gait blend value: the blend's two gaits' strides mixed by the same weights the animation tree uses.
func stride_at(blend: float) -> float:
	if blend <= 1.0:
		return lerpf(walk.stride_length, jog.stride_length, blend)
	return lerpf(jog.stride_length, run.stride_length, blend - 1.0)


func loaded_stride_at(blend: float) -> float:
	return lerpf(loaded_walk.stride_length, loaded_fast.stride_length, blend)


func cadence_for(speed: float, stride: float) -> float:
	return clampf(speed / maxf(stride, 0.1), min_cadence, max_cadence)
