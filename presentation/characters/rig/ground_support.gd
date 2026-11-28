class_name GroundSupport
extends RefCounted
## Feet on ground that is not flat (ramps, slopes, and uneven ground to come): the pure part. The animation's own pose stands on the floor under the character's root; where the ground under a foot is higher or lower
## than that, the foot goes with it. Given the animated ankles and the ground under them, this returns how far to move each ankle (the swing keeps its arc: the shift is added to the animated height, not substituted
## for it), how far to take the pelvis (the lower foot's way, so the leg that reaches down is not over-extended and the leg that reaches up bends its knee), and the ground's normal under each foot (a planted foot is turned
## flat to it). It reads nothing of the rig or the world: the host supplies the ground heights, the modifiers apply the result.
##
## It does nothing on flat ground: a shift or a tilt under the thresholds is not a slope, so the animation is left exactly as it was and no IK runs.

## A shift smaller than this (metres) and a tilt smaller than this (the normal's departure from the vertical) is flat ground.
const FLAT_SHIFT := 0.004
const FLAT_TILT := 0.02
## The ground this far above or below the root's floor is not "ground the feet follow" (a stair or a ledge is somebody else's, and a drop is a fall): the foot keeps the animation's height.
const MAX_SHIFT := 0.45
## Ground further BELOW the root's floor than this (a foot over the side edge of a ramp, over a ledge) is not followed: the leg reaches down a step, not a drop.
const MAX_DROP := 0.20
## The weight eases up and down at these rates per second.
const RATE_UP := 40.0
const RATE_DOWN := 8.0


## `root_y`: the height the animation assumes the feet stand at. `ankles`: the animated ankles, world. `samples`: per foot a Dictionary {y, normal} (the ground under it) or {} (none found).
## Returns {shift: [a, b], normal: [a, b], pelvis: float, slope: bool}.
static func plan(root_y: float, ankles: Array[Vector3], samples: Array) -> Dictionary:
	var shift: Array[float] = [0.0, 0.0]
	var normal: Array[Vector3] = [Vector3.UP, Vector3.UP]
	var slope := false
	for side in 2:
		var sample: Dictionary = samples[side]
		if sample.is_empty():
			continue
		var offset := float(sample.y) - root_y
		if absf(offset) > MAX_SHIFT or offset < -MAX_DROP:
			continue
		shift[side] = offset
		var n: Vector3 = sample.normal
		if n.y > 0.5:
			normal[side] = n.normalized()
		if absf(offset) > FLAT_SHIFT or Vector3.UP.angle_to(normal[side]) > FLAT_TILT:
			slope = true
	return {"shift": shift, "normal": normal, "pelvis": minf(shift[0], shift[1]), "slope": slope}


## The next weight: toward 1 on a slope while the character is on the ground, toward 0 otherwise.
static func ease_weight(weight: float, on_slope: bool, delta: float) -> float:
	return move_toward(weight, 1.0 if on_slope else 0.0, (RATE_UP if on_slope else RATE_DOWN) * maxf(delta, 0.0))
