extends SceneTree
## The hand-over between ordinary locomotion and the stair pose, in the FINAL pose (sampled at `skeleton_updated`). Walks onto the Exploration Playground's staircase from the flat, up it and off the top (and the reverse),
## and records per frame the pelvis and both ankles in world space, the stair pose's weight and whether the stair pose is active. A discontinuity is a frame-to-frame change that the surrounding frames do not explain:
## the probe reports the largest SECOND difference (change of velocity, per frame) of the pelvis height and of each ankle, where it happened (the stair weight and progress at that frame), so a pop at the hand-over is
## told apart from the ordinary rhythm of a step. Bone positions, not a mesh measurement.
##
##   godot_console --path . --script res://tools/quality/stair_transition_probe.gd -- [json=<path>] [dump=<path>]
const PLAYGROUND := "res://research/exploration_playground/exploration_playground.tscn"

var world: Node
var _rows: Array[Dictionary] = []
var _json := ""
var _dump := ""
var _limit := -1.0
var _cap := true
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


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		var parts := String(argument).split("=", true, 1)
		if parts.size() == 2 and parts[0] == "json":
			_json = parts[1]
		elif parts.size() == 2 and parts[0] == "dump":
			_dump = parts[1]
		elif parts.size() == 2 and parts[0] == "cap":
			_cap = parts[1] != "0"   # cap=0 removes the playground's approach pace limit (the control)
		elif parts.size() == 2 and parts[0] == "only":
			_only = parts[1].replace("_", " ")
		elif parts.size() == 2 and parts[0] == "limit":
			_limit = float(parts[1])   # the stair foot speed limit (m/s); 0 = the plan shown exactly (the unlimited control)
	world = load(PLAYGROUND).instantiate()
	root.add_child(world)
	current_scene = world
	await _wait(1.0)
	var result := {}
	for character in [0, 1]:
		world._select_character(character)
		await _wait(0.5)
		if _limit >= 0.0:
			world.visual.rig.stair_profile.max_foot_speed = _limit
		world.traversal.limit_approach = _cap
		for case in ["walk up", "walk down", "run up", "stop and resume"]:
			if _only != "" and _only != case:
				continue
			var key := "%s | %s" % [["Regular", "Small"][character], case]
			result[key] = await _measure(case)
			var r: Dictionary = result[key]
			print("STAIR %-24s hand-over frames %3d: pelvis jump %5.1f mm, ankle jump %5.1f mm | on the stairs, any frame: ankle %5.1f mm | whole walk: pelvis %5.1f mm (weight %.2f), ankle %5.1f mm (weight %.2f, s %.2f) | fastest ankle %.2f m/s" % [key, r.hand_frames, r.hand_pelvis * 1000.0, r.hand_ankle * 1000.0, r.on_stairs_ankle * 1000.0, r.pelvis_jump * 1000.0, r.pelvis_weight, r.ankle_jump * 1000.0, r.ankle_weight, r.ankle_s, r.foot_speed])
	if _json != "":
		var file := FileAccess.open(_json, FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "\t"))
	quit()


func _sample() -> void:
	var rig: CharacterRig = world.visual.rig
	var sk := rig.skeleton
	var row := {"t": Time.get_ticks_usec() / 1e6, "hips": sk.global_transform * sk.get_bone_global_pose(sk.find_bone(rig.bones.hips)).origin}
	for side in 2:
		var bone: StringName = [rig.bones.left_leg, rig.bones.right_leg][side][2]
		row["ankle%d" % side] = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin
	row["weight"] = rig.stairs.pose.weight if rig.stairs != null and rig.stairs.pose != null else 0.0
	row["on"] = rig.stairs != null
	row["s"] = world.traversal.stairs.progress_of(world.body.global_position)
	_rows.append(row)


func _measure(case: String) -> Dictionary:
	_rows = []
	if world.traversal.on_stairs:
		world.traversal._leave_stairs()
	world.visual.set_crouched(false)
	var stairs: StairModel = world.traversal.stairs
	var camera_yaw := PI
	var start := stairs.low + Vector3(0.0, 0.0, -2.2)
	var run := false
	var duration := 4.6
	if case == "walk down":
		start = stairs.low + Vector3(0.0, 2.05, 2.0 + stairs.tread_depth * stairs.count)
		camera_yaw = 0.0
	elif case == "run up":
		run = true
		duration = 3.6
	world.body.global_position = start
	world.body.velocity = Vector3.ZERO
	world.yaw = camera_yaw
	world.pitch = 0.0
	world._apply_camera_rotation()
	world.visual.reset_motion(camera_yaw + PI)
	await _wait(0.8)
	var callable := _sample
	world.visual.rig.skeleton.skeleton_updated.connect(callable)
	_press(&"playground_forward", true)
	_press(&"playground_run", run)
	if case == "stop and resume":
		await _wait(2.4)
		_press(&"playground_forward", false)
		await _wait(0.9)
		_press(&"playground_forward", true)
		await _wait(1.0)
		_press(&"playground_forward", false)
		await _wait(0.9)
		_press(&"playground_forward", true)
		duration = 0.6
	await _wait(duration)
	_press(&"playground_forward", false)
	_press(&"playground_run", false)
	await _wait(0.4)
	world.visual.rig.skeleton.skeleton_updated.disconnect(callable)
	var pelvis_jump := 0.0
	var pelvis_weight := 0.0
	var pelvis_s := 0.0
	var ankle_jump := 0.0
	var ankle_weight := 0.0
	var ankle_s := 0.0
	var stair_frames := 0
	var worst := 0.0
	var hand_frames := 0
	var hand_pelvis := 0.0
	var hand_ankle := 0.0
	var foot_speed := 0.0
	for i in range(1, _rows.size()):
		var dt := float(_rows[i].t) - float(_rows[i - 1].t)
		if dt > 0.004 and _rows[i].on and _rows[i - 1].on:
			for side in 2:
				foot_speed = maxf(foot_speed, ((_rows[i]["ankle%d" % side] as Vector3) - (_rows[i - 1]["ankle%d" % side] as Vector3)).length() / dt)
	for i in range(1, _rows.size() - 1):
		var a: Dictionary = _rows[i - 1]
		var b: Dictionary = _rows[i]
		var c: Dictionary = _rows[i + 1]
		if b.on:
			stair_frames += 1
		# second difference of the pelvis HEIGHT (a step's own rhythm is smooth; a pop is a spike)
		var second := absf(float(a.hips.y) - 2.0 * float(b.hips.y) + float(c.hips.y))
		if second > pelvis_jump:
			pelvis_jump = second
			pelvis_weight = float(b.weight)
			pelvis_s = float(b.s)
		var handing_over := float(b.weight) > 0.001 and float(b.weight) < 0.999
		if handing_over:
			hand_frames += 1
			hand_pelvis = maxf(hand_pelvis, second)
		for side in 2:
			var second_ankle: float = ((a["ankle%d" % side] as Vector3) - 2.0 * (b["ankle%d" % side] as Vector3) + (c["ankle%d" % side] as Vector3)).length()
			if handing_over:
				hand_ankle = maxf(hand_ankle, second_ankle)
			if b.on:
				worst = maxf(worst, second_ankle)
			if second_ankle > ankle_jump:
				ankle_jump = second_ankle
				ankle_weight = float(b.weight)
				ankle_s = float(b.s)
	if _dump != "":
		var file := FileAccess.open(_dump + "_" + case.replace(" ", "_") + ".csv", FileAccess.WRITE)
		file.store_line("t,hips_y,a0x,a0y,a0z,a1x,a1y,a1z,weight,on,s")
		for row in _rows:
			file.store_line("%f,%f,%f,%f,%f,%f,%f,%f,%f,%d,%f" % [row.t, row.hips.y, row.ankle0.x, row.ankle0.y, row.ankle0.z, row.ankle1.x, row.ankle1.y, row.ankle1.z, row.weight, 1 if row.on else 0, row.s])
	return {"pelvis_jump": pelvis_jump, "pelvis_weight": pelvis_weight, "pelvis_s": pelvis_s, "ankle_jump": ankle_jump, "ankle_weight": ankle_weight, "ankle_s": ankle_s, "frames": _rows.size(), "stair_frames": stair_frames, "hand_frames": hand_frames, "hand_pelvis": hand_pelvis, "hand_ankle": hand_ankle, "on_stairs_ankle": worst, "foot_speed": foot_speed}
