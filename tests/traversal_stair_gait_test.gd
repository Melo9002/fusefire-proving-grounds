extends SceneTree
## Stair dimensions and gait (pure planner): the exaggerated range stairs (0.5 m risers) and a realistic stair (0.17 m risers, 0.28 m treads), up and down, flat-to-stair and
## stair-to-flat hand-over, and the contact policy at walking, jogging and running speeds. No skipped step is forced where the legs cannot reach.
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _stair(rise: float, depth: float, count: int, first_riser: float) -> StairModel:
	var model := StairModel.new()
	model.low = Vector3.ZERO
	model.direction = Vector3.BACK
	model.tread_rise = rise
	model.tread_depth = depth
	model.count = count
	model.first_riser = first_riser
	return model

func _lateral_control(model: StairModel, profile: StairProfile) -> void:
	model.width = 1.6
	var left := Vector3.UP.cross(model.direction)
	var center := model.point_at(model.riser_s(4) + model.tread_depth * 0.5, model.tread_top(4))
	var previous := [{}, {}]
	var max_follow_drift := 0.0
	var max_step_drift := 0.0
	var plant_pairs := 0
	var swing_samples := 0
	for i in 51:
		var body := center + left * (float(i) * 0.01 - 0.25)
		for foot in 2:
			var step := StairFootPlanner.side_step_foot(model, profile, foot, body, left)
			var follow := StairFootPlanner.stance_foot(model, profile, foot, body, left)
			var prior: Dictionary = previous[foot]
			if not step.planted:
				swing_samples += 1
			if not prior.is_empty() and prior.step.planted and step.planted:
				plant_pairs += 1
				max_step_drift = maxf(max_step_drift, absf(((step.position as Vector3) - (prior.step.position as Vector3)).dot(left)))
				max_follow_drift = maxf(max_follow_drift, absf(((follow.position as Vector3) - (prior.follow.position as Vector3)).dot(left)))
			previous[foot] = {"step": step, "follow": follow}
	check(plant_pairs > 10 and swing_samples > 10 and max_follow_drift > 0.009 and max_step_drift < 0.001, "Side-step control: planted target drift %.2f mm vs %.2f mm for body-following stance (%d plant pairs, %d swing samples)" % [max_step_drift * 1000.0, max_follow_drift * 1000.0, plant_pairs, swing_samples])

## Walks the whole stair (and a metre of flat each side) at `step` treads per step and measures the feet and pelvis.
func _measure(model: StairModel, profile: StairProfile, ascending: bool, step: int) -> Dictionary:
	var holds := StairFootPlanner.holds(model, ascending, step)
	var enter := 0.0
	var exit := model.riser_s(model.count)
	var s_from := enter - 1.0 if ascending else exit + 1.0
	var s_to := exit + 1.0 if ascending else enter - 1.0
	var direction := 1.0 if s_to > s_from else -1.0
	var s := s_from
	var result := {"unreachable": 0, "planted_moved": 0, "worst_clamp": 0.0, "min_interior": 999.0, "pelvis_jump": 0.0, "pelvis_range": [INF, -INF], "weight_jump": 0.0, "end_weights": [], "penetration": 0, "samples": 0}
	var last_height := INF
	var last_weight := 0.0
	var first := true
	while (s - s_to) * direction < 0.0:
		var feet := []
		for foot in 2:
			var info := StairFootPlanner.foot_at(model, profile, holds, ascending, s, foot)
			feet.append(info)
			var sole := (info.position as Vector3).y - profile.ankle_height
			if sole < model.height_at(model.progress_of(info.position)) - 0.001 and model.progress_of(info.position) > model.riser_s(1) - 0.001:
				result.penetration += 1
		var weight := StairFootPlanner.weight_at(s, enter if ascending else exit, exit if ascending else enter, model.tread_depth * 1.5)
		if first:
			result.end_weights.append(weight)
			first = false
		result.weight_jump = maxf(result.weight_jump, absf(weight - last_weight))
		last_weight = weight
		var root := model.point_at(s, model.low.y)
		var facing: Vector3 = model.direction if ascending else -model.direction
		var solved := StairFootPlanner.pelvis_smoothed(model, profile, holds, ascending, s, root, [], facing)
		if weight > 0.5:
			result.samples += 1
			if not solved.ok:
				result.unreachable += 1
			for foot in 2:
				var hip := StairFootPlanner.hip_joint(profile, Vector3(root.x, solved.height, root.z), facing, foot)   # each leg hangs from its hip joint
				var limited := StairFootPlanner.limit_ankle(profile, hip, feet[foot].position)
				if feet[foot].planted and limited.distance_to(feet[foot].position) > StairFootPlanner.REACH_TOLERANCE:
					result.planted_moved += 1
				if not feet[foot].planted:
					result.worst_clamp = maxf(result.worst_clamp, limited.distance_to(feet[foot].position))
				var chord := hip.distance_to(limited)
				result.min_interior = minf(result.min_interior, rad_to_deg(acos(clampf(1.0 - chord * chord / (2.0 * pow(profile.leg_length * 0.5, 2.0)), -1.0, 1.0))))
			if last_height != INF:
				result.pelvis_jump = maxf(result.pelvis_jump, absf(solved.height - last_height))
			last_height = solved.height
			result.pelvis_range = [minf(result.pelvis_range[0], solved.height), maxf(result.pelvis_range[1], solved.height)]
		else:
			last_height = INF
		s += 0.002 * direction
	result.end_weights.append(last_weight)
	return result

func _run() -> void:
	var profile := StairProfile.new()
	var profile_speed := profile.speed
	var extreme := _stair(0.5, 0.5, 6, 0.5)
	var realistic := _stair(0.17, 0.28, 14, 0.5)
	_lateral_control(_stair(0.17, 0.28, 14, 0.5), profile)

	check(is_equal_approx(realistic.height_at(realistic.riser_s(14) + 0.1), 14 * 0.17), "The realistic stair rises 2.38 m over 14 treads")
	for entry in [["range stairs 0.5/0.5", extreme, 1], ["realistic 0.17/0.28", realistic, 1], ["realistic 0.17/0.28", realistic, 2]]:
		var model: StairModel = entry[1]
		var step: int = entry[2]
		for ascending in [true, false]:
			var label := "%s %s step %d" % [entry[0], "up" if ascending else "down", step]
			var measured := _measure(model, profile, ascending, step)
			print("  %s: tightest knee %.0f deg, pelvis %.2f..%.2f m (worst jump %.4f m per 2 mm), swing foot pulled in %.3f m, unreachable %d, weight jump %.4f" % [label, measured.min_interior, measured.pelvis_range[0], measured.pelvis_range[1], measured.pelvis_jump, measured.worst_clamp, measured.unreachable, measured.weight_jump])
			check(measured.unreachable == 0 and measured.planted_moved == 0, "%s: both legs reach and the knee limit never moves a planted foot (%d unreachable, %d moved)" % [label, measured.unreachable, measured.planted_moved])
			check(measured.min_interior >= profile.min_knee_interior_degrees - 1.0, "%s: no knee folds past %.0f degrees (tightest %.0f)" % [label, profile.min_knee_interior_degrees, measured.min_interior])
			check(measured.penetration == 0, "%s: no sole goes below a tread (%d)" % [label, measured.penetration])
			check(float(measured.pelvis_jump) < 0.012, "%s: the pelvis height is continuous: no step larger than %.4f m per 2 mm of travel, i.e. at most %.1f m/s of vertical pelvis speed at the %.1f m/s stair walk" % [label, measured.pelvis_jump, float(measured.pelvis_jump) / 0.002 * profile_speed, profile_speed])
			check(float(measured.weight_jump) < 0.01 and is_equal_approx(float(measured.end_weights[0]), 0.0) and is_equal_approx(float(measured.end_weights[1]), 0.0), "%s: flat-to-stair and stair-to-flat hand-over is smooth and exactly zero at both ends (jump %.4f)" % [label, measured.weight_jump])
			# The measured leg (0.767 m from the hip joint) is shorter than the 0.84 the planner used to assume, so the 0.5 m risers pull the swing foot in more (a deliberately extreme stair).
			var clamp_limit := 0.08 if model.tread_rise < 0.3 else 0.12
			check(float(measured.worst_clamp) < clamp_limit, "%s: the swing foot needs at most %.3f m of correction (limit %.2f)" % [label, measured.worst_clamp, clamp_limit])

	# ---- The pelvis follows the stair (it is placed from the feet, so it rises with them).
	var up := _measure(realistic, profile, true, 1)
	check(float(up.pelvis_range[1]) - float(up.pelvis_range[0]) > 1.5, "The pelvis climbs with the stair (range %.2f m over 2.38 m of rise, within the walked part)" % (float(up.pelvis_range[1]) - float(up.pelvis_range[0])))

	# ---- Skipping a tread where the legs cannot span it is reported, not forced.
	var forced := _measure(extreme, profile, true, 2)
	print("  forced every second tread on the 0.5 m stairs: unreachable %d of %d samples, tightest knee %.0f deg" % [forced.unreachable, forced.samples, forced.min_interior])
	check(forced.unreachable > 0, "Forcing ALTERNATE on 0.5 m risers is outside the legs' reach and says so (%d samples unreachable): AUTO never does it" % forced.unreachable)

	# ---- Policy at gait speeds: walking every tread, jogging and running skip one only where the legs can span it.
	for speed in [1.2, 3.0, 4.6]:
		var on_extreme := profile.step_treads(speed, false, extreme.tread_rise)
		var on_realistic := profile.step_treads(speed, false, realistic.tread_rise)
		var expected_realistic := 1 if speed < profile.alternate_from_speed else 2
		print("  AUTO at %.1f m/s: range stairs every %d tread(s), realistic stair every %d" % [speed, on_extreme, on_realistic])
		check(on_extreme == 1, "At %.1f m/s AUTO puts a foot on every tread of the 0.5 m stairs (the double rise is beyond reach)" % speed)
		check(on_realistic == expected_realistic, "At %.1f m/s AUTO is %d on the realistic stair" % [speed, expected_realistic])
		if on_realistic == 2:
			var skipped := _measure(realistic, profile, true, 2)
			check(skipped.unreachable == 0, "...and that skipping is reachable (%d unreachable)" % skipped.unreachable)
	check(profile.step_treads(4.6, true, realistic.tread_rise) == 1, "A loaded carrier never skips a tread")

	print("Stair gait: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
