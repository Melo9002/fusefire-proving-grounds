class_name StairFootPlanner
extends RefCounted
## Foot placement for walking a staircase: PURE and deterministic, a function of (stair model, contact policy, where the body is along the stair). Nothing accumulates, so the feet
## are the same at any frame rate, replay speed or seek position. (With the stance motion on a planted foot rolls through its stance; with it off it is locked at one point.) It plans where each foot is and what it does (stance or swing); the rig's leg IK puts the ankle there.
##
## Holds: the ordered places a foot is put, in TRAVEL order (the ground before the stair, the chosen treads, the landing). With a step of one tread every tread is a hold; with two
## every second one (counted from the top so a stair is always finished on its last tread). Feet alternate holds (even holds the left foot, odd the right). A foot is on hold j
## while the body's continuous hold index M is within half a hold of j (a 50% stance), and swings between its two neighbouring holds otherwise: it lifts first and travels after
## (StairProfile.lift_phase / travel_start), so it clears the riser, and it is locked (the same world point) for the whole stance.

const LEFT := 0
const RIGHT := 1


## The holds of `model` for a walk up (`ascending`) or down, as [{s, height}] in travel order, `step` treads per step.
static func holds(model: StairModel, ascending: bool, step: int) -> Array:
	var treads: Array[int] = []
	var k := model.count
	while k >= 1:
		treads.push_front(k)
		k -= maxi(step, 1)
	var list: Array = [{"s": model.riser_s(1) - model.tread_depth * 0.5, "height": model.low.y}]
	for tread in treads:
		var span := model.tread_span(tread)
		list.append({"s": (span.x + span.y) * 0.5, "height": model.tread_top(tread)})
	list.append({"s": model.end_s() + model.tread_depth * 0.5, "height": model.top()})
	if not ascending:
		list.reverse()
	return list


## The continuous hold index of a body at distance `s` along the stair: 0 at the first hold, n-1 at the last, linear between holds, clamped.
static func hold_index(hold_list: Array, s: float) -> float:
	var count := hold_list.size()
	if count < 2:
		return 0.0
	var ascending := float(hold_list[1].s) > float(hold_list[0].s)
	var q := s if ascending else -s
	for i in count - 1:
		var a := float(hold_list[i].s) if ascending else -float(hold_list[i].s)
		var b := float(hold_list[i + 1].s) if ascending else -float(hold_list[i + 1].s)
		if q <= b:
			return clampf(float(i) + (q - a) / maxf(b - a, 0.0001), 0.0, float(count - 1))
	return float(count - 1)


## Where foot `foot` (LEFT / RIGHT) is for a body at distance `s`: {position (the ankle target in world), planted, hold, swing, tread_top}.
static func foot_at(model: StairModel, profile: StairProfile, hold_list: Array, ascending: bool, s: float, foot: int) -> Dictionary:
	var last := hold_list.size() - 1
	var index := hold_index(hold_list, s)
	var nearest := foot + 2 * int(round((index - float(foot)) / 2.0))
	var hold_a := clampi(nearest, 0, last)
	var hold_b := hold_a
	var swing := 0.0
	if index > float(nearest) + 0.5:
		hold_b = clampi(nearest + 2, 0, last)
		swing = clampf(index - (float(nearest) + 0.5), 0.0, 1.0)
	elif index < float(nearest) - 0.5:
		hold_b = hold_a
		hold_a = clampi(nearest - 2, 0, last)
		swing = clampf(index - (float(nearest) - 1.5), 0.0, 1.0)
	# A planted foot ROLLS through its stance (phase -0.5 at heel strike to +0.5 at toe-off); the swing leaves from the toe-off state and arrives at the next heel-strike state, so nothing jumps.
	var phase := clampf(index - float(nearest), -0.5, 0.5)
	var from_point := _hold_point(model, profile, hold_list[hold_a], ascending, foot, hold_a, 0.5)
	var to_point := _hold_point(model, profile, hold_list[hold_b], ascending, foot, hold_b, -0.5)
	if swing <= 0.0 or hold_a == hold_b:
		var planted_point := _hold_point(model, profile, hold_list[hold_a], ascending, foot, hold_a, phase)
		return {"position": planted_point, "planted": true, "hold": hold_a, "swing": 0.0, "tread_top": float(hold_list[hold_a].height), "phase": phase}
	var going_up := to_point.y >= from_point.y
	# Up: lift first, travel after, so the foot clears the riser. Down: travel first (out over the nosing), drop after: the foot never goes down through the tread it left.
	var travel := smoothstep(profile.travel_start, 1.0, swing) if going_up else smoothstep(0.0, 1.0 - profile.travel_start, swing)
	var vertical := smoothstep(0.0, profile.lift_phase, swing) if going_up else smoothstep(1.0 - profile.lift_phase, 1.0, swing)
	var base := from_point.lerp(to_point, travel)
	var height := lerpf(from_point.y, to_point.y, vertical) + sin(swing * PI) * profile.swing_lift
	var position := Vector3(base.x, height, base.z)
	return {"position": position, "planted": false, "hold": hold_b, "swing": swing, "tread_top": maxf(float(hold_list[hold_a].height), float(hold_list[hold_b].height))}


## The ankle target for a foot on `hold` (index `hold_id` in the list) at stance `phase` (-0.5 heel strike .. +0.5 toe-off). With the stance motion off this is one fixed point per hold.
static func _hold_point(model: StairModel, profile: StairProfile, hold: Dictionary, ascending: bool, foot: int, hold_id := -1, phase := 0.0) -> Vector3:
	var facing := model.direction if ascending else -model.direction
	var left := Vector3.UP.cross(facing).normalized()
	var side := profile.foot_half_spread * (1.0 if foot == LEFT else -1.0)
	var forward := -profile.ankle_setback
	var lift := 0.0
	if profile.stance_motion_enabled and hold_id >= 0:
		forward += profile.stance_roll * phase
		lift = profile.heel_lift * smoothstep(0.05, 0.5, phase)
		var variation := _variation(hold_id, foot, profile.placement_variation)
		forward += variation.x
		side += variation.y
		var reach := maxf(model.width * 0.5 - 0.1, 0.05)
		side = clampf(side, -reach, reach)
	var along := model.low + model.direction * float(hold.s) + facing * forward + left * side
	return Vector3(along.x, float(hold.height) + profile.ankle_height + lift, along.z)


## A small deterministic offset (along, across) for a foot landing on hold `hold_id`: the same for the same hold every time, different between holds and between feet.
static func _variation(hold_id: int, foot: int, amount: float) -> Vector2:
	if amount <= 0.0:
		return Vector2.ZERO
	var a := sin(float(hold_id) * 12.9898 + float(foot) * 78.233) * 43758.5453
	var b := sin(float(hold_id) * 39.3468 + float(foot) * 11.135) * 24634.6345
	return Vector2((a - floorf(a)) * 2.0 - 1.0, (b - floorf(b)) * 2.0 - 1.0) * amount


## The sideways shift of the pelvis toward the foot that carries the weight (world, horizontal): zero in double support, a full `pelvis_sway` toward the planted foot while the other swings.
static func sway_at(model: StairModel, profile: StairProfile, hold_list: Array, ascending: bool, s: float) -> Vector3:
	if not profile.stance_motion_enabled or profile.pelvis_sway <= 0.0:
		return Vector3.ZERO
	var support: Array[float] = []
	for foot in 2:
		var result := foot_at(model, profile, hold_list, ascending, s, foot)
		support.append(1.0 if bool(result.planted) else 0.5 + 0.5 * cos(TAU * float(result.swing)))   # 1 at lift-off, 0 mid-swing, 1 at landing
	var facing := model.direction if ascending else -model.direction
	var left := Vector3.UP.cross(facing).normalized()
	return left * profile.pelvis_sway * (support[LEFT] - support[RIGHT])


## The pelvis height for a body at `body_xz` (world x/z of the hips), from the two feet (`feet` = the dictionaries foot_at returns): a PLANTED foot constrains the pelvis both
## ways (the leg may not overreach and the knee may not fold past `min_knee_interior_degrees`); a swinging foot only may not be overreached (it can fold freely: it is in the
## air). Returns {height, ok, low, high}: `ok` false means no height satisfies the planted legs (the stair is too steep for this body at this stride): the height is then
## the reachable one (legs never overreach) and it is a mismatch to report, not hide.
static func pelvis(profile: StairProfile, body_xz: Vector3, feet: Array, smooth_floor := NAN) -> Dictionary:
	var min_chord := profile.leg_length * sin(deg_to_rad(profile.min_knee_interior_degrees) * 0.5)   # thigh = shin = leg/2: the chord across the knee angle
	var max_chord := profile.leg_length * profile.max_leg_extension
	var low := -INF
	var high := INF
	for foot: Dictionary in feet:
		var ankle: Vector3 = foot.position
		var horizontal := Vector2(ankle.x - body_xz.x, ankle.z - body_xz.z).length()
		var vertical_max := sqrt(maxf(max_chord * max_chord - horizontal * horizontal, 0.0))
		high = minf(high, ankle.y + vertical_max)
		if bool(foot.planted):
			low = maxf(low, ankle.y + sqrt(maxf(min_chord * min_chord - horizontal * horizontal, 0.0)))
	if low == -INF:
		low = high - 0.2
	var ok := low <= high
	if not ok:
		return {"height": high, "ok": false, "low": low, "high": high}
	if not is_nan(smooth_floor):
		# The smooth standing height, pushed only as far as the planted legs require.
		return {"height": clampf(smooth_floor + profile.pelvis_standing_height, low, high), "ok": true, "low": low, "high": high}
	return {"height": lerpf(low, high, profile.pelvis_preference), "ok": true, "low": low, "high": high}


## The stair's SURFACE (the tread tops) averaged over +-`pelvis_smoothing` metres of travel around `s` (a pure function of s): the smooth height the pelvis stands over. The average of a
## staircase is the line through its tread tops, not the line through its cell centres (which lies half a rise lower), and the body stands over the former.
static func floor_reference(model: StairModel, profile: StairProfile, s: float) -> float:
	var half := profile.pelvis_smoothing
	if half <= 0.0001:
		return model.height_at(s)
	# The mean of the step function height_at over [s - half, s + half], in closed form (a piecewise-linear, continuous function of s): each riser adds one rise for the part
	# of the window beyond it.
	var total := 0.0
	for k in model.count:
		total += clampf(s + half - model.riser_s(k + 1), 0.0, 2.0 * half)
	return model.low.y + model.tread_rise * total / (2.0 * half)


## The pelvis height actually used: the stair's smoothed SURFACE (floor_reference) plus the standing height, pushed only as far as the legs demand right now (pelvis: the planted legs
## may neither overreach nor fold past the knee limit). The reference is smooth, so the pelvis moves smoothly and only leaves it when a planted leg requires. (An earlier version
## averaged per-moment solutions over a window: it stepped by one sample's share at every footfall and cost 0.5 ms per call; measured in the architecture audit.)
static func pelvis_smoothed(model: StairModel, profile: StairProfile, hold_list: Array, ascending: bool, s: float, body_xz: Vector3) -> Dictionary:
	var feet_now := [foot_at(model, profile, hold_list, ascending, s, LEFT), foot_at(model, profile, hold_list, ascending, s, RIGHT)]
	return pelvis(profile, body_xz, feet_now, floor_reference(model, profile, s))


## An ankle target held inside what the leg can do from `hip`: never farther than the legs reach, never closer than a knee folded to `min_knee_interior_degrees` allows. A planted foot
## stays where it is (the pelvis was placed for it); this is for the swinging foot, whose planned arc may carry it closer than a knee can fold.
static func limit_ankle(profile: StairProfile, hip: Vector3, ankle: Vector3) -> Vector3:
	var min_chord := profile.leg_length * sin(deg_to_rad(profile.min_knee_interior_degrees) * 0.5)
	var max_chord := profile.leg_length * profile.max_leg_extension
	var offset := ankle - hip
	var chord := offset.length()
	if chord < 0.0001:
		return hip + Vector3.DOWN * min_chord
	return hip + offset / chord * clampf(chord, min_chord, max_chord)


## How much of the stair pose applies for a body at distance `s` that walks the stair from `enter` to `exit` (distances along the stair): 0 at both ends of its walk and on the
## way in and out, 1 in the middle, easing over `ease_length` metres (or less on a short walk). The animation's own legs are the weight-0 pose, so entering and leaving is a blend.
static func weight_at(s: float, enter: float, exit: float, ease_length: float) -> float:
	var low := minf(enter, exit)
	var high := maxf(enter, exit)
	if s <= low or s >= high:
		return 0.0
	var blend := minf(maxf(ease_length, 0.001), (high - low) * 0.45)
	return smoothstep(0.0, blend, minf(s - low, high - s))
