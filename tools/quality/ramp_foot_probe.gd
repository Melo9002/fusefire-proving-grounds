extends SceneTree
## Feet on the Exploration Playground's ramp, measured in the FINAL pose (sampled at `skeleton_updated`, after every modifier and the leg IK), with the slope-aware foot placement off and on, for both characters and the
## movements a player makes: uphill, downhill, sideways (across the slope), diagonal, standing, and the walk on and off the ramp's ends. Per frame it takes the SUPPORTING foot (the lower of the two) and reports how far its
## ankle is above where a foot standing on the ground under it would have it (`ankle height`): negative is a foot sunk into the ground, positive a foot floating. These are ankle BONE heights against the ground's collision
## surface: not a mesh measurement (the sole's mesh is not sampled). The ankle rises and falls through a step (heel strike, toe-off), so the ground truth is the SAME walk on flat floor: `flat walk` is the reference, and a slope
## is placed correctly when its supporting-foot clearance has the flat walk's distribution (p5 = the deepest the supporting ankle gets, p50 = its usual height), whatever the slope.
##
##   godot_console --path . --script res://tools/quality/ramp_foot_probe.gd -- [json=<path>]
const PLAYGROUND := "res://research/exploration_playground/exploration_playground.tscn"
const RAMP_LOW_X := 8.0

var world: Node
var _errors: Array[float] = []
var _frames := 0
var _tilts: Array[float] = []
var _json := ""


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
	world = load(PLAYGROUND).instantiate()
	root.add_child(world)
	current_scene = world
	await _wait(1.0)
	var result := {}
	for character in [0, 1]:
		world._select_character(character)
		await _wait(0.5)
		for follow in [false, true]:
			world.visual.rig.set_ground_sampler(world.visual._sample_ground if follow else Callable())
			for movement in ["flat walk", "flat standing", "uphill", "downhill", "sideways", "diagonal", "standing"]:
				var key := "%s | %s | %s" % [["Regular", "Small"][character], "ground support ON" if follow else "off", movement]
				result[key] = await _measure(movement)
				print("RAMP %-52s supporting-ankle clearance p5 %+5.1f  p50 %+5.1f  p95 %+5.1f cm  (%d frames)" % [key, result[key].p5 * 100.0, result[key].p50 * 100.0, result[key].p95 * 100.0, result[key].frames])
	if _json != "":
		var file := FileAccess.open(_json, FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "\t"))
	quit()


func _skeleton_updated() -> void:
	var rig: CharacterRig = world.visual.rig
	var sk := rig.skeleton
	var heights: Array[float] = []
	var offset := 0.0
	var ankle_height: float = rig.stair_profile.ankle_height
	for side in 2:
		var bone: StringName = [rig.bones.left_leg, rig.bones.right_leg][side][2]
		var ankle: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin
		var ground: Dictionary = world.visual._sample_ground(ankle)
		if ground.is_empty():
			return
		heights.append(ankle.y - float(ground.y) - ankle_height)
		offset = maxf(offset, 0.0)
	_frames += 1
	_errors.append(minf(heights[0], heights[1]))


func _measure(movement: String) -> Dictionary:
	_errors = []
	_frames = 0
	var start := Vector3(7.0, 0.0, 8.0)
	var camera_yaw := PI   # forward is +Z at PI
	var keys: Array[StringName] = []
	match movement:
		"uphill":
			camera_yaw = -PI * 0.5   # forward is +X, up the ramp
			keys = [&"playground_forward"]
		"downhill":
			start = Vector3(13.0, 1.3, 8.0)
			camera_yaw = PI * 0.5
			keys = [&"playground_forward"]
		"sideways":
			start = Vector3(11.0, 0.7, 6.9)
			camera_yaw = -PI * 0.5
			keys = [&"playground_right"]   # across the slope, along +Z
		"diagonal":
			start = Vector3(8.2, 0.0, 6.9)
			camera_yaw = -PI * 0.5
			keys = [&"playground_forward", &"playground_right"]
		"flat walk":
			start = Vector3(-3.0, 0.0, -4.0)
			camera_yaw = -PI * 0.5
			keys = [&"playground_forward"]
		"flat standing":
			start = Vector3(-3.0, 0.0, -4.0)
			camera_yaw = -PI * 0.5
		"standing":
			start = Vector3(11.0, 0.7, 8.0)
			camera_yaw = -PI * 0.5
	world.body.global_position = start
	world.body.velocity = Vector3.ZERO
	world.yaw = camera_yaw
	world.pitch = 0.0
	world._apply_camera_rotation()
	world.visual.reset_motion(camera_yaw + PI)
	await _wait(0.6)
	var skeleton: Skeleton3D = world.visual.rig.skeleton
	var callable := _skeleton_updated
	skeleton.skeleton_updated.connect(callable)
	for key in keys:
		_press(key, true)
	await _wait(1.5 if movement == "sideways" else (2.2 if movement != "standing" else 1.2))
	for key in keys:
		_press(key, false)
	await _wait(0.3 if movement != "standing" else 0.1)
	skeleton.skeleton_updated.disconnect(callable)
	_errors.sort()
	var count := _errors.size()
	var at := func(q: float) -> float: return _errors[clampi(int(q * (count - 1)), 0, count - 1)] if count > 0 else 0.0
	return {"p5": at.call(0.05), "p50": at.call(0.5), "p95": at.call(0.95), "frames": count}
