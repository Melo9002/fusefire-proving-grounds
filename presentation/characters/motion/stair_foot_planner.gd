class_name StairFootPlanner
extends RefCounted
## Foot placement for walking a staircase: PURE and deterministic, a function of (stair model, contact policy, where the body is along the stair). Nothing accumulates, so the feet
## are the same at any frame rate, replay speed or seek position. (With the stance motion on a planted foot rolls through its stance; with it off it is locked at one point.) It plans where each foot is and what it does (stance or swing); the rig's leg IK puts the ankle there.
##
## Holds: the ordered places a foot is put, in TRAVEL order (the ground before the stair, the chosen treads, the landing). With a step of one tread every tread is a hold; with two
## every second one (counted from the top so a stair is always finished on its last tread). Feet alternate holds (even holds the left foot, odd the right). A foot is on hold j
## while the body's continuous hold index M is within half a hold of j (a 50% stance), and swings between its two neighbouring holds otherwise: it lifts first and travels after
## (StairProfile.lift_phase / travel_start), so it clears the riser, and it is locked (the same world point) for the whole stance.

## How far a pelvis window may be narrower than empty before it counts as unreachable: the extension and knee limits are comfort margins, and 1.5 cm is below the legs' real slack (3% of 0.77 m = 2.3 cm).
const REACH_TOLERANCE := 0.015
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
static func foot_at(model: StairModel, profile: StairProfile, hold_list: Array, ascending: bool, s: float, foot: int, lateral := 0.0) -> Dictionary:
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
	var from_point := _hold_point(model, profile, hold_list[hold_a], ascending, foot, hold_a, 0.5, lateral)
	var to_point := _hold_point(model, profile, hold_list[hold_b], ascending, foot, hold_b, -0.5, lateral)
	if swing <= 0.0 or hold_a == hold_b:
		var planted_point := _hold_point(model, profile, hold_list[hold_a], ascending, foot, hold_a, phase, lateral)
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
static func _hold_point(model: StairModel, profile: StairProfile, hold: Dictionary, ascending: bool, foot: int, hold_id := -1, phase := 0.0, lateral := 0.0) -> Vector3:
	var facing := model.direction if ascending else -model.direction
	var left := Vector3.UP.cross(facing).normalized()
	var side := profile.foot_half_spread * (1.0 if foot == LEFT else -1.0)
	var forward := -profile.ankle_setback
	var lift := 0.0
	var on_tread := float(hold.s) >= model.riser_s(1) and float(hold.s) <= model.end_s()
	if profile.stance_motion_enabled and hold_id >= 0:
		forward += profile.stance_roll * phase
		lift = profile.heel_lift * smoothstep(0.05, 0.5, phase)
		var variation := _variation(hold_id, foot, profile.placement_variation)
		forward += variation.x
		side += variation.y
	if profile.lateral_follow_enabled:
		side += lateral * (1.0 if facing == model.direction else -1.0)   # the stair's left is the travel's left going up and its right coming down
	if profile.tread_clamp_enabled:
		# The foot stays wholly on its tread: its heel and toe inside the tread's depth (on a tread; the ground and the landing have no riser to stop at) and the foot inside the stair's width.
		if on_tread:
			var half_depth := model.tread_depth * 0.5
			forward = clampf(forward, -(half_depth - profile.foot_back - profile.tread_margin), half_depth - profile.foot_front - profile.tread_margin) if half_depth > profile.foot_back + profile.foot_front * 0.5 else clampf(forward, -half_depth * 0.5, 0.0)
		var lateral_reach := maxf(model.width * 0.5 - profile.foot_half_width - profile.tread_margin, 0.0)
		var lateral_axis_sign := 1.0 if facing == model.direction else -1.0
		side = clampf(side * lateral_axis_sign, -lateral_reach, lateral_reach) * lateral_axis_sign
	var along := model.low + model.direction * float(hold.s) + facing * forward + left * side
	return Vector3(along.x, float(hold.height) + profile.ankle_height + lift, along.z)


## A small deterministic offset (along, across) for a foot landing on hold `hold_id`: the same for the same hold every time, different between holds and between feet.
static func _variation(hold_id: int, foot: int, amount: float) -> Vector2:
	if amount <= 0.0:
		return Vector2.ZERO
	var a := sin(float(hold_id) * 12.9898 + float(foot) * 78.233) * 43758.5453
	var b := sin(float(hold_id) * 39.3468 + float(foot) * 11.135) * 24634.6345
	return Vector2((a - floorf(a)) * 2.0 - 1.0, (b - floorf(b)) * 2.0 - 1.0) * amount


## How far the body is across the stair: the signed distance of `body` from the stair's centre line, along the stair's left (positive to the left looking up the stair).
static func lateral_of(model: StairModel, body: Vector3) -> float:
	return (body - model.low).dot(Vector3.UP.cross(model.direction).normalized())


## Where each hip JOINT is for a pelvis at `pelvis_world` facing `forward` (the pelvis origin is not the joint: the joints are sideways of it and a little below). `foot` LEFT or RIGHT.
static func hip_joint(profile: StairProfile, pelvis_world: Vector3, forward: Vector3, foot: int) -> Vector3:
	var flat := Vector3(forward.x, 0.0, forward.z)
	flat = flat.normalized() if flat.length() > 0.001 else Vector3.BACK
	var left := Vector3.UP.cross(flat).normalized()
	return pelvis_world + left * profile.hip_joint_offset.x * (1.0 if foot == LEFT else -1.0) + flat * profile.hip_joint_offset.z + Vector3.DOWN * profile.hip_joint_offset.y


## A foot standing on whatever surface is under it (terrain contact for a body at rest): the ankle target for foot `foot` of a body at `body` facing `forward`. The foot goes where the foot would be (under the
## body, to its side, pointing the way the body faces), onto the tread under it, moved just enough that heel and toe are inside that tread and the foot is inside the stair's width. Left and right can therefore be
## on different treads (a body turned across the stair, a body on a riser line). Pure: a function of the stair and the body.
static func stance_foot(model: StairModel, profile: StairProfile, foot: int, body: Vector3, forward: Vector3) -> Dictionary:
	var flat := Vector3(forward.x, 0.0, forward.z)
	flat = flat.normalized() if flat.length() > 0.001 else model.direction
	var left := Vector3.UP.cross(flat).normalized()
	var desired := body + left * profile.foot_half_spread * (1.0 if foot == LEFT else -1.0)
	var stair_left := Vector3.UP.cross(model.direction).normalized()
	var along := flat.dot(model.direction)
	var across := flat.dot(stair_left)
	var front := profile.foot_front * absf(along) + profile.foot_half_width * absf(across)
	var back := profile.foot_back * absf(along) + profile.foot_half_width * absf(across)
	var half_across := profile.foot_front * absf(across) + profile.foot_half_width * absf(along)
	var s_foot := model.progress_of(desired)
	var lateral := (desired - model.low).dot(stair_left)
	var tread := 0
	if s_foot >= model.riser_s(1):
		tread = mini(model.count + 1, int(floor((s_foot - model.riser_s(1)) / model.tread_depth)) + 1)
	var height := model.low.y if tread == 0 else (model.top() if tread > model.count else model.tread_top(tread))
	if tread >= 1 and tread <= model.count:
		var span := model.tread_span(tread)
		var low := span.x + back + profile.tread_margin
		var high := span.y - front - profile.tread_margin
		s_foot = clampf(s_foot, low, high) if low <= high else (span.x + span.y) * 0.5
	elif tread == 0:
		s_foot = minf(s_foot, model.riser_s(1) - front - profile.tread_margin)
	else:
		s_foot = maxf(s_foot, model.end_s() + back + profile.tread_margin)
	var reach := maxf(model.width * 0.5 - half_across - profile.tread_margin, 0.0)
	lateral = clampf(lateral, -reach, reach)
	var point := model.low + model.direction * s_foot + stair_left * lateral
	return {"position": Vector3(point.x, height + profile.ankle_height, point.z), "planted": true, "hold": -1, "swing": 0.0, "tread_top": height}


## The foot as the pose shows it: the gait's foot (feet follow the body across the stair), blended into the terrain stance as the body slows (`settle`), so a stop settles onto valid treads
## smoothly instead of freezing the stride. `body` is the root, `forward` its facing, `speed` its speed along the stair.
static func contact_foot(model: StairModel, profile: StairProfile, hold_list: Array, ascending: bool, s: float, foot: int, body: Vector3, forward: Vector3, speed: float) -> Dictionary:
	var lateral := lateral_of(model, body) if profile.lateral_follow_enabled else 0.0
	var gait := foot_at(model, profile, hold_list, ascending, s, foot, lateral)
	var settle := settle_weight(profile, speed)
	if settle <= 0.0:
		return gait
	var stance := stance_foot(model, profile, foot, body, forward)
	var result := gait.duplicate()
	result["position"] = (gait.position as Vector3).lerp(stance.position, settle)
	result["planted"] = bool(gait.planted) or settle >= 0.5
	result["settle"] = settle
	result["tread_top"] = lerpf(float(gait.tread_top), float(stance.tread_top), settle)
	return result


## 1 when the body is at rest, 0 when it is walking: the weight of the terrain stance.
static func settle_weight(profile: StairProfile, speed: float) -> float:
	if not profile.settle_enabled:
		return 0.0
	return 1.0 - smoothstep(profile.settle_speed_low, profile.settle_speed_high, speed)


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
static func pelvis(profile: StairProfile, body_xz: Vector3, feet: Array, smooth_floor := NAN, forward := Vector3.BACK) -> Dictionary:
	var min_chord := profile.leg_length * sin(deg_to_rad(profile.min_knee_interior_degrees) * 0.5)   # thigh = shin = leg/2: the chord across the knee angle
	var max_chord := profile.leg_length * profile.max_leg_extension
	var low := -INF
	var high := INF
	for index in feet.size():
		var foot: Dictionary = feet[index]
		var ankle: Vector3 = foot.position
		# The leg hangs from its hip JOINT (sideways of the pelvis origin and below it), not from the origin: reach and knee fold are measured from there.
		var joint := hip_joint(profile, Vector3(body_xz.x, 0.0, body_xz.z), forward, index)
		var horizontal := Vector2(ankle.x - joint.x, ankle.z - joint.z).length()
		var vertical_max := sqrt(maxf(max_chord * max_chord - horizontal * horizontal, 0.0))
		high = minf(high, ankle.y + vertical_max + profile.hip_joint_offset.y)
		if bool(foot.planted):
			low = maxf(low, ankle.y + sqrt(maxf(min_chord * min_chord - horizontal * horizontal, 0.0)) + profile.hip_joint_offset.y)
	if low == -INF:
		low = high - 0.2
	# The extension limit (97% of the leg) and the knee limit are comfort margins, not the leg's real limits, so a window narrower than REACH_TOLERANCE is met in the middle instead of being reported as unreachable.
	var ok := low <= high + REACH_TOLERANCE
	if not ok:
		return {"height": high, "ok": false, "low": low, "high": high}
	if low > high:
		return {"height": (low + high) * 0.5, "ok": true, "low": low, "high": high}
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
static func pelvis_smoothed(model: StairModel, profile: StairProfile, hold_list: Array, ascending: bool, s: float, body_xz: Vector3, feet := [], forward := Vector3.BACK) -> Dictionary:
	var feet_now: Array = feet if feet.size() == 2 else [foot_at(model, profile, hold_list, ascending, s, LEFT), foot_at(model, profile, hold_list, ascending, s, RIGHT)]
	return pelvis(profile, body_xz, feet_now, floor_reference(model, profile, s), forward)


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
