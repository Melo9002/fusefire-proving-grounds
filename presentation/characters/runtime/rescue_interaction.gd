class_name RescueInteraction
extends Resource
## The shared timeline of a rescue lift: ONE clock that drives both humanoids (the carrier's body, the passenger's pose and
## placement, how much the hands hold, where the weapon is). Pure data and arithmetic: no nodes, no randomness, no physics, so
## the same inputs give the same poses (replay-safe). The tactical layer decides THAT a rescue happens; this only decides how it
## looks. CharacterRig owns an instance, advances it once per frame and applies `sample()`.
##
## PICKUP phases (default 3.0 s): ALIGN (carrier turns to the passenger, steps in and bends), REACH (kneels, the hands go to the
## wrist and thigh and take hold), LIFT (the passenger is raised and rolled over, the carrier rises), SETTLE (the passenger
## comes to rest across the shoulders, the carrier steps back into the carry posture).
## RELEASE is the same timeline run backwards at its own duration, with the same phases in reverse: the carrier steps in,
## kneels, lowers the passenger, the hands let go last, the carrier rises and takes the weapon back.
##
## Everything tunable is below, grouped. Times are seconds; the sample is a function of time only (`scrub` sets it directly).

enum Kind { NONE, PICKUP, RELEASE }

@export_group("Pickup timing")
## Carrier turns to the passenger and steps in.
@export_range(0.05, 3.0, 0.01, "suffix:s") var align_seconds := 0.5
## Kneels and takes hold.
@export_range(0.05, 3.0, 0.01, "suffix:s") var reach_seconds := 0.7
## Raises and rolls the passenger.
@export_range(0.05, 3.0, 0.01, "suffix:s") var lift_seconds := 1.25
## Passenger comes to rest across the shoulders; the carrier steps back.
@export_range(0.05, 3.0, 0.01, "suffix:s") var settle_seconds := 0.8
@export_group("Release timing")
## The whole release, run through the pickup's phases backwards.
@export_range(0.5, 8.0, 0.01, "suffix:s") var release_seconds := 3.0
@export_group("Carrier")
## Hip drop while bending to the passenger (metres; the crouch modifier clamps it to what this body can do).
@export_range(0.0, 1.0, 0.01, "suffix:m") var crouch_depth := 0.5
## How far into the half-kneel the reach goes (0 = crouch, 1 = one knee down).
@export_range(0.0, 1.0, 0.01) var kneel := 1.0
## How low the carrier is while the passenger is in the lifting phase, as a fraction of the full bend.
@export_range(0.0, 1.0, 0.01) var lift_crouch := 0.3
## The most the carrier walks toward the passenger to get hold of it (metres); it steps back with the load.
@export_range(0.0, 2.0, 0.01, "suffix:m") var max_step := 0.9
## How far in front of the carrier's root the passenger's abdomen lies once the carrier has stepped in (metres).
@export_range(0.2, 1.2, 0.01, "suffix:m") var stand_off := 0.5
@export_group("Passenger")
## Where the passenger's abdomen is at the middle of the lift, in the carrier's frame (x left, y up, z forward): in front of the
## carrier at hip height, so the body comes up the carrier's front and not through it.
@export var lift_waypoint := Vector3(0.0, 0.95, 0.38)
## The abdomen's height above the floor while lying (metres).
@export_range(0.0, 0.5, 0.005, "suffix:m") var ground_height := 0.13
## Fraction of the lift the passenger has done when the settle begins.
@export_range(0.5, 1.0, 0.01) var lift_before_settle := 0.85
@export_group("Hands and weapon")
## Window (fraction of the REACH phase) in which the rifle goes from the hand to the sling.
@export var stow_window := Vector2(0.0, 1.0)

var kind := Kind.NONE
var time := 0.0
var paused := false


func pickup_seconds() -> float:
	return align_seconds + reach_seconds + lift_seconds + settle_seconds


func duration() -> float:
	return release_seconds if kind == Kind.RELEASE else pickup_seconds()


func active() -> bool:
	return kind != Kind.NONE


func start(new_kind: Kind) -> void:
	kind = new_kind
	time = 0.0


func stop() -> void:
	kind = Kind.NONE
	time = 0.0


## Moves the clock on and returns true when the timeline has just run out. The state stays at its end
## until `stop()`; the owner stops it after reading the final sample.
func advance(delta: float) -> bool:
	if kind == Kind.NONE or paused:
		return false
	var before := time
	time = minf(time + delta, duration())
	if before < duration() and time >= duration():
		return true
	return false


## Jumps to `seconds` (clamped). For scrubbing in the workbench and for tests; emits nothing.
func scrub(seconds: float) -> void:
	time = clampf(seconds, 0.0, duration())


func progress() -> float:
	return time / maxf(duration(), 0.0001)


## The pickup's own clock for the current time: the release maps onto the same timeline backwards.
func _pickup_time() -> float:
	if kind == Kind.RELEASE:
		return pickup_seconds() * (1.0 - time / maxf(release_seconds, 0.0001))
	return time


static func _smooth(t: float, a: float, b: float) -> float:
	var x := clampf((t - a) / maxf(b - a, 0.0001), 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func phase_name() -> StringName:
	if kind == Kind.NONE:
		return &"none"
	var t := _pickup_time()
	var t1 := align_seconds
	var t2 := t1 + reach_seconds
	var t3 := t2 + lift_seconds
	var names: Array[StringName] = [&"align", &"reach", &"lift", &"settle"]
	var index := 0 if t < t1 else (1 if t < t2 else (2 if t < t3 else 3))
	# Backwards, the same phases read as their opposites.
	if kind == Kind.RELEASE:
		var reverse: Array[StringName] = [&"step_back", &"let_go", &"lower", &"steady"]
		return reverse[index]
	return names[index]


## Phase boundaries in the interaction's own time, for the workbench and the tests: [start, end] per phase, in the order the
## kind plays them.
func phase_bounds() -> Array:
	var t1 := align_seconds
	var t2 := t1 + reach_seconds
	var t3 := t2 + lift_seconds
	var t4 := t3 + settle_seconds
	var bounds := [[0.0, t1], [t1, t2], [t2, t3], [t3, t4]]
	if kind == Kind.RELEASE:
		var k := release_seconds / t4
		return [[0.0, (t4 - t3) * k], [(t4 - t3) * k, (t4 - t2) * k], [(t4 - t2) * k, (t4 - t1) * k], [(t4 - t1) * k, release_seconds]]
	return bounds


## What both bodies are asked to do now. All values 0..1 unless noted.
##   crouch    carrier bend (hip drop = crouch * crouch_depth)
##   kneel     half-kneel weight
##   lean      extra forward lean of the carrier, degrees (the carry's own lean arrives with `carry`)
##   carry     0 = not yet loaded, 1 = in the loaded carry posture (lean and gait)
##   step      how far the carrier is toward the passenger (fraction of the step; 0 = at its tactical place)
##   contact   how fully the hands are on the contacts (0 = where they were, 1 = on the passenger)
##   lift      the passenger's progress from the floor (0) to across the shoulders (1)
##   pose      the passenger's limb pose, lying (0) to draped (1)
##   stow      the weapon, in the hand (0) to on the sling (1)
##   clip      the carrier's base animation state for this moment
func sample() -> Dictionary:
	if kind == Kind.NONE:
		return {"phase": &"none", "crouch": 0.0, "kneel": 0.0, "lean": 0.0, "carry": 1.0, "step": 0.0, "contact": 1.0, "lift": 1.0, "pose": 1.0, "stow": 1.0, "clip": &"carry_idle"}
	var t := _pickup_time()
	var t1 := align_seconds
	var t2 := t1 + reach_seconds
	var t3 := t2 + lift_seconds
	var t4 := t3 + settle_seconds
	var crouch := 0.0
	if t < t2:
		crouch = _smooth(t, t1 * 0.3, t2)
	elif t < t3:
		crouch = lerpf(1.0, lift_crouch, _smooth(t, t2, t3))
	else:
		crouch = lerpf(lift_crouch, 0.0, _smooth(t, t3, t4))
	var carry := _smooth(t, t3, t4)
	var lift := 0.0
	if t >= t2:
		lift = lift_before_settle * _smooth(t, t2, t3) if t < t3 else lerpf(lift_before_settle, 1.0, _smooth(t, t3, t4))
	var step := _smooth(t, 0.0, t1) * (1.0 - _smooth(t, t3, t4))
	var stepping := t < t1 * 0.9 or t > t3 + settle_seconds * 0.1
	var clip := &"pickup"
	if stepping and step > 0.0 and step < 1.0:
		clip = &"carry_move" if t > t3 else &"move"
	elif t >= t4 - 0.0001:
		clip = &"carry_idle"
	var done := kind == Kind.RELEASE and time >= release_seconds - 0.0001
	if done:
		clip = &"rifle_idle"
	return {
		"phase": phase_name(),
		"crouch": crouch,
		"kneel": kneel * crouch,
		"lean": 0.0,
		"carry": carry,
		"step": step,
		"contact": _smooth(t, t1, t2),
		"lift": lift,
		"pose": lift,
		"stow": _smooth(t, t1 + stow_window.x * reach_seconds, t1 + stow_window.y * reach_seconds),
		"clip": clip,
	}
