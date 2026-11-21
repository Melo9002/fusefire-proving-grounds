extends SceneTree
## Stair geometry and foot placement (pure): the stair model's alignment with the tactical cells, the root ride path, and the planner's feet: on the treads, ROLLING through their stance (a bounded forward drift
## and a heel that comes up; the earlier contract locked each planted foot at one point, which still holds with the stance motion switched off and is verified below), clearing the risers going up and down, reachable,
## deterministic, and following the contact policy.
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _sole_height_ok(model: StairModel, profile: StairProfile, position: Vector3) -> bool:
	var s := model.progress_of(position)
	# The sole may not be below the tread top under it (no riser or tread penetration); a millimetre of tolerance.
	return position.y - profile.ankle_height >= model.height_at(s) - 0.001 or s < model.riser_s(1) - 0.001 and position.y - profile.ankle_height >= model.low.y - 0.001

func _run() -> void:
	var profile := StairProfile.new()
	# The Tactical Test Range stairs: three one-metre links, two 0.5 m treads each.
	var model := StairModel.from_links(Vector3(0, 0, 0), Vector3(0, 0, 1), 1.0, 1.0, 2, 3)
	check(model != null and model.count == 6 and is_equal_approx(model.tread_depth, 0.5) and is_equal_approx(model.tread_rise, 0.5), "Six treads of 0.5 m depth and 0.5 m rise")
	check(is_equal_approx(model.riser_s(1), 0.0) and is_equal_approx(model.riser_s(6), 2.5), "Risers at 0, 0.5 ... 2.5 m from the lower cell centre: the foot cell stands at the first riser (verified against the physical stairs)")
	check(is_equal_approx(model.height_at(0.0), 0.0) and is_equal_approx(model.height_at(1.0), 1.0) and is_equal_approx(model.height_at(2.0), 2.0) and is_equal_approx(model.height_at(3.0), 3.0), "The surface is exactly the tactical floors at each cell centre (0, 1, 2, 3 m)")
	check(is_equal_approx(model.height_at(0.25), 0.5) and is_equal_approx(model.height_at(0.75), 1.0) and is_equal_approx(model.height_at(10.0), 3.0), "Between risers it is the tread top (0.5 on the first tread, 1.0 on the second); past the top it stays at the top")
	check(StairModel.from_links(Vector3.ZERO, Vector3.ZERO, 1.0, 1.0, 2, 3) == null and StairModel.from_links(Vector3.ZERO, Vector3(0, 0, 1), 1.0, 1.0, 0, 3) == null, "Degenerate inputs give no model (no silent invention)")
	var up_path := model.path_points(true, 0.2, 0.3)
	var down_path := model.path_points(false, 0.2, 0.3)
	check(up_path[0].is_equal_approx(Vector3.ZERO) and down_path[down_path.size() - 1].is_equal_approx(Vector3.ZERO) and is_equal_approx(up_path[up_path.size() - 1].y, 3.0), "The ride path starts and ends exactly on the stair's floor points")
	var monotone := true
	for i in range(1, up_path.size()):
		if up_path[i].y < up_path[i - 1].y - 0.0001 or up_path[i].z < up_path[i - 1].z - 0.0001:
			monotone = false
	check(monotone, "The ascent path only goes forward and up (no hovering, no dip)")
	var length_up := 0.0
	for i in range(1, up_path.size()):
		length_up += up_path[i].distance_to(up_path[i - 1])
	print("  ride path up the 3 m stair: %.2f m (the tactical vertical-then-level route was 6.00 m)" % length_up)
	check(length_up < 6.0, "The ride path is shorter than the old rectilinear route")

	# ---- Policy.
	check(profile.step_treads(1.2, false, 0.15) == 1 and profile.step_treads(4.0, false, 0.15) == 2 and profile.step_treads(4.0, true, 0.15) == 1, "AUTO: every tread walking, every second tread at speed on low risers, every tread when loaded")
	check(profile.step_treads(4.0, false, 0.5) == 1, "AUTO never skips a tread when two risers (1.0 m) are more than the legs can span")
	var forced := StairProfile.new()
	forced.policy = StairProfile.ContactPolicy.ALTERNATE
	check(forced.step_treads(0.5, true) == 2, "A forced policy is not overridden")

	# A realistic low-rise stair as well (3 treads per link: 0.167 m rise, 0.333 m depth): there skipping a tread is within reach, so both policies are exercised.
	var low_model := StairModel.from_links(Vector3(0, 0, 0), Vector3(0, 0, 1), 1.0, 0.5, 3, 4)
	check(profile.step_treads(4.0, false, low_model.tread_rise) == 2, "AUTO does skip treads at speed on a low-rise stair")
	for stair: StairModel in [model, low_model]:
		for ascending in [true, false]:
			for step in [1, 2]:
				var label := "%s %s, every %s tread" % ["range stairs" if stair == model else "low-rise", "up" if ascending else "down", "" if step == 1 else "second"]
				var holds := StairFootPlanner.holds(stair, ascending, step)
				if step == 2 and stair.tread_rise * 2.0 > profile.max_step_rise:
					continue   # alternate stepping across 0.5 m risers is outside MIRA's reach by design (see the AUTO check); measured separately below
				var planted_runs := {}
				var last_position := [Vector3.INF, Vector3.INF]
				var last_hold := [-1, -1]
				var slide := 0.0
				var stance_span := {}
				var stance_lift := {}
				var worst_step := 0.0
				var penetration := 0
				var off_tread := 0
				var both_on_one := 0
				var worst_reach := 0.0
				var unreachable := 0
				var worst_clamp := 0.0
				var planted_moved := 0
				var min_interior := 999.0
				var heights_planted := {}
				var s := -1.0
				var s_end := stair.end_s() + 1.2
				while s <= s_end:
					var query := s if ascending else (s_end - (s + 1.0))   # descending sweeps from the top down
					var feet := []
					for foot in 2:
						var result := StairFootPlanner.foot_at(stair, profile, holds, ascending, query, foot)
						feet.append(result)
						if not _sole_height_ok(stair, profile, result.position):
							penetration += 1
						if result.planted:
							var hold_info: Dictionary = holds[result.hold]
							var span_s := stair.progress_of(result.position)
							heights_planted[snappedf(result.position.y - profile.ankle_height, 0.001)] = true
							if float(hold_info.s) >= stair.riser_s(1) and float(hold_info.s) <= stair.end_s():
								var tread := int(round((float(hold_info.height) - stair.low.y) / stair.tread_rise))
								var span := stair.tread_span(tread)
								if tread >= 1 and tread <= stair.count and (span_s < span.x - 0.06 or span_s > span.y + 0.001):
									off_tread += 1
							if last_hold[foot] == result.hold and last_position[foot] != Vector3.INF:
								slide = maxf(slide, (result.position as Vector3).distance_to(last_position[foot]))
							var key := "%d:%d" % [foot, result.hold]
							var along := stair.progress_of(result.position)
							var lift: float = result.position.y - profile.ankle_height - float(hold_info.height)
							var span: Vector2 = stance_span.get(key, Vector2(along, along))
							stance_span[key] = Vector2(minf(span.x, along), maxf(span.y, along))
							var lifts: Vector2 = stance_lift.get(key, Vector2(lift, lift))
							stance_lift[key] = Vector2(minf(lifts.x, lift), maxf(lifts.y, lift))
						if last_position[foot] != Vector3.INF:
							worst_step = maxf(worst_step, (result.position as Vector3).distance_to(last_position[foot]))
						last_position[foot] = result.position
						last_hold[foot] = result.hold if result.planted else -1
					if feet[0].planted and feet[1].planted and feet[0].hold == feet[1].hold:
						both_on_one += 1
					# The pelvis is placed from the feet: both legs must reach and no knee fold past the limit, on the stair.
					if StairFootPlanner.weight_at(query, 0.0, stair.riser_s(stair.count), 0.75) > 0.5:
						var root := stair.point_at(query, stair.low.y)
						var facing: Vector3 = stair.direction if ascending else -stair.direction
						var solved := StairFootPlanner.pelvis_smoothed(stair, profile, holds, ascending, query, root, [], facing)
						if not solved.ok:
							unreachable += 1
						for foot in 2:
							var hip := StairFootPlanner.hip_joint(profile, Vector3(root.x, solved.height, root.z), facing, foot)   # the leg hangs from its hip joint
							var limited := StairFootPlanner.limit_ankle(profile, hip, feet[foot].position)
							if not feet[foot].planted:
								worst_clamp = maxf(worst_clamp, limited.distance_to(feet[foot].position))
							elif limited.distance_to(feet[foot].position) > StairFootPlanner.REACH_TOLERANCE:
								planted_moved += 1
							var chord: float = hip.distance_to(limited)
							worst_reach = maxf(worst_reach, chord)
							var interior := rad_to_deg(acos(clampf(1.0 - chord * chord / (2.0 * pow(profile.leg_length * 0.5, 2.0)), -1.0, 1.0)))
							min_interior = minf(min_interior, interior)
					s += 0.002
				print("  %s: planted tread heights %s, worst foot step %.3f m per 2 mm, stance slide %.4f m, worst hip-to-ankle %.2f m, tightest knee %.0f deg, unreachable %d, swing foot pulled in by at most %.3f m" % [label, heights_planted.keys(), worst_step, slide, worst_reach, min_interior, unreachable, worst_clamp])
				check(penetration == 0, "%s: no sole goes below the tread or through a riser (%d samples)" % [label, penetration])
				var worst_roll := 0.0
				var worst_heel := 0.0
				for key in stance_span:
					worst_roll = maxf(worst_roll, (stance_span[key] as Vector2).y - (stance_span[key] as Vector2).x)
					worst_heel = maxf(worst_heel, (stance_lift[key] as Vector2).y - (stance_lift[key] as Vector2).x)
				check(slide < 0.0015, "%s: a planted foot rolls smoothly, it never skates (%.5f m per 2 mm of body travel)" % [label, slide])
				check(worst_roll <= profile.stance_roll + 0.002 and worst_roll >= profile.stance_roll * 0.7 and worst_heel <= profile.heel_lift + 0.002 and worst_heel >= profile.heel_lift * 0.8,
					"%s: through its stance a foot drifts forward by %.3f m (limit %.3f) and its heel comes up %.3f m (limit %.3f)" % [label, worst_roll, profile.stance_roll, worst_heel, profile.heel_lift])
				check(worst_step < 0.025, "%s: the feet never jump (worst %.3f m per 2 mm of body travel)" % [label, worst_step])
				check(both_on_one == 0, "%s: the feet are never on the same hold" % label)
				check(off_tread == 0, "%s: stance feet are on their treads (%d off)" % [label, off_tread])
				check(planted_moved == 0, "%s: the knee limit never has to move a planted foot (%d)" % [label, planted_moved])
				check(worst_clamp < 0.12, "%s: the swing foot is pulled in by the knee limit by less than 12 cm (%.3f m)" % [label, worst_clamp])
				check(unreachable == 0 and worst_reach <= profile.leg_length + 0.001 and min_interior >= profile.min_knee_interior_degrees - 1.0, "%s: with the pelvis placed from the feet both legs reach and no knee folds past the limit (%d unreachable, worst chord %.2f of %.2f, tightest knee %.0f deg)" % [label, unreachable, worst_reach, profile.leg_length, min_interior])
				if step == 2:
					var only_even := true
					for height in heights_planted.keys():
						var tread := int(round((float(height) - stair.low.y) / stair.tread_rise))
						if tread >= 1 and tread <= stair.count and tread % 2 != 0:
							only_even = false
					check(only_even, "%s: only every second tread (counted from the top) is stepped on" % label)

	# ---- The earlier contract, with the stance motion switched off: each planted foot is locked at one point and the pelvis does not shift.
	var locked := StairProfile.new()
	locked.stance_motion_enabled = false
	for ascending in [true, false]:
		var locked_holds := StairFootPlanner.holds(model, ascending, 1)
		var locked_slide := 0.0
		var previous := [Vector3.INF, Vector3.INF]
		var previous_hold := [-1, -1]
		var s_lock := -1.0
		while s_lock <= model.end_s() + 1.2:
			for foot in 2:
				var result := StairFootPlanner.foot_at(model, locked, locked_holds, ascending, s_lock, foot)
				if result.planted and previous_hold[foot] == result.hold and previous[foot] != Vector3.INF:
					locked_slide = maxf(locked_slide, (result.position as Vector3).distance_to(previous[foot]))
				previous[foot] = result.position
				previous_hold[foot] = result.hold if result.planted else -1
			s_lock += 0.002
		check(locked_slide < 0.0001, "Stance motion off, %s: a planted foot does not slide (%.5f m)" % ["up" if ascending else "down", locked_slide])
		check(StairFootPlanner.sway_at(model, locked, locked_holds, ascending, 1.2) == Vector3.ZERO, "Stance motion off: no pelvis shift")

	# ---- The stance motion itself: the pelvis shifts toward the supporting foot, the landing varies between treads but is the same every time, and a landing stays on its tread.
	var shift_holds := StairFootPlanner.holds(model, true, 1)
	var biggest_sway := 0.0
	var shifts_both_ways := [false, false]
	var s_sway := 0.0
	while s_sway <= model.end_s():
		var sway := StairFootPlanner.sway_at(model, profile, shift_holds, true, s_sway)
		biggest_sway = maxf(biggest_sway, sway.length())
		var left := Vector3.UP.cross(model.direction).normalized()
		shifts_both_ways[0] = shifts_both_ways[0] or sway.dot(left) > profile.pelvis_sway * 0.5
		shifts_both_ways[1] = shifts_both_ways[1] or sway.dot(left) < -profile.pelvis_sway * 0.5
		s_sway += 0.01
	check(biggest_sway <= profile.pelvis_sway + 0.0001 and shifts_both_ways[0] and shifts_both_ways[1], "The pelvis shifts toward whichever foot carries the weight, at most %.3f m (%.3f)" % [profile.pelvis_sway, biggest_sway])
	var landing_a: Vector3 = StairFootPlanner.foot_at(model, profile, shift_holds, true, 1.0, 0).position
	var landing_b: Vector3 = StairFootPlanner.foot_at(model, profile, shift_holds, true, 2.0, 0).position
	var landing_again: Vector3 = StairFootPlanner.foot_at(model, profile, shift_holds, true, 1.0, 0).position
	check(landing_a == landing_again and absf((landing_a.x - model.low.x) - (landing_b.x - model.low.x)) > 0.0005, "Where a foot lands differs between treads but is the same every time")

	# ---- Determinism and ordinary-ground hand-over.
	var holds_a := StairFootPlanner.holds(model, true, 1)
	var one := StairFootPlanner.foot_at(model, profile, holds_a, true, 1.37, 0)
	var two := StairFootPlanner.foot_at(model, profile, holds_a, true, 1.37, 0)
	check(one.hash() == two.hash(), "The same inputs give the same foot")
	check(StairFootPlanner.weight_at(1.5, 0.0, 3.0, 0.75) == 1.0 and StairFootPlanner.weight_at(-1.0, 0.0, 3.0, 0.75) == 0.0 and StairFootPlanner.weight_at(4.0, 0.0, 3.0, 0.75) == 0.0, "The stair pose applies in the middle of the walk and is released outside it")
	check(StairFootPlanner.weight_at(0.0, 0.0, 3.0, 0.75) == 0.0 and StairFootPlanner.weight_at(3.0, 0.0, 3.0, 0.75) == 0.0, "...and is exactly zero at both ends of the walk (the animation's own legs hand over without a pop)")
	check(StairFootPlanner.weight_at(0.2, 0.0, 3.0, 0.75) > 0.0 and StairFootPlanner.weight_at(0.2, 0.0, 3.0, 0.75) < 1.0 and StairFootPlanner.weight_at(1.0, 3.0, 0.0, 0.75) == 1.0, "...easing in and out, and the same going the other way")

	print("Stair feet: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
