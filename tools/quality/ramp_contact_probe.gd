extends SceneTree
## Foot CONTACT on the Exploration Playground's ramp, in the FINAL pose (sampled at `skeleton_updated`, after every modifier and the leg IK), through real input actions, with the ground-following placement off and on.
## Complements ramp_foot_probe (ankle height against a flat-walk reference): this one looks at the foot as a body, from bone positions:
##   heel / ball / toe-tip clearance  the sole's height above the ground under each of the three points (negative is a point inside the ground), the lowest of them per foot per frame
##   pitch error                      the foot's pitch against the slope of the ground along the foot's own direction (0 is a foot lying flat on the surface)
##   standing slide                   how far the lower foot's ankle travels over a stand
##   extension                        the farthest a leg is stretched, as a share of its length
##   airborne ground weight           the placement's weight while the body is off the ground (should have faded)
## Bone positions with fixed sole offsets, not a mesh measurement.
##
##   godot_console --path . --script res://tools/quality/ramp_contact_probe.gd -- [json=<path>]
const PLAYGROUND := "res://research/exploration_playground/exploration_playground.tscn"

var world: Node
var _json := ""
var _rows: Array[Dictionary] = []
var _hips: Array[float] = []
var _feet: SkinnedSurface
var _dump := ""
var _tag := ""
var _only := ""


func _initialize() -> void:
	_run.call_deferred()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _press(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


func _tap(action: StringName) -> void:
	_press(action, true)
	await _wait(0.1)
	_press(action, false)


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		var parts := String(argument).split("=", true, 1)
		if parts.size() == 2 and parts[0] == "json":
			_json = parts[1]
		elif parts.size() == 2 and parts[0] == "only":
			_only = parts[1].replace("_", " ")
		elif parts.size() == 2 and parts[0] == "dump":
			_dump = parts[1]   # per-frame CSV for every case (the series behind the summary)
	world = load(PLAYGROUND).instantiate()
	root.add_child(world)
	current_scene = world
	await _wait(1.0)
	var result := {}
	var cases := ["flat walk", "flat standing", "ramp entry", "ramp exit", "uphill", "downhill", "sideways", "diagonal", "standing", "stop", "turning", "crouching", "jump"]
	for character in [0, 1]:
		world._select_character(character)
		await _wait(0.5)
		for follow in [false, true]:
			world.visual.rig.set_ground_sampler(world.visual._sample_ground if follow else Callable())
			for case in cases:
				if _only != "" and _only != case:
					continue
				_tag = ["Regular", "Small"][character]
				var key := "%s | %s | %s" % [["Regular", "Small"][character], "ON" if follow else "off", case]
				result[key] = await _measure(case)
				var r: Dictionary = result[key]
				print("CONTACT %-34s MESH clearance min %+6.1f p5 %+5.1f p50 %+5.1f mm | below ground >5 mm: %3d of %3d frames | pitch err p50 %4.1f p95 %4.1f deg | slide %5.1f mm | ext %.3f | hips-ground %.3f..%.3f | airborne weight max %.2f" % [key, r.min * 1000.0, r.p5 * 1000.0, r.p50 * 1000.0, r.under, r.frames, r.pitch50, r.pitch95, r.slide * 1000.0, r.extension, r.hips_low, r.hips_high, r.air_weight])
	if _json != "":
		var file := FileAccess.open(_json, FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "\t"))
	quit()


func _sample() -> void:
	var rig: CharacterRig = world.visual.rig
	var sk := rig.skeleton
	var gt := sk.global_transform
	var ratio := rig.body_ratio()
	var row := {"clear": 1.0, "pitch": 0.0, "extension": 0.0, "lowest_ankle": Vector3.ZERO, "grounded": world.body.is_on_floor(), "weight": 0.0}
	if rig.traversal_modifier != null:
		row["weight"] = rig.traversal_modifier.input.ground_weight
	var lowest := INF
	for side in 2:
		var legs: Array = [rig.bones.left_leg, rig.bones.right_leg][side]
		var ankle: Vector3 = gt * sk.get_bone_global_pose(sk.find_bone(legs[2])).origin
		var toes: StringName = [rig.bones.left_toes, rig.bones.right_toes][side]
		var ball: Vector3 = gt * sk.get_bone_global_pose(sk.find_bone(toes)).origin
		var hip: Vector3 = gt * sk.get_bone_global_pose(sk.find_bone(legs[0])).origin
		row["extension"] = maxf(float(row.extension), hip.distance_to(ankle) / rig.stair_profile.leg_length)
		var direction := Vector3(ball.x - ankle.x, 0.0, ball.z - ankle.z)
		direction = direction.normalized() if direction.length() > 0.01 else Vector3.FORWARD
		var tip := ball + direction * 0.07 * ratio
		var heel := ankle - direction * 0.07 * ratio
		var heel_sole := ankle.y - rig.stair_profile.ankle_height
		var ball_sole := ball.y - 0.028 * ratio
		var clearance := 1.0
		# The sole is a line from the heel's sole to the ball's sole, carried on to the toe tip: on a tilted foot the tip's sole is higher or lower than the ball's.
		var run := maxf(Vector2(ball.x - heel.x, ball.z - heel.z).length(), 0.001)
		var sole_slope := (ball_sole - heel_sole) / run
		var tip_sole := ball_sole + sole_slope * Vector2(tip.x - ball.x, tip.z - ball.z).length()
		for pair in [[heel, heel_sole], [ball, ball_sole], [tip, tip_sole]]:
			var ground: Dictionary = world.visual._sample_ground(pair[0])
			if ground.is_empty():
				continue
			clearance = minf(clearance, float(pair[1]) - float(ground.y))
		row["clear%d" % side] = clearance
		var ground_here: Dictionary = world.visual._sample_ground(ankle)
		row["a" + "lr"[side]] = ankle
		row["g" + "lr"[side]] = float(ground_here.y) if not ground_here.is_empty() else NAN
		row["l" + "lr"[side]] = ankle.y - rig.stair_profile.ankle_height - (float(ground_here.y) if not ground_here.is_empty() else ankle.y)
		var under: Dictionary = world.visual._sample_ground(ankle)
		if not under.is_empty():
			var normal: Vector3 = under.normal
			var slope_along := -(normal.x * direction.x + normal.z * direction.z) / maxf(normal.y, 0.01)   # rise per metre along the foot's own direction
			var foot_pitch := (ball.y - ankle.y) / maxf(Vector2(ball.x - ankle.x, ball.z - ankle.z).length(), 0.001)
			row["pitch%d" % side] = absf(rad_to_deg(atan(foot_pitch) - atan(slope_along)))
		if ankle.y < lowest:
			lowest = ankle.y
			row["lowest_ankle"] = ankle
	# The foot MESH: every skinned vertex that follows the foot or toe bones, against the ground under it (the lowest is the deepest the visible foot goes into the surface).
	_feet.capture()
	var mesh_clear := 1.0
	for point in _feet.points():
		var world_point := gt * point
		var ground: Dictionary = world.visual._sample_ground(world_point)
		if not ground.is_empty():
			mesh_clear = minf(mesh_clear, world_point.y - float(ground.y))
	row["clear"] = mesh_clear
	row["pitch"] = maxf(float(row.get("pitch0", 0.0)), float(row.get("pitch1", 0.0)))
	var hips: Vector3 = gt * sk.get_bone_global_pose(sk.find_bone(rig.bones.hips)).origin
	var under_hips: Dictionary = world.visual._sample_ground(hips)
	row["hips_h"] = hips.y - float(under_hips.y) if not under_hips.is_empty() else NAN
	_rows.append(row)


func _setup(case: String) -> Dictionary:
	var start := Vector3(7.0, 0.0, 8.0)
	var yaw := -PI * 0.5   # forward is +X, up the ramp
	var keys: Array[StringName] = []
	var hold := 2.2
	match case:
		"uphill":
			keys = [&"playground_forward"]
		"ramp entry":
			start = Vector3(6.2, 0.0, 8.0)
			keys = [&"playground_forward"]
			hold = 1.2
		"ramp exit":
			start = Vector3(12.0, 1.0, 8.0)
			keys = [&"playground_forward"]
			hold = 1.6
		"downhill":
			start = Vector3(13.0, 1.3, 8.0)
			yaw = PI * 0.5
			keys = [&"playground_forward"]
		"sideways":
			start = Vector3(11.0, 0.7, 6.9)
			keys = [&"playground_right"]
			hold = 1.5
		"diagonal":
			start = Vector3(8.2, 0.0, 6.9)
			keys = [&"playground_forward", &"playground_right"]
		"standing":
			start = Vector3(11.0, 0.7, 8.0)
			hold = 1.2
		"stop", "turning", "crouching", "jump":
			start = Vector3(9.0, 0.3, 8.0)
			keys = [&"playground_forward"]
		"flat walk":
			start = Vector3(-3.0, 0.0, -4.0)
			keys = [&"playground_forward"]
		"flat standing":
			start = Vector3(-3.0, 0.0, -4.0)
			hold = 1.2
	return {"start": start, "yaw": yaw, "keys": keys, "hold": hold}


func _measure(case: String) -> Dictionary:
	_rows = []
	var plan := _setup(case)
	world.visual.set_crouched(false)
	world.body.global_position = plan.start
	world.body.velocity = Vector3.ZERO
	world.yaw = plan.yaw
	world.pitch = 0.0
	world._apply_camera_rotation()
	world.visual.reset_motion(float(plan.yaw) + PI)
	await _wait(0.6)
	var skeleton: Skeleton3D = world.visual.rig.skeleton
	var rig_bones: RigBones = world.visual.rig.bones
	_feet = SkinnedSurface.create(skeleton, [rig_bones.left_leg[2], rig_bones.right_leg[2], rig_bones.left_toes, rig_bones.right_toes], 0.5)
	var callable := _sample
	skeleton.skeleton_updated.connect(callable)
	var first := Vector3.ZERO
	for key in plan.keys:
		_press(key, true)
	match case:
		"stop":
			await _wait(1.0)
			for key in plan.keys:
				_press(key, false)
			await _wait(1.2)
		"turning":
			await _wait(0.6)
			for i in 12:
				world.yaw += 0.13
				world._apply_camera_rotation()
				await _wait(0.06)
			await _wait(0.4)
		"crouching":
			await _wait(0.5)
			world.visual.set_crouched(true)
			await _wait(1.3)
			world.visual.set_crouched(false)
		"jump":
			await _wait(0.5)
			await _tap(&"playground_cover")
			await _wait(1.4)
		_:
			if case == "standing" or case == "flat standing":
				first = world.visual.rig.skeleton.global_transform * Vector3.ZERO
			await _wait(float(plan.hold))
	for key in plan.keys:
		_press(key, false)
	await _wait(0.3)
	skeleton.skeleton_updated.disconnect(callable)
	if _dump != "":
		var file := FileAccess.open("%s_%s_%s_%s.csv" % [_dump, _tag, "on" if world.visual.rig.ground_sampler.is_valid() else "off", case.replace(" ", "_")], FileAccess.WRITE)
		file.store_line("mesh_clear,ground_weight,grounded,ankle_l_y,ankle_r_y,ground_l,ground_r,lift_l,lift_r")
		for row in _rows:
			file.store_line("%f,%f,%d,%f,%f,%f,%f,%f,%f" % [row.clear, row.weight, 1 if row.grounded else 0, row.al.y, row.ar.y, row.gl, row.gr, row.ll, row.lr])
	return _summarise(case)


func _summarise(case: String) -> Dictionary:
	var clearances: Array[float] = []
	var pitches: Array[float] = []
	var under := 0
	var extension := 0.0
	var hips_low := 9.0
	var hips_high := -9.0
	var air_weight := 0.0
	var slide := 0.0
	var anchor := Vector3.INF
	for row in _rows:
		clearances.append(float(row.clear))
		pitches.append(float(row.pitch))
		if float(row.clear) < -0.005:
			under += 1
		extension = maxf(extension, float(row.extension))
		if not is_nan(float(row.hips_h)):
			hips_low = minf(hips_low, float(row.hips_h))
			hips_high = maxf(hips_high, float(row.hips_h))
		if not bool(row.grounded):
			air_weight = maxf(air_weight, float(row.weight))
		if case == "standing" or case == "flat standing":
			if anchor == Vector3.INF:
				anchor = row.lowest_ankle
			slide = maxf(slide, (row.lowest_ankle as Vector3).distance_to(anchor))
	clearances.sort()
	pitches.sort()
	var count := clearances.size()
	var at := func(values: Array[float], q: float) -> float: return values[clampi(int(q * (count - 1)), 0, count - 1)] if count > 0 else 0.0
	return {"min": clearances[0] if count > 0 else 0.0, "p5": at.call(clearances, 0.05), "p50": at.call(clearances, 0.5), "under": under, "frames": count, "pitch50": at.call(pitches, 0.5), "pitch95": at.call(pitches, 0.95), "slide": slide, "extension": extension, "hips_low": hips_low, "hips_high": hips_high, "air_weight": air_weight}
