extends SceneTree
## Feet on a slope and the hand-over to the stairs, in the real Exploration Playground (Prototype 1.5 playground assignment), measured in the FINAL pose (sampled at `skeleton_updated`).
##  * GroundSupport's plan (pure): flat ground is flat, a slope shifts each foot by its own ground, the pelvis follows the lower foot, ground too far off is not followed.
##  * The ramp, both characters: standing on it the feet are on the ground (and are not without the foot placement: the negative control), and walking uphill, downhill and across it the supporting ankle keeps the
##    height it has in the same walk on flat floor. Flat ground is untouched (the foot placement stays at zero weight).
##  * The stairs: a run up to them is slowed before them and the hand-over has no pop, a stop on them gathers the feet over several frames, not one. The negative control switches the pace limit and the speed
##    slew off and the pop is back.
## Bone positions, not mesh measurements. Real time (about two minutes).
const PLAYGROUND := "res://research/exploration_playground/exploration_playground.tscn"

var failures := 0
var checks := 0
var world: Node
var _clearance: Array[float] = []
var _rows: Array[Dictionary] = []


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


func _run() -> void:
	_plan_is_sane()
	world = load(PLAYGROUND).instantiate()
	root.add_child(world)
	current_scene = world
	await _wait(1.0)
	for character in [0, 1]:
		world._select_character(character)
		await _wait(0.5)
		await _ramp(character)
	await _flat_is_untouched()
	await _stairs()
	await _clean_view()
	print("playground_terrain_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)


func _plan_is_sane() -> void:
	var ankles: Array[Vector3] = [Vector3(0.1, 0.1, 0.0), Vector3(-0.1, 0.1, 0.0)]
	var flat := GroundSupport.plan(0.0, ankles, [{"y": 0.0, "normal": Vector3.UP}, {"y": 0.001, "normal": Vector3.UP}])
	check(not bool(flat.slope) and float(flat.pelvis) == 0.0, "GroundSupport: flat ground is flat (no slope, no pelvis shift)")
	var slope := GroundSupport.plan(0.0, ankles, [{"y": 0.12, "normal": Vector3(-0.24, 0.97, 0.0).normalized()}, {"y": -0.10, "normal": Vector3(-0.24, 0.97, 0.0).normalized()}])
	check(bool(slope.slope) and is_equal_approx(float(slope.shift[0]), 0.12) and is_equal_approx(float(slope.shift[1]), -0.10), "GroundSupport: each foot is shifted by its own ground")
	check(is_equal_approx(float(slope.pelvis), -0.10), "GroundSupport: the pelvis follows the lower foot (%.2f)" % float(slope.pelvis))
	var far := GroundSupport.plan(0.0, ankles, [{"y": 0.9, "normal": Vector3.UP}, {}])
	check(not bool(far.slope) and float(far.shift[0]) == 0.0, "GroundSupport: ground a metre off, or none, is not followed")
	check(GroundSupport.ease_weight(0.0, true, 0.01) > 0.0 and GroundSupport.ease_weight(1.0, false, 0.01) < 1.0 and GroundSupport.ease_weight(0.5, true, 0.0) == 0.5, "GroundSupport: the weight eases and does not move without time")


func _sample() -> void:
	var rig: CharacterRig = world.visual.rig
	var sk := rig.skeleton
	var heights: Array[float] = []
	for side in 2:
		var bone: StringName = [rig.bones.left_leg, rig.bones.right_leg][side][2]
		var ankle: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin
		var ground: Dictionary = world.visual._sample_ground(ankle)
		if ground.is_empty():
			return
		heights.append(ankle.y - float(ground.y))
	_clearance.append(minf(heights[0], heights[1]))


func _stair_sample() -> void:
	var rig: CharacterRig = world.visual.rig
	var sk := rig.skeleton
	var row := {"hips": sk.global_transform * sk.get_bone_global_pose(sk.find_bone(rig.bones.hips)).origin, "on": rig.stairs != null, "weight": rig.stairs.pose.weight if rig.stairs != null and rig.stairs.pose != null else 0.0}
	for side in 2:
		var bone: StringName = [rig.bones.left_leg, rig.bones.right_leg][side][2]
		row["ankle%d" % side] = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin
	_rows.append(row)


func _percentile(values: Array[float], q: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(q * (sorted.size() - 1)), 0, sorted.size() - 1)] if not sorted.is_empty() else 0.0


## Walks (or stands) from `start` for `seconds` with `keys` held and returns the supporting ankle's clearance over the ground under it, per frame.
func _walk(start: Vector3, camera_yaw: float, keys: Array[StringName], seconds: float) -> Array[float]:
	_clearance = []
	world.body.global_position = start
	world.body.velocity = Vector3.ZERO
	world.yaw = camera_yaw
	world.pitch = 0.0
	world._apply_camera_rotation()
	world.visual.reset_motion(camera_yaw + PI)
	await _wait(0.6)
	var callable := _sample
	world.visual.rig.skeleton.skeleton_updated.connect(callable)
	for key in keys:
		_press(key, true)
	await _wait(seconds)
	for key in keys:
		_press(key, false)
	await _wait(0.2)
	world.visual.rig.skeleton.skeleton_updated.disconnect(callable)
	return _clearance.duplicate()


func _ramp(character: int) -> void:
	var label: String = ["Regular", "Small"][character]
	var rig: CharacterRig = world.visual.rig
	var flat: Array[float] = await _walk(Vector3(-3.0, 0.0, -4.0), -PI * 0.5, [&"playground_forward"], 2.2)
	check(rig.traversal_modifier.input.ground_weight == 0.0, "%s: on flat floor the foot placement stays at zero weight" % label)
	var flat_p5 := _percentile(flat, 0.05)
	var flat_p50 := _percentile(flat, 0.5)
	# Standing on the ramp: the feet are on the ground as they are on flat floor; the negative control (no foot placement) floats.
	var flat_stand: float = _percentile(await _walk(Vector3(-3.0, 0.0, -4.0), -PI * 0.5, [], 0.8), 0.5)
	var standing: Array[float] = await _walk(Vector3(11.0, 0.7, 8.0), -PI * 0.5, [], 0.8)
	check(absf(_percentile(standing, 0.5) - flat_stand) < 0.006, "%s: standing on the ramp the supporting ankle is at the height it has on flat floor (%+.1f cm from it)" % [label, (_percentile(standing, 0.5) - flat_stand) * 100.0])
	rig.set_ground_sampler(Callable())
	var floating: Array[float] = await _walk(Vector3(11.0, 0.7, 8.0), -PI * 0.5, [], 0.8)
	rig.set_ground_sampler(world.visual._sample_ground)
	check(_percentile(floating, 0.5) - flat_stand > 0.012, "%s: control: without the foot placement the same stance floats %.1f cm" % [label, (_percentile(floating, 0.5) - flat_stand) * 100.0])
	var cases := {
		"uphill": [Vector3(7.0, 0.0, 8.0), -PI * 0.5, [&"playground_forward"], 2.2],
		"downhill": [Vector3(13.0, 1.3, 8.0), PI * 0.5, [&"playground_forward"], 2.2],
		"across": [Vector3(11.0, 0.7, 6.9), -PI * 0.5, [&"playground_right"], 1.5],
		"diagonal": [Vector3(8.2, 0.0, 6.9), -PI * 0.5, [&"playground_forward", &"playground_right"], 2.2],
	}
	for name in cases:
		var c: Array = cases[name]
		var keys: Array[StringName] = []
		for key in c[2]:
			keys.append(key)
		var walk: Array[float] = await _walk(c[0], c[1], keys, c[3])
		var p5 := _percentile(walk, 0.05)
		var p50 := _percentile(walk, 0.5)
		check(p5 > flat_p5 - 0.02 and absf(p50 - flat_p50) < 0.012, "%s %s: the supporting ankle keeps its flat-walk height (p5 %.1f vs flat %.1f cm, p50 %.1f vs %.1f)" % [label, name, p5 * 100.0, flat_p5 * 100.0, p50 * 100.0, flat_p50 * 100.0])
	# The walk onto and off the ramp's ends is part of those walks; the weight is back to zero on the flat afterwards.
	await _walk(Vector3(-3.0, 0.0, -4.0), -PI * 0.5, [&"playground_forward"], 1.2)
	check(rig.traversal_modifier.input.ground_weight == 0.0, "%s: off the ramp the foot placement is back at zero" % label)


func _flat_is_untouched() -> void:
	# The foot placement is off the legs on flat ground: the leg IK is not engaged by it.
	world._select_character(0)
	await _wait(0.4)
	var rig: CharacterRig = world.visual.rig
	await _walk(Vector3(-3.0, 0.0, -4.0), -PI * 0.5, [&"playground_forward"], 1.0)
	check(not rig.leg_ik.active, "On flat floor the foot placement leaves the leg IK off")


## Walks the stairs and returns the largest second difference (a pop) of the ankles over the frames the stair pose is in use, and over the frames of the hand-over.
func _stair_walk(run: bool, stop_after: float) -> Dictionary:
	_rows = []
	if world.traversal.on_stairs:
		world.traversal._leave_stairs()
	var stairs: StairModel = world.traversal.stairs
	world.body.global_position = stairs.low + Vector3(0.0, 0.0, -2.6)
	world.body.velocity = Vector3.ZERO
	world.yaw = PI
	world.pitch = 0.0
	world._apply_camera_rotation()
	world.visual.reset_motion(0.0)
	await _wait(0.6)
	var callable := _stair_sample
	world.visual.rig.skeleton.skeleton_updated.connect(callable)
	_press(&"playground_forward", true)
	_press(&"playground_run", run)
	await _wait(stop_after)
	_press(&"playground_forward", false)
	_press(&"playground_run", false)
	await _wait(0.9)
	world.visual.rig.skeleton.skeleton_updated.disconnect(callable)
	var on_stairs := 0.0
	var hand_over := 0.0
	var pelvis := 0.0
	for i in range(1, _rows.size() - 1):
		var b: Dictionary = _rows[i]
		var handing := float(b.weight) > 0.001 and float(b.weight) < 0.999
		if not b.on:
			continue
		for side in 2:
			var second: float = ((_rows[i - 1]["ankle%d" % side] as Vector3) - 2.0 * (b["ankle%d" % side] as Vector3) + (_rows[i + 1]["ankle%d" % side] as Vector3)).length()
			on_stairs = maxf(on_stairs, second)
			if handing:
				hand_over = maxf(hand_over, second)
		if handing:
			pelvis = maxf(pelvis, absf(float((_rows[i - 1].hips as Vector3).y) - 2.0 * float((b.hips as Vector3).y) + float((_rows[i + 1].hips as Vector3).y)))
	return {"on_stairs": on_stairs, "hand_over": hand_over, "pelvis": pelvis}


func _stairs() -> void:
	world._select_character(0)
	await _wait(0.4)
	var near: Vector3 = world.traversal.stairs.low + Vector3(0.0, 0.0, -1.0)
	world.body.global_position = near
	await _wait(0.3)
	check(world.traversal.approaching_stairs() and not world.traversal.on_stairs, "One metre before the stairs she is approaching them")
	world.body.global_position = Vector3(0.0, 0.0, 0.0)
	await _wait(0.2)
	check(not world.traversal.approaching_stairs(), "Far from them she is not")
	var run: Dictionary = await _stair_walk(true, 3.0)
	check(float(run.hand_over) < 0.05 and float(run.pelvis) < 0.05, "A run up to the stairs hands over without a pop (ankle %.0f mm, pelvis %.0f mm per frame squared)" % [float(run.hand_over) * 1000.0, float(run.pelvis) * 1000.0])
	check(float(run.on_stairs) < 0.06, "...and stopping on them gathers the feet over several frames (worst frame %.0f mm)" % [float(run.on_stairs) * 1000.0])
	# The control: the earlier behaviour, no pace limit before the stairs and no slew of the speed the pose is given, pops.
	var old: Dictionary = await _control_without_limits()
	check(float(old.on_stairs) > 0.1, "Control: with the pace limit and the speed slew off, the same run pops (worst frame %.0f mm)" % [float(old.on_stairs) * 1000.0])
	if world.traversal.on_stairs:
		world.traversal._leave_stairs()


## The same run with the approach limit and the host's speed slew bypassed (the behaviour before this assignment), to show the check can fail.
func _control_without_limits() -> Dictionary:
	var host: ExplorationCharacterHost = world.visual
	host.stair_speed_slew = false
	world.traversal.limit_approach = false
	var result: Dictionary = await _stair_walk(true, 3.0)
	host.stair_speed_slew = true
	world.traversal.limit_approach = true
	return result


func _clean_view() -> void:
	var signs := world.get_tree().get_nodes_in_group(PlaygroundProps.SIGN_GROUP)
	check(signs.size() >= 6 and (signs[0] as Node3D).visible and world.hint_label.visible, "The station signs and the help text are shown by default")
	world.set_clean_view(true)
	check(not world.hint_label.visible and not world.state_label.visible and not (signs[0] as Node3D).visible, "The clean view hides the help text, the state line and the signs")
	world.set_clean_view(false)
	check(world.hint_label.visible and (signs[0] as Node3D).visible, "...and brings them back")
