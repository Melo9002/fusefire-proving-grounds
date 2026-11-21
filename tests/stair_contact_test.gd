extends SceneTree
## Stair contact, foot orientation and balance. Part 1 (pure planner): feet follow the body across the stair, stay inside the tread and the stair's width, a body at rest stands on the tread under each
## foot, the legs hang from the hip joints. Part 2 (the rig, on the playground's stairs): measured from the skeleton AFTER the whole modifier stack, a MIRA that stops half way up stands with no heel,
## ball or toe below the tread, at the centre and at the edge, and her legs reach. NEGATIVE CONTROLS: each correction is switched off and the matching measurement must fail.
const PLAYGROUND := "res://research/exploration_playground/exploration_playground.tscn"
var failures := 0
var checks := 0
var world: Node


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _press(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


func _planner_part() -> void:
	var profile := StairProfile.new()
	var model := StairModel.new()
	model.low = Vector3.ZERO
	model.direction = Vector3.BACK
	model.tread_depth = 0.4
	model.tread_rise = 0.2
	model.first_riser = 0.0
	model.count = 10
	model.width = 1.6
	var left := Vector3.UP.cross(model.direction).normalized()
	var holds := StairFootPlanner.holds(model, true, 1)
	# Feet follow the body across the stair (lateral), and stay inside its width.
	var body_offset := 0.55
	var centre := StairFootPlanner.foot_at(model, profile, holds, true, 1.0, StairFootPlanner.LEFT)
	var followed := StairFootPlanner.foot_at(model, profile, holds, true, 1.0, StairFootPlanner.LEFT, body_offset)
	check(absf((followed.position - centre.position).dot(left) - body_offset) < 0.02, "A foot follows a body that walks %.2f m off the stair's centre line (moved %.3f m)" % [body_offset, (followed.position - centre.position).dot(left)])
	var wide := StairFootPlanner.foot_at(model, profile, holds, true, 1.0, StairFootPlanner.LEFT, 3.0)
	check(absf(((wide.position as Vector3) - model.low).dot(left)) <= model.width * 0.5 - profile.foot_half_width + 0.0001, "A foot never leaves the stair's width, however far the body is (lateral %.3f of half-width %.2f)" % [((wide.position as Vector3) - model.low).dot(left), model.width * 0.5])
	# Negative control: lateral follow off reproduces the feet glued to the centre line.
	var glued := StairProfile.new()
	glued.lateral_follow_enabled = false
	var glued_foot := StairFootPlanner.contact_foot(model, glued, holds, true, 1.0, StairFootPlanner.LEFT, model.low + left * body_offset + model.direction * 1.0, model.direction, 1.4)
	var following_foot := StairFootPlanner.contact_foot(model, profile, holds, true, 1.0, StairFootPlanner.LEFT, model.low + left * body_offset + model.direction * 1.0, model.direction, 1.4)
	check(absf((following_foot.position - glued_foot.position).dot(left)) > 0.4, "Negative control: with lateral_follow_enabled off the foot stays on the centre line (%.3f m from the following foot)" % (following_foot.position - glued_foot.position).dot(left))
	# Heel and toe stay on the tread (forward clamp), every tread, with and without the roll.
	var over := 0
	var over_unclamped := 0
	profile.stance_roll = 0.12   # a long roll: the clamp must hold the toe on the tread; without it the roll carries the toe off
	var unclamped := StairProfile.new()
	unclamped.stance_roll = 0.12
	unclamped.tread_clamp_enabled = false
	var s := 0.0
	while s < 3.5:
		for foot in 2:
			for p in [profile, unclamped]:
				var f := StairFootPlanner.foot_at(model, p, holds, true, s, foot)
				if f.planted:
					var tread_s := model.progress_of(f.position)
					var tread := int(floor((tread_s - model.riser_s(1)) / model.tread_depth)) + 1
					if tread >= 1 and tread <= model.count:
						var span := model.tread_span(tread)
						if tread_s + profile.foot_front > span.y + 0.0005 or tread_s - profile.foot_back < span.x - 0.0005:
							if p == profile:
								over += 1
							else:
								over_unclamped += 1
		s += 0.01
	check(over == 0, "A planted foot's toe and heel are inside its tread through a whole climb (%d violations)" % over)
	check(over_unclamped > 0, "Negative control: with tread_clamp_enabled off the roll carries the toe off a 0.4 m tread (%d violations)" % over_unclamped)
	# Terrain stance: the foot's sole stands on the tread under it, feet may be on different treads.
	profile.stance_roll = 0.06
	var on_riser := model.low + model.direction * model.riser_s(3)   # a body exactly on a riser line
	var stance_l := StairFootPlanner.stance_foot(model, profile, StairFootPlanner.LEFT, on_riser, model.direction)
	var stance_r := StairFootPlanner.stance_foot(model, profile, StairFootPlanner.RIGHT, on_riser, left)   # turned across the stair: one foot each side of the riser line
	var stance_across := stance_r
	check(is_equal_approx((stance_l.position as Vector3).y, float(stance_l.tread_top) + profile.ankle_height) and bool(stance_l.planted), "A body at rest puts the ankle exactly the sole height above the tread under the foot")
	var span_l := model.tread_span(int(round(((stance_l.tread_top as float) - model.low.y) / model.tread_rise)))
	check(model.progress_of(stance_l.position) + profile.foot_front <= span_l.y + 0.0005 and model.progress_of(stance_l.position) - profile.foot_back >= span_l.x - 0.0005, "At rest the whole foot is inside the tread: toe and heel margins hold even on a riser line")
	var across_l := StairFootPlanner.stance_foot(model, profile, StairFootPlanner.LEFT, on_riser, left)
	check(not is_equal_approx(float(across_l.tread_top), float(stance_across.tread_top)) and is_equal_approx(float(across_l.position.y), float(across_l.tread_top) + profile.ankle_height) and is_equal_approx(float(stance_across.position.y), float(stance_across.tread_top) + profile.ankle_height), "A body turned across a riser line has each foot on its own tread (%.2f and %.2f), each ankle a sole height above it" % [across_l.tread_top, stance_across.tread_top])
	var turned := StairFootPlanner.stance_foot(model, profile, StairFootPlanner.LEFT, model.low + model.direction * 1.1, left)   # facing across the stair
	var across_reach := model.width * 0.5
	check(absf(((turned.position as Vector3) - model.low).dot(left)) <= across_reach, "Facing across the stair keeps the foot inside the stair's width")
	# Settling blends the stride into the stance by speed; off means never.
	check(is_equal_approx(StairFootPlanner.settle_weight(profile, 0.0), 1.0) and is_equal_approx(StairFootPlanner.settle_weight(profile, 1.4), 0.0), "Settle weight is 1 at rest and 0 at walking speed")
	check(is_equal_approx(StairFootPlanner.settle_weight(glued, 0.0), 1.0), "Settle weight stays 1 at rest for a profile that only changes lateral_follow")
	var no_settle := StairProfile.new()
	no_settle.settle_enabled = false
	check(is_equal_approx(StairFootPlanner.settle_weight(no_settle, 0.0), 0.0), "Negative control: settle_enabled off never settles")
	var rest_body := model.low + model.direction * 1.3 + left * 0.3
	var settled_foot := StairFootPlanner.contact_foot(model, profile, holds, true, 1.3, 0, rest_body, model.direction, 0.0)
	var frozen_foot := StairFootPlanner.contact_foot(model, no_settle, holds, true, 1.3, 0, rest_body, model.direction, 0.0)
	var stance_only := StairFootPlanner.stance_foot(model, profile, 0, rest_body, model.direction)
	check((settled_foot.position as Vector3).distance_to(stance_only.position) < 0.0001 and bool(settled_foot.planted), "At rest the foot is exactly the terrain stance")
	check((frozen_foot.position as Vector3).distance_to(stance_only.position) > 0.01, "Negative control: with settle_enabled off the stopped foot stays on the frozen stride (%.3f m from the stance)" % (frozen_foot.position as Vector3).distance_to(stance_only.position))
	# The legs hang from the hip joints: the pelvis solved for the planted feet keeps both legs in reach from the joint, not from the pelvis origin.
	var worst := 0.0
	s = 0.3
	while s < 3.0:
		var feet := [StairFootPlanner.foot_at(model, profile, holds, true, s, 0, 0.55), StairFootPlanner.foot_at(model, profile, holds, true, s, 1, 0.55)]
		var body := model.low + model.direction * s + left * 0.55
		var solved := StairFootPlanner.pelvis(profile, body, feet, StairFootPlanner.floor_reference(model, profile, s), model.direction)
		for foot in 2:
			var joint := StairFootPlanner.hip_joint(profile, Vector3(body.x, solved.height, body.z), model.direction, foot)
			worst = maxf(worst, joint.distance_to(feet[foot].position) / profile.leg_length)
		s += 0.05
	check(worst <= 0.97 + REACH_SLACK, "Walking at the edge, both legs reach from their hip joints (%.3f of the leg)" % worst)


const REACH_SLACK := 0.02


## Stops half way up the playground stairs and measures the settled stance after the full modifier stack. Returns the worst penetration of heel, ball and toe below the tread, the worst ankle-to-target error
## of a planted foot and the longest hip-joint-to-ankle distance as a fraction of the leg.
func _stop_halfway(lateral: float, start_z := 4.4, mutate := Callable()) -> Dictionary:
	var rig: CharacterRig = world.visual.rig
	var stairs: StairModel = world.traversal.stairs
	var profile := rig.stair_profile
	world.body.global_position = Vector3(stairs.low.x + lateral, 0.0, start_z)
	world.body.velocity = Vector3.ZERO
	world.yaw = PI
	world.pitch = 0.0
	world._apply_camera_rotation()
	world.pivot_position = world._focus_point()
	await _wait(0.8)
	var settled := {"on": false, "phase": "walk"}
	var data := {"walk": {"toe": 0.0, "heel": 0.0, "ik": 0.0, "reach": 0.0, "off": 0.0, "hips_low": 9.0, "n": 0}, "rest": {"toe": 0.0, "heel": 0.0, "ik": 0.0, "reach": 0.0, "off": 0.0, "hips_low": 9.0, "n": 0}}
	var skeleton := rig.skeleton
	var ankles := [skeleton.find_bone(rig.bones.left_leg[2]), skeleton.find_bone(rig.bones.right_leg[2])]
	var toes := [skeleton.find_bone(rig.bones.left_toes), skeleton.find_bone(rig.bones.right_toes)]
	var thighs := [skeleton.find_bone(rig.bones.left_leg[0]), skeleton.find_bone(rig.bones.right_leg[0])]
	var right_axis := stairs.direction.cross(Vector3.UP)
	var hips_bone := skeleton.find_bone(rig.bones.hips)
	var sample := func() -> void:
		if not settled.on or not world.traversal.on_stairs:
			return
		if rig.stairs == null or rig.stairs.pose == null or float(rig.stairs.pose.weight) < 0.99:
			return   # only with the stair pose fully on (the blend in and out is the animation's own legs)
		var to_world := skeleton.global_transform
		var d: Dictionary = data[settled.phase]
		for foot in 2:
			var ankle: Vector3 = to_world * skeleton.get_bone_global_pose(ankles[foot]).origin
			var ball: Vector3 = to_world * skeleton.get_bone_global_pose(toes[foot]).origin
			var direction := Vector3(ball.x - ankle.x, 0.0, ball.z - ankle.z)
			direction = direction.normalized() if direction.length() > 0.01 else Vector3.BACK
			var tip := ball + direction * 0.07
			var heel := ankle - direction * 0.07
			var sole := ankle.y - profile.ankle_height
			var ball_sole := ball.y - 0.028
			var surface := func(point: Vector3) -> float:
				if absf((point - stairs.low).dot(right_axis)) > stairs.width * 0.5 + 0.02:
					return 0.0
				var along := stairs.progress_of(point)
				return stairs.low.y if along < 0.0 else (stairs.top() if along > stairs.end_s() else stairs.height_at(along))
			d.heel = maxf(d.heel, surface.call(heel) - sole)
			d.toe = maxf(d.toe, maxf(surface.call(tip) - ball_sole, surface.call(ball) - ball_sole))
			var marker: Vector3 = rig.traversal_modifier.foot_targets[foot].global_position
			if rig.stairs != null and rig.stairs.pose != null and rig.stairs.pose.feet[foot].planted:
				d.ik = maxf(d.ik, marker.distance_to(ankle))
			d.off = maxf(d.off, absf((ankle - world.body.global_position).dot(right_axis)))   # how far the foot is from the body's own line across the stair
			var hip_joint: Vector3 = to_world * skeleton.get_bone_global_pose(thighs[foot]).origin
			d.reach = maxf(d.reach, hip_joint.distance_to(ankle) / profile.leg_length)
		var hips: Vector3 = to_world * skeleton.get_bone_global_pose(hips_bone).origin
		d.hips_low = minf(d.hips_low, hips.y - world.body.global_position.y)
		d.n += 1
	skeleton.skeleton_updated.connect(sample)
	if mutate.is_valid():
		mutate.call(rig, true)
	settled.on = true
	_press(&"playground_forward", true)
	await _wait(2.4)
	_press(&"playground_forward", false)
	settled.phase = "rest"
	await _wait(1.2)
	settled.on = false
	skeleton.skeleton_updated.disconnect(sample)
	if mutate.is_valid():
		mutate.call(rig, false)
	await _wait(0.3)
	return data


func _rig_part() -> void:
	world = load(PLAYGROUND).instantiate()
	root.add_child(world)
	current_scene = world
	await _wait(1.0)
	var rig: CharacterRig = world.visual.rig
	check(rig.foot_modifier != null and rig.stair_profile.ankle_height > 0.1 and rig.stair_profile.leg_length < 0.8, "The rig measured its own anatomy (leg %.3f, ankle %.3f) and built the foot stage" % [rig.stair_profile.leg_length, rig.stair_profile.ankle_height])
	var centre := await _stop_halfway(0.0)
	var edge := await _stop_halfway(0.55)
	for pair in [["centre", centre], ["edge", edge]]:
		var walk: Dictionary = pair[1].walk
		var rest: Dictionary = pair[1].rest
		print("  %s: walking up ik %.3f reach %.2f | at rest toe %.3f heel %.3f ik %.3f reach %.2f (%d frames)" % [pair[0], walk.ik, walk.reach, rest.toe, rest.heel, rest.ik, rest.reach, rest.n])
		check(int(rest.n) > 20 and int(walk.n) > 100, "Half way up (%s): the stair pose was sampled (%d walking, %d resting frames)" % [pair[0], walk.n, rest.n])
		check(float(rest.toe) <= 0.01 and float(rest.heel) <= 0.01, "Stopped half way up (%s): no heel, ball or toe below the tread (toe %.3f m, heel %.3f m)" % [pair[0], rest.toe, rest.heel])
		check(float(rest.ik) <= 0.01 and float(walk.ik) <= 0.02, "Half way up (%s): the planted ankles are on their targets, walking %.3f m and at rest %.3f m: the legs reach" % [pair[0], walk.ik, rest.ik])
		check(float(walk.off) <= 0.25 and float(walk.hips_low) >= 0.84, "Half way up (%s): each foot stays under its own side of the body (at most %.2f m across) and the pelvis keeps its height (%.2f m)" % [pair[0], walk.off, walk.hips_low])
		check(float(rest.reach) <= 1.0 and float(walk.reach) <= 1.0, "Half way up (%s): no leg is stretched past its length (walking %.3f, at rest %.3f of it)" % [pair[0], walk.reach, rest.reach])
	# Negative controls: each correction off, and its own measurement must fail.
	var no_feet := await _stop_halfway(0.0, 4.4, func(r: CharacterRig, on: bool) -> void:
		if r.foot_modifier != null:
			r.foot_modifier.active = not on)
	check(float(no_feet.rest.toe) > 0.02, "Negative control: without the foot-orientation stage the toes go %.3f m into the tread" % no_feet.rest.toe)
	var no_follow := await _stop_halfway(0.55, 4.4, func(r: CharacterRig, on: bool) -> void:
		r.stair_profile.lateral_follow_enabled = not on)
	print("  lateral follow off, edge: feet %.2f m across from the body, pelvis down to %.2f m" % [no_follow.walk.off, no_follow.walk.hips_low])
	check(float(no_follow.walk.off) > 0.35 and float(no_follow.walk.hips_low) < 0.8, "Negative control: with the feet glued to the centre line a body at the edge straddles them (%.2f m across) and the pelvis collapses to %.2f m" % [no_follow.walk.off, no_follow.walk.hips_low])


func _run() -> void:
	_planner_part()
	await _rig_part()
	print("Stair contact: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures > 0 else 0)
